module ShopInvader
  module Middlewares
    class Download < Locomotive::Steam::Middlewares::ThreadSafe

      include Locomotive::Steam::Middlewares::Concerns::Helpers

      BASE_STRING = '/_store/download/'.freeze
      PATH_REGEXP = /#{BASE_STRING}(.*)/mo.freeze

      def _call
        if path.start_with?(BASE_STRING)
          attachment_path = path.match(PATH_REGEXP)[1]
          filename        = File.basename(path)

          if response = service.download(attachment_path)
            @next_response = [
              200,
              {
                'Content-Type'        => response.headers['content-type'],
                'Content-Length'      => response.headers['content-length'],
                'Content-Disposition' => "attachment; filename=\"#{filename}\""
              },
              [response.body]
            ]
          end
        end
      end

      private

      def path
        request.path_info
      end

      def service
        services.erp
      end

    end
  end
end
