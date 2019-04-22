module ShopInvader
  module Middlewares
    class ErpProxy < Locomotive::Steam::Middlewares::ThreadSafe

      include Locomotive::Steam::Middlewares::Concerns::Helpers
      include Locomotive::Steam::Middlewares::Concerns::Recaptcha

      def _call
        if env['steam.path'].start_with?('invader/')
          if recaptcha_proxy_required? && !recaptcha_proxy_valid?
            if html_form_edition
              redirect_to params['invader_error_url'], 302
            else
              render_response("{'recaptcha_invalid': true}", 200, 'application/json')
            end
          end
          response = erp.call_without_parsing(env['REQUEST_METHOD'], path, params)
          if response.status == 200 && response.headers["content-type"] != "application/json"
            _render_download(response)
          elsif force_redirection || html_form_edition
            _process_redirection(response)
          else
            _render_json(response)
          end
        end
      end

      def _render_download(response)
        headers = response.headers
        @next_response = [
            200,
            {
              'Content-Type' => headers['content-type'],
              'Content-Disposition' => headers['content-disposition'],
              'Content-Length' => headers['content-length'],
            },
            [response.body]
        ]
      end

      def _render_json(response)
        if response.status == 200
          data = erp.parse_response(response)
          render_response(JSON.dump(data), 200, 'application/json')
        else
          # We do not catch the error here as this should be done
          # by the code that call this end point
          render_response(response.body, response.status, 'application/json')
        end
      end

      def _process_redirection(response)
        if response.status == 200
          data = erp.parse_response(response)
          if data.include?('redirect_to')
            redirect_to data['redirect_to'], 302
          elsif params.include?('invader_success_url')
            redirect_to params['invader_success_url'], 302
          else
            redirect_to env['HTTP_REFERER'], 302
          end
        else
          erp.catch_error(response)
          if params.include?('invader_error_url')
            redirect_to params['invader_error_url'], 302
          else
            redirect_to env['HTTP_REFERER'], 302
          end
        end
      end

      private

      def recaptcha_required?
        ['PUT', 'POST'].include?(env['REQUEST_METHOD']) && recaptcha_procy_protected
      end

      def path
        @path |= env['steam.path'].sub('invader/', '')
      end

      def force_redirection
        # the check_payment path always need to render an html page
        # as this is the redirection done by the payment provider
        # we keep it for compatibility reason but it's better to use
        # the params "force_apply_redirection"
        params.include?('force_apply_redirection') || path.include?('check_payment')
      end

      def html_form_edition
        # if you do a post/put/delete from the browse directly with a basic html form
        # we process it as an html edition and we will do the redirection
        # parsing the http_accept is done in a simple way here
        accept = parse_http_accept_header(request.get_header('HTTP_ACCEPT'))
        if accept.size > 0
          accept[0][0] == "text/html" && (request.post? || request.delete? || request.put?)
        end
      end

      def erp
        services.erp
      end

      def parse_http_accept_header(header)
        header.to_s.split(/\s*,\s*/).map do |part|
          attribute, parameters = part.split(/\s*;\s*/, 2)
          quality = 1.0
          if parameters and /\Aq=([\d.]+)/ =~ parameters
            quality = $1.to_f
          end
          [attribute, quality]
        end
      end

    end
  end
end
