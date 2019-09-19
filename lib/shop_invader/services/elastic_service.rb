module ShopInvader
  class ElasticService

    include ShopInvader::Services::Concerns::SearchEngine


    attr_reader :indices, :site, :routes

    def initialize(site, customer, locale)
      @site         = site
      @customer     = customer
      @locale       = locale
      if is_configured?
        @indices      = JSON.parse(site.metafields.dig('elasticsearch', 'indices') || '[]')
        @client       = Elasticsearch::Client.new hosts: @site.metafields.dig('elasticsearch', 'url')
        @routes       = JSON.parse(site.metafields.dig('elasticsearch', 'routes') || '[]')
      else
        @indices    = []
        @client     = nil
        @routes     = []
      end
    end

    def is_configured?
     !!@site.metafields['elasticsearch']
    end

    def find_all_products_and_categories
      indices.map do |config|
        {}.tap do |records|
          site.locales.each do |locale|
            index   = build_index_name(config['index'], locale.to_s)
            body =  { query: { match_all: {} } }
            body[:size]=100
            result = @client.search(
              index: index,
              scroll: '5m',
              body: body
            )

            # first search which also returns _scroll_id
            result['hits']['hits'].each do |hit|
              record = records[hit['_id']] ||= {}
              record[locale] = { name: hit['_source']['name'], url: find_route(config['name']).gsub('*', hit['_source']['url_key']) }
            end

            # Uses the `scroll` API until empty results are returned
            # https://www.elastic.co/guide/en/elasticsearch/reference/6.6/search-request-scroll.html
            while result = @client.scroll(body: { scroll_id: result['_scroll_id'] }, scroll: '5m') and not result['hits']['hits'].empty? do
              result['hits']['hits'].each do |hit|
                record = records[hit['_id']] ||= {}
                record[locale] = { name: hit['_source']['name'], url: find_route(config['name']).gsub('*', hit['_source']['url_key']) }
              end
            end
          end
        end.values
      end.flatten
    end

    def find_all(name, conditions: nil, page: 0, per_page: 20)

      body = {
        from: page * per_page,
        size: per_page,
        track_total_hits: true
      }

      if conditions
        body[:query] = build_params(conditions)
      else
        body[:query] = { match_all: {} }
      end

      response = @client.search(
        index: find_index_name(name),
        body: body
      )

      response = _parse_response(response)
      {
        data: response['hits']['hits'].map { |hit| hit['_source']['index_name'] = name; hit['_source'] },
        size: response['hits']['total']['value']
      }
    end

    def find_by_key(name, key)
      _find_by_key(name, key)
    end

    private

    def _parse_response(response)
      if @customer
        role = @customer.role
      end
      role ||= @site.metafields['erp']['default_role']
      response['hits']['hits'].each do |hit|
        if hit["_source"].include?('price')
          hit["_source"]['price'] = hit["_source"]['price'][role]
        end
      end
      response
    end

    def _find_by_key(name, key)
      body = {
        query:{
          bool:{
              should: [
                { term: { url_key: key } },
                { term: { redirect_url_key: key } }
              ]
          }
        }
      }
      response = @client.search(
        index: find_index_name(name),
        body: body
      )
      response = _parse_response(response)
      resource = nil
      # look for the main product/category AND its variants
      response['hits']['hits'].each do |hit|
        hit['_source']['index_name'] = name
        if resource.nil?
          resource = hit['_source']
        else
          (resource['variants'] ||= []) << hit['_source']
        end
      end
      resource
    end

    def build_params(conditions)
      { bool: { filter: [], must_not: [] }}.tap do |params|
        conditions.each do |key, value|
          name, op = key.split('.')
          build_attr(name, value).each do | name, value |
            if %w(ne nin).include?(op)
              [*value].each do |_value|
                params[:bool][:must_not] << { term: { name => _value } }
              end
            elsif %w(gt gte lt lte).include?(op)
              params[:bool][:filter] << { range: { name => { op => value } } }
            else
              params[:bool][:filter] << { term: { name => value } }
            end
          end
        end
      end
    end

    def find_route(index_name)
      @routes ||= JSON.parse(site.metafields.dig('elasticsearch', 'routes')  || '[]')
      (@routes.find { |(route, rule)| rule['index'] == index_name }).try(:first)
    end

  end
end
