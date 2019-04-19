module ShopInvader
  module Middlewares
    class ErpProxy < Locomotive::Steam::Middlewares::ThreadSafe

      include Locomotive::Steam::Middlewares::Concerns::Helpers

      def _call
        if env['steam.path'].start_with?('_store/')
          path = env['steam.path'].sub('_store/', '')
          response = erp.call(env['REQUEST_METHOD'], path, params)
          if response.include?('redirect_to')
            redirect_to response['redirect_to'], 302
          else
            render_response(JSON.dump(response), 200, 'application/json')
          end
        elsif params && params.include?('action_proxy')
          if params.include?('action_method')
            method = params.delete('action_method').upcase
          else
            method = env['REQUEST_METHOD']
          end
          path = params.delete('action_proxy')
          begin
            response = erp.call(method, path, params)
          rescue ShopInvader::ErpMaintenance => e
            env['steam.liquid_assigns']['store_maintenance'] = true
            response = {error: true}
          end
          if not response.include?(:error)
            if response.include?('redirect_to')
              redirect_to response['redirect_to'], 302
            elsif params.include?('redirect_success_to')
              redirect_to params['redirect_success_to'], 302
            end
          end
        end
      end

      private

      def erp
        services.erp
      end

    end
  end
end
