require 'locomotive/common'
require 'locomotive/steam'
require 'pg'

module Spec
  module Helpers

    def reset!
      FileUtils.rm_rf(File.expand_path('../../../site', __FILE__))
    end

    def remove_logs
      FileUtils.rm_rf(File.join(default_fixture_site_path, 'log'))
    end

    def setup_common(logger_output = nil)
      Locomotive::Common.reset
      Locomotive::Common.configure do |config|
        config.notifier = Locomotive::Common::Logger.setup(logger_output)
      end
    end

    def run_server
      require 'haml'

      output = ENV['STEAM_VERBOSE'] ? nil : File.join(default_fixture_site_path, 'log/steam.log')
      setup_common(output)

      Locomotive::Common::Logger.info 'Server started...'
      Locomotive::Steam::Server.to_app
    end

    def sign_in(params, follow_redirect = false)
      post '/account', params
      follow_redirect! if follow_redirect
      last_response
    end

    def sign_up(params, follow_redirect = false)
      post '/account/register', params
      follow_redirect! if follow_redirect && is_redirect
      last_response
    end

    def sign_out(follow_redirect = false, path='/account')
      post path, {
        'auth_action': 'sign_out',
        'auth_content_type': 'customers',
      }
      follow_redirect! if follow_redirect && is_redirect
      last_response
    end

    def is_redirect
      [301, 302].include?(last_response.status)
    end

    def add_an_address(params, referer, follow_redirect = false, json = false)
      header 'Referer', referer
      if json
        header 'Content-type', "application/json"
        params = params.to_json
      else
        header 'Accept', "text/html,*/*;q=0.01"
      end
      post '/invader/addresses/create', params
      follow_redirect! if follow_redirect
      last_response
    end

    def remove_addresses
      header 'Content-type', "application/json"
      get '/invader/addresses?per_page=200&scope[address_type]=address'
      addresses = JSON.parse(last_response.body)
      if addresses
        addresses['data'].each do | address |
          delete "/invader/addresses/#{address['id']}"
        end
      end
    end

    def session
      last_request.env['rack.session']
    end

    def xml2id(xml_id)
      conn = PG.connect
      res = conn.exec_params(
        "SELECT res_id FROM ir_model_data WHERE module=$1 and name=$2",
        xml_id.split('.'))
      res[0]['res_id'].to_i
    end

    def add_item_to_cart(product_xml_id)
      product_id = xml2id(product_xml_id)
      post '/invader/cart/add_item', { product_id: product_id, item_qty: 1 }
    end

  end
end

def default_fixture_site_path
  'spec/integration/template'
end

Locomotive::Steam.configure do |config|
  config.mode           = :test
  config.adapter        = { name: :filesystem, path: default_fixture_site_path }
  config.asset_path     = File.expand_path(File.join(default_fixture_site_path, 'public'))
  config.serve_assets   = true
  config.minify_assets  = true
end

