module ShopInvader
  class SearchEngineService
    attr_reader :adapter

    def initialize(site, locale, elastic, algolia)
      if elastic.is_configured?
        @adapter = elastic
      elsif algolia.is_configured?
        @adapter = algolia
      else
        @adapter = nil
      end
    end

    def find_all_products_and_categories
      @adapter.find_all_products_and_categories
    end

    def find_by_key(name, key)
      @adapter.find_by_key(name, key)
    end

    def routes
      @adapter.routes
    end

    def indices
      @adapter.indices
    end

    def find_all(name, conditions: nil, page: 1, per_page: 20)
      @adapter.find_all(name, conditions: conditions, page: page, per_page: per_page)
    end

  end
end
