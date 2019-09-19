require 'locomotive/steam'
require 'locomotive/steam/server'
require 'algoliasearch'
require 'elasticsearch'

require 'shop_invader/version'
require 'shop_invader/errors'
require 'shop_invader/services'
require 'shop_invader/services/concerns/locale'
require 'shop_invader/services/concerns/search_engine'
require 'shop_invader/services/algolia_service'
require 'shop_invader/services/elastic_service'
require 'shop_invader/services/search_engine_service'
require 'shop_invader/services/erp_service'
require 'shop_invader/services/erp_auth_service'
require 'shop_invader/services/action_service'
require 'shop_invader/middlewares/templatized_page'
require 'shop_invader/middlewares/erp_proxy'
require 'shop_invader/middlewares/store'
require 'shop_invader/middlewares/renderer'
require 'shop_invader/middlewares/locale'
require 'shop_invader/middlewares/snippet'
require 'shop_invader/middlewares/helpers'
require_relative_all %w(concerns concerns/sitemap), 'shop_invader/middlewares'
require_relative_all %w(. drops filters tags tags/concerns), 'shop_invader/liquid'
require 'shop_invader/steam_patches'
require 'faraday'

def should_notify_erp(payload)
  payload[:request].env['steam.site'].metafields.include?('erp') && payload[:entry].content_type.slug.downcase == 'customers'
end

module ShopInvader

  # Locales mapping table. Locomotive only uses the
  # main locale but not the dialect. This behavior
  # will change in Locomotive v4.
  LOCALES = {
    'ar' => 'ar_SY',
    'bg' => 'bg_BG',
    'ca' => 'ca_ES',
    'cs' => 'cs_CZ',
    'da' => 'da_DK',
    'de' => 'de_DE',
    'el' => 'el_GR',
    'en' => 'en_US',
    'es' => 'es_ES',
    'et' => 'et_EE',
    'fa-IR' => 'fa_IR',
    'fi-FI' => 'fi_FI',
    'fr' => 'fr_FR',
    'hr' => 'hr_HR',
    'it' => 'it_IT',
    'ja-JP' => 'ja_JP',
    'ko' => 'ko_KR',
    'lt' => 'lt_LT',
    'lv' => 'lv_LV',
    'nb' => 'nb_NO',
    'nl' => 'nl_NL',
    'pl-PL' => 'pl_PL',
    'pt' => 'pt_PT',
    'ru' => 'ru_RU',
    'sk' => 'sk_SK',
    'sl' => 'sl_SL',
    'sr' => 'sr_RS',
    'sv' => 'sv_SE',
    'uk' => 'uk_UA',
    'vi' => 'vi_VN',
    'zh-CN' => 'zh_CN',
  }

  def self.setup
    Locomotive::Steam.configure do |config|
      config.middleware.insert_after Locomotive::Steam::Middlewares::TemplatizedPage, ShopInvader::Middlewares::TemplatizedPage
      config.middleware.insert_before Locomotive::Steam::Middlewares::Path, ShopInvader::Middlewares::Store
      config.middleware.insert_after Locomotive::Steam::Middlewares::Path, ShopInvader::Middlewares::ErpProxy
      config.middleware.insert_after Locomotive::Steam::Middlewares::Path, ShopInvader::Middlewares::SnippetPage
    end

    subscribe_to_steam_notifications
  end


  def self.subscribe_to_steam_notifications

    # new signups
    ActiveSupport::Notifications.subscribe('steam.auth.signed_up') do |name, start, finish, id, payload|
      service = Locomotive::Steam::Services.build_instance(payload[:request])
      if should_notify_erp(payload)
        service.erp_auth.signed_up(payload[:entry])
      end
    end

    ActiveSupport::Notifications.subscribe('steam.auth.signed_in') do |name, start, finish, id, payload|
      service = Locomotive::Steam::Services.build_instance(payload[:request])
      if should_notify_erp(payload)
        payload[:request].env['steam.authenticated_entry'] = payload[:entry]
        service.erp_auth.signed_in(payload[:entry])
      end
    end

    ActiveSupport::Notifications.subscribe('steam.auth.reset_password') do |name, start, finish, id, payload|
      service = Locomotive::Steam::Services.build_instance(payload[:request])
      if should_notify_erp(payload)
        payload[:request].env['steam.authenticated_entry'] = payload[:entry]
        service.erp_auth.reset_password(payload[:entry])
      end
    end

    ActiveSupport::Notifications.subscribe('steam.auth.signed_out') do |name, start, finish, id, payload|
      service = Locomotive::Steam::Services.build_instance(payload[:request])
      if should_notify_erp(payload)
        service.erp_auth.sign_out(payload[:entry])
      end
    end
  end
end

# The Rails app must call the setup itself.
unless defined?(Rails)
  # context here: Wagon site
  ShopInvader.setup
end
