require 'spec_helper'

module ActiveShipping
  describe Spree::Calculator::Shipping::Usps do
    WebMock.disable_net_connect!

    let(:address) { FactoryGirl.create(:address) }
    let(:stock_location) { FactoryGirl.create(:stock_location) }
    let!(:order) do
      order = FactoryGirl.create(:order_with_line_items, ship_address: address, line_items_count: 2)
      order.line_items.first.tap do |line_item|
        line_item.quantity = 2
        line_item.variant.save
        line_item.variant.weight = 1
        line_item.variant.save
        line_item.save
        # product packages?
      end
      order.line_items.last.tap do |line_item|
        line_item.quantity = 2
        line_item.variant.save
        line_item.variant.weight = 2
        line_item.variant.save
        line_item.save
        # product packages?
      end
      order
    end

    let(:carrier) { ActiveShipping::USPS.new(login: 'FAKEFAKEFAKE') }
    let(:calculator) { Spree::Calculator::Shipping::Usps::ExpressMail.new }
    let(:response) { double('response', rates: rates, params: {}) }
    let(:package) { order.shipments.first.to_package }

    before(:each) do
      Spree::StockLocation.destroy_all
      stock_location
      order.create_proposed_shipments
      expect(order.shipments.count).to eq 1
      Spree::ActiveShipping::Config.set(units: 'imperial')
      Spree::ActiveShipping::Config.set(unit_multiplier: 1)
      allow(calculator).to receive(:carrier) { carrier }
      Rails.cache.clear
    end

    describe 'package.order' do
      it { expect(package.order).to eq(order) }
      it { expect(package.order.ship_address).to eq(address) }
      it { expect(package.order.ship_address.country.iso).to eq('US') }
      it { expect(package.stock_location).to eq(stock_location) }
    end

    describe 'compute' do
      subject { calculator.compute(package) }

      it 'should use the carrier supplied in the initializer' do
        stub_request(:get, %r{http:\/\/production.shippingapis.com\/ShippingAPI.dll.*})
          .to_return(body: fixture(:normal_rates_request))
        expect(subject).to eq 14.1
      end

      context 'with valid response' do
        let(:rates) do
          [double('rate', service_code: '3', price: 999)]
        end

        before do
          allow(carrier).to receive(:find_rates) { response }
        end

        it "should return rate based on calculator's service_code" do
          allow(calculator.class).to receive(:service_code) { 'dom:3' }
          expect(subject).to eq 9.99
        end

        it 'should include handling_fee when configured' do
          allow(calculator.class).to receive(:service_code) { 'dom:3' }
          Spree::ActiveShipping::Config.set(handling_fee: 100)
          expect(subject).to eq 10.99
        end

        it 'should return nil if service_code is not found in rate_hash' do
          allow(calculator.class).to receive(:service_code) { 'invalid service_code' }
          expect(subject).to be_nil
        end
      end
    end

    describe 'service_name' do
      it 'should return description when not defined' do
        expect(calculator.class.service_name).to eq calculator.description
      end
    end
  end
end
