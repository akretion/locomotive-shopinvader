module ShopInvader
  module Services
    module Concerns

      module SearchEngine
        include ShopInvader::Services::Concerns::LocaleMapping

        KEY_ATTRIBUTES = %w(url_key redirect_url_key).freeze

        # TODO filter allowed operator
        ALLOWED_OPERATORS = %w(gt gte lt lte ne nin).freeze
        # TODO add support of "in"

        private

        def find_index_name(name)
          settings = indices.detect { |settings| settings['name'] == name }
          build_index_name(settings["index"], @locale)
        end

        def build_index_name(index, locale)
          "#{index}_#{map_locale(locale.to_s)}".downcase
        end

        def build_attr(name, value)
          if value.is_a?(Hash)
            result = []
            value.each do | key, val |
               subname = "#{name}.#{key}"
               result.concat(build_attr(subname, val))
            end
            result
          else
            [[name, value]]
          end
        end

      end

    end
  end
end
