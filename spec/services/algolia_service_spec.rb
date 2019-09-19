require 'spec_helper'

RSpec.describe ShopInvader::AlgoliaService do

  let(:indices)     { '[{ "name": "products", "index": "locomotive_shopinvader_product" }, { "name": "categories", "index": "locomotive_shopinvader_category" }]' }
  let(:routes)      { '[]' }
  let(:metafields)  { {
    'algolia' => {
      'application_id'  => ENV['ALGOLIA_APP_ID'],
      'api_key'         => ENV['ALGOLIA_API_KEY'],
      'indices'         => indices,
      'routes'          => routes
    },
    'erp' => { 'default_role' => 'public_tax_inc' }
  } }
  let(:site)      { instance_double('Site', metafields: metafields, locales: ['en']) }
  let(:customer)  { nil }
  let(:locale)    { 'fr' }
  let(:service)   { described_class.new(site, customer, locale) }

  describe '#build_index_name for local fr' do

    subject { service.send(:build_index_name, 'shopinvader_variant', 'fr') }

    it 'returns the index with the lang fr_FR' do
      expect(subject).to eq('shopinvader_variant_fr_FR')
    end

    context "with specific lang mapping for Belgium" do

      let(:metafields) { {'_store' => {'locale_mapping' => '{"fr": "fr_BE"}'}} }

      it 'return the index with the lang fr_be' do
        expect(subject).to eq('shopinvader_variant_fr_BE')
      end

    end
  end

  describe 'Building params from condition' do
    subject { service.send(:build_params, conditions) }

    context "with numeric filter" do
      let(:conditions) { { 'categories_ids' => 5 } }

      it 'returns 1 numeric filter"' do
        expect(subject).to eq({:facetFilters=>[], :numericFilters=>["categories_ids = 5"]})
      end
    end

    context "with nested numeric filter" do
      let(:conditions) { { 'categories' => {'id': 5} } }

      it 'returns 1 numeric filter"' do
        expect(subject).to eq({:facetFilters=>[], :numericFilters=>["categories.id = 5"]})
      end
    end

    context "with nested facet filter" do
      let(:conditions) { { 'attributes' => {'color': 'red'} } }

      it 'returns 1 facet filter"' do
        expect(subject).to eq({:facetFilters=>["attributes.color:red"], :numericFilters=>[]})
      end
    end

    context "with nested not equal" do
      let(:conditions) { { 'attributes.ne' => {'color': 'red'} } }

      it 'returns 1 must not filter"' do
        expect(subject).to eq({:facetFilters=>["NOT attributes.color:red"], :numericFilters=>[]})
      end
    end

    context "with nested not in" do
      let(:conditions) { { 'attributes.nin' => {'color': ['red', 'yellow'] } } }

      it 'returns 2 must not filter"' do
        expect(subject).to eq({:facetFilters=>["attributes.color:red", "attributes.color:yellow"], :numericFilters=>[]})
      end
    end

    context "with nested comparator" do
      let(:conditions) { { 'price.gt' => {'value': 10} } }

      it 'returns 1 numeric filter with comparator"' do
        expect(subject).to eq({:facetFilters=>[], :numericFilters=>["price.value > 10"]})
      end
    end

    context "with nested range" do
      let(:conditions) { { 'price.gt' => {'value': 10}, 'price.lt' => {'value': 30} } }

      it 'returns 1 numeric filter with comparator"' do
        expect(subject).to eq({:facetFilters=>[], :numericFilters=>["price.value > 10", "price.value < 30"]})
      end
    end

    context "with all" do
      let(:conditions) { { 'categories' => {'id': 5} , 'attributes' => {'color': 'red'},  'price.gt' => { 'value': 10 } } }

      it 'returns all filter and faceting"' do
        expect(subject).to eq({:facetFilters=>["attributes.color:red"], :numericFilters=>["categories.id = 5", "price.value > 10"]})
      end
    end

  end

end
