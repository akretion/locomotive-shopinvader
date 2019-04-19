module ShopInvader
  module Middlewares
    class Store < Locomotive::Steam::Middlewares::ThreadSafe

      include Locomotive::Steam::Middlewares::Concerns::Helpers

      def _call
        liquid_assigns['store'] = ShopInvader::Liquid::Drops::Store.new
      end

    end
  end
end
