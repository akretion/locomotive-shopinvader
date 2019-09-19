module ShopInvader
  class AlgoliaService

    include ShopInvader::Services::Concerns::SearchEngine

    NUMERIC_OPERATORS = {
      nil   => '=',
      'gt'  => '>',
      'gte' => '>=',
      'lt'  => '<',
      'lte' => '<=',
      'ne'  => '!='
    }.freeze

    attr_reader :indices, :site, :routes

    def initialize(site, customer, locale)
      @site         = site
      @customer     = customer
      @locale       = locale
      if is_configured?
        @indices      = JSON.parse(site.metafields.dig('algolia', 'indices') || '[]')
        @credentials  = site.metafields['algolia'].slice('application_id', 'api_key').symbolize_keys
        @client       = Algolia::Client.new(@credentials)
        @routes       = JSON.parse(site.metafields.dig('algolia', 'routes') || '[]')
      else
        @indices    = []
        @credentials= nil
        @client     = nil
        @routes     = []
      end
    end

    def is_configured?
     !!@site.metafields['algolia']
    end

    def find_all_products_and_categories
      indices.map do |config|
        {}.tap do |records|
          site.locales.each do |locale|
            index   = Algolia::Index.new(build_index_name(config['index'], locale.to_s), @client)
            filters = ''
            if config['have_variant']
                filter = 'main: true'
            end
            params = {
               query: '',
               attributesToRetrieve: 'name,objectID,url_key',
               filters: filter,
            }
            index.browse(params) do |hit|
              record = records[hit['objectID']] ||= {}
              record[locale] = { name: hit['name'], url: find_route(config['name']).gsub('*', hit['url_key']) }
            end
          end
        end.values
      end.flatten
    end

    def find_all(name, conditions: nil, page: 0, per_page: 20)
      response = find_index(name).search('',
        build_params(conditions || {}).merge({
          page:         page,
          hitsPerPage:  per_page
        })
      )
      response = _parse_response(response)
      {
        data: response['hits'].map { |hit| hit['index_name'] = name; hit },
        size: response['nbHits']
      }
    end

    def find_by_key(name, key)
      _find_by_key(find_index(name), name, key)
    end

    private

    def _parse_response(response)
      if @customer
        role = @customer.role
      end
      role ||= @site.metafields['erp']['default_role']
      response['hits'].each do |hit|
        if hit.include?('price')
          hit['price'] = hit['price'][role]
        end
      end
      response
    end

    def _find_by_key(index, name, key)
      response = index.search('', {
        filters: "(url_key:#{key} OR redirect_url_key:#{key})",
        distinct: 0,
      })
      response = _parse_response(response)
      resource = nil
      # look for the main product/category AND its variants
      response['hits'].each do |hit|
        hit['index_name'] = name
        if resource.nil?
          resource = hit
        else
          (resource['variants'] ||= []) << hit
        end
      end
      resource
    end

    def find_index(name)
      Algolia::Index.new(find_index_name(name), @client)
    end

    def build_params(conditions)
      { numericFilters: [], facetFilters: [] }.tap do |params|
        conditions.each do |key, value|
          name, op = key.split('.')
          build_attr(name, value).each do | name, value |
            if value.is_a?(Numeric)
              params[:numericFilters] << "#{name} #{NUMERIC_OPERATORS[op] || '='} #{value}"
            else
              [*value].each do |_value|
                if _value.is_a?(Numeric) && op == 'nin'
                  params[:numericFilters] << "#{name} != #{_value}"
                else
                  params[:facetFilters] << "#{op == 'ne' ? 'NOT ' : ''}#{name}:#{_value}"
                end
              end
            end
          end
        end
      end
    end

    # For compatibility reason for now we do not use the generic method
    # as we want to keep the case sensitive
    # will be removed soon
    def build_index_name(index, locale)
      "#{index}_#{map_locale(locale.to_s)}"
    end

    def find_route(index_name)
      @routes ||= JSON.parse(site.metafields.dig('algolia', 'routes')  || '[]')
      (@routes.find { |(route, rule)| rule['index'] == index_name }).try(:first)
    end

  end
end
