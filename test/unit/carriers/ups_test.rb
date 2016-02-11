require 'test_helper'

class UPSTest < Test::Unit::TestCase

  def setup
    @packages  = TestFixtures.packages
    @locations = TestFixtures.locations
    @carrier   = UPS.new(
                   :key => 'key',
                   :login => 'login',
                   :password => 'password'
                 )
    @tracking_response = xml_fixture('ups/shipment_from_tiger_direct')
  end

  def test_initialize_options_requirements
    assert_raises(ArgumentError) { UPS.new }
    assert_raises(ArgumentError) { UPS.new(:login => 'blah', :password => 'bloo') }
    assert_raises(ArgumentError) { UPS.new(:login => 'blah', :key => 'kee') }
    assert_raises(ArgumentError) { UPS.new(:password => 'bloo', :key => 'kee') }
    assert_nothing_raised { UPS.new(:login => 'blah', :password => 'bloo', :key => 'kee') }
  end

  def test_find_tracking_info_should_return_a_tracking_response
    @carrier.expects(:commit).returns(@tracking_response)
    assert_equal 'ActiveMerchant::Shipping::TrackingResponse', @carrier.find_tracking_info('1Z5FX0076803466397').class.name
  end

  def test_find_tracking_info_should_parse_response_into_correct_number_of_shipment_events
    @carrier.expects(:commit).returns(@tracking_response)
    response = @carrier.find_tracking_info('1Z5FX0076803466397')
    assert_equal 8, response.shipment_events.size
  end

  def test_find_tracking_info_should_return_shipment_events_in_ascending_chronological_order
    @carrier.expects(:commit).returns(@tracking_response)
    response = @carrier.find_tracking_info('1Z5FX0076803466397')
    assert_equal response.shipment_events.map(&:time).sort, response.shipment_events.map(&:time)
  end

  def test_find_tracking_info_should_have_correct_names_for_shipment_events
    @carrier.expects(:commit).returns(@tracking_response)
    response = @carrier.find_tracking_info('1Z5FX0076803466397')
    assert_equal [ "BILLING INFORMATION RECEIVED",
                   "IMPORT SCAN",
                   "LOCATION SCAN",
                   "LOCATION SCAN",
                   "DEPARTURE SCAN",
                   "ARRIVAL SCAN",
                   "OUT FOR DELIVERY",
                   "DELIVERED" ], response.shipment_events.map(&:name)
  end

  def test_add_origin_and_destination_data_to_shipment_events_where_appropriate
    @carrier.expects(:commit).returns(@tracking_response)
    response = @carrier.find_tracking_info('1Z5FX0076803466397')
    assert_equal '175 AMBASSADOR', response.shipment_events.first.location.address1
    assert_equal 'K1N5X8', response.shipment_events.last.location.postal_code
  end

  def test_response_parsing_for_activity_without_location
    tracking_response = xml_fixture('ups/first_activity_without_location')
    @carrier.expects(:commit).returns(tracking_response)
    response = @carrier.find_tracking_info('1Z2789781390037999')
    assert_equal nil, response.shipment_events.first.location
    location = response.shipment_events.last.location
    assert_equal '68105', location.postal_code
    assert_equal 'OMAHA', location.city
  end

  def test_response_parsing
    mock_response = xml_fixture('ups/test_real_home_as_residential_destination_response')
    @carrier.expects(:commit).returns(mock_response)
    response = @carrier.find_rates( @locations[:beverly_hills],
                                    @locations[:real_home_as_residential],
                                    @packages.values_at(:chocolate_stuff))
    assert_equal [ "UPS Ground",
                   "UPS 3 Day Select",
                   "UPS 2nd Day Air",
                   "UPS Next Day Air Saver",
                   "UPS Next Day Air Early A.M.",
                   "UPS Next Day Air"], response.rates.map(&:service_name)
    assert_equal [992, 2191, 3007, 5509, 9401, 6124], response.rates.map(&:price)
    assert_equal [0, 0, 0, 0, 0, 0], response.rates.map(&:negotiated_rate)

    date_test = [nil, 3, 2, 1, 1, 1].map do |days|
      DateTime.strptime(days.days.from_now.strftime("%Y-%m-%d"), "%Y-%m-%d") if days
    end

    assert_equal date_test, response.rates.map(&:delivery_date)
  end

  def test_response_with_origin_account_parsing
    @carrier   = UPS.new(
                   :key => 'key',
                   :login => 'login',
                   :origin_account => 'account_number',
                   :password => 'password'
                 )
    mock_response = xml_fixture('ups/test_real_home_as_residential_destination_with_origin_account_response')
    @carrier.expects(:commit).returns(mock_response)
    response = @carrier.find_rates( @locations[:beverly_hills],
                                    @locations[:real_home_as_residential],
                                    @packages[:chocolate_stuff])
    assert_equal [ "UPS Worldwide Express",
                   "UPS Worldwide Expedited",
                   "UPS Worldwide Express Plus",
                   "UPS Worldwide Saver"], response.rates.map(&:service_name)
    assert_equal [18893, 17856, 23473, 18286], response.rates.map(&:price)
    assert_equal [18704, 17677, 23238, 18103], response.rates.map(&:negotiated_rate)
  end

  def test_maximum_weight
    assert Package.new(150 * 16, [5,5,5], :units => :imperial).mass == @carrier.maximum_weight
    assert Package.new((150 * 16) + 0.01, [5,5,5], :units => :imperial).mass > @carrier.maximum_weight
    assert Package.new((150 * 16) - 0.01, [5,5,5], :units => :imperial).mass < @carrier.maximum_weight
  end
end
