require 'locomotive/steam'
require 'locomotive/steam/server'
require 'algoliasearch'

require 'shop_invader/version'
require 'shop_invader/errors'
require 'shop_invader/services'
require 'shop_invader/services/algolia_service'
require 'shop_invader/services/erp_service'
require 'shop_invader/services/action_service'
require 'shop_invader/middlewares/templatized_page'
require 'shop_invader/middlewares/erp_proxy'
require 'shop_invader/middlewares/store'
require 'shop_invader/middlewares/renderer'
require 'shop_invader/middlewares/locale'
require_relative_all %w(concerns concerns/sitemap), 'shop_invader/middlewares'
require_relative_all %w(. drops filters tags tags/concerns), 'shop_invader/liquid'
require 'shop_invader/steam_patches'
require 'faraday'
require 'rack-utm'

module ShopInvader

  # Locales mapping table. Locomotive only uses the
  # main locale but not the dialect. This behavior
  # might change in Locomotive v4.
  LOCALES = {
    'fr' => 'fr_FR',
    'en' => 'en_US',
    'es' => 'es_ES',
    'it' => 'it_IT',
  }

  def self.setup
    Locomotive::Steam.configure do |config|
      config.middleware.insert_after Locomotive::Steam::Middlewares::Site, Rack::Utm
      config.middleware.insert_after Locomotive::Steam::Middlewares::TemplatizedPage, ShopInvader::Middlewares::TemplatizedPage
      config.middleware.insert_after ShopInvader::Middlewares::TemplatizedPage, ShopInvader::Middlewares::Store
      config.middleware.insert_after Locomotive::Steam::Middlewares::Path, ShopInvader::Middlewares::ErpProxy
    end

    subscribe_to_steam_notifications
  end

  def self.subscribe_to_steam_notifications
    # new signups
    ActiveSupport::Notifications.subscribe('steam.auth.signed_up') do |name, start, finish, id, payload|
      request = payload[:request]
      entry = payload[:entry]
      service = Locomotive::Steam::Services.build_instance(payload[:request])
      params = request.params.clone
      params.update({
          'external_id': entry._id,
          'email': entry.email
          })

      %w(auth_action auth_disable_email auth_content_type auth_id_field
         auth_password_field auth_email_handle auth_callback auth_entry).each do | key |
        params.delete(key)
      end
      rollback = false
      begin
        if params.include?('auth_guest_signup')
          register_params = {
            'external_id': entry._id,
            # TODO it will be better to not pass this arg, we will discusse about it
            # on odoo side then remove this comment of teh email here
            'email': entry.email
          }
          data = service.erp.call('POST', 'guest/register', register_params)
        else
          data = service.erp.call('POST', 'customer', params)
        end
      rescue ShopInvader::ErpMaintenance => e
        request.env['steam.liquid_assigns']['store_maintenance'] = true
        rollback = true
      else
        if data.include?(:error)
          rollback = true
        else
          unless data.include?('role')
            data['role'] = request.env['steam.site'].metafields['erp']['default_role']
          end
          vals = {}
          current_vals = entry.to_hash
          data.each do |key, val|
            if current_vals.include?(key) && current_vals[key] != data[key]
              vals[key] = val
            end
          end
          service.content_entry.update_decorated_entry(entry, vals)
        end
      end
      if rollback
        # Drop the content created (no rollback on mongodb)
        service.content_entry.delete(entry.content_type_slug, entry._id)
        # Add a fake error field to avoid content authentification
        entry.errors.add('error', 'Fail to create')
      end
    end

    ActiveSupport::Notifications.subscribe('steam.auth.signed_in') do |name, start, finish, id, payload|
      service = Locomotive::Steam::Services.build_instance(payload[:request])
      payload[:request].env['authenticated_entry'] = payload[:entry]
      begin
        service.erp.initialize_customer
      rescue ShopInvader::ErpMaintenance => e
        # TODO add special logging
      end
    end

    ActiveSupport::Notifications.subscribe('steam.auth.reset_password') do |name, start, finish, id, payload|
      service = Locomotive::Steam::Services.build_instance(payload[:request])
      payload[:request].env['authenticated_entry'] = payload[:entry]
      begin
        service.erp.initialize_customer
      rescue ShopInvader::ErpMaintenance => e
        # TODO add special logging
      end
    end

    ActiveSupport::Notifications.subscribe('steam.auth.signed_out') do |name, start, finish, id, payload|
      # After signed out, drop the erp / store session
      session = payload[:request].env['rack.session']
      session.keys.each do | key |
        if key.start_with?('erp_') || key.start_with?('store_')
          session.delete(key)
        end
      end
    end
  end
end

# The Rails app must call the setup itself.
unless defined?(Rails)
  # context here: Wagon site
  ShopInvader.setup
end
