#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "braintrust"
require "ruby_llm"
require "opentelemetry/sdk"

# Example: RubyLLM tool calling with Braintrust tracing
#
# This demonstrates how tool calls create nested spans with a sophisticated
# travel planning scenario featuring:
# - Multiple tools with complex nested parameters
# - Tools that return deeply nested response structures
# - Tools that create their own internal spans (simulating API calls)
# - Multi-turn conversation with multiple tool invocations
#
# Trace hierarchy will look like:
#   examples/contrib/ruby_llm/tool_usage.rb
#   └── ruby_llm.chat
#       ├── ruby_llm.tool.search_flights
#       │   └── flight_api.search (internal span)
#       ├── ruby_llm.tool.search_hotels
#       │   └── hotel_api.search (internal span)
#       └── ruby_llm.tool.get_destination_info
#           ├── weather_api.forecast (internal span)
#           └── events_api.search (internal span)
#
# Usage:
#   OPENAI_API_KEY=your-key bundle exec appraisal ruby_llm ruby examples/contrib/ruby_llm/tool_usage.rb

unless ENV["OPENAI_API_KEY"]
  puts "Error: OPENAI_API_KEY environment variable is required"
  exit 1
end

# Flight search tool with complex nested parameters
class SearchFlightsTool < RubyLLM::Tool
  description "Search for flights between cities with flexible date options and passenger details"

  param :origin, type: :string, desc: "Origin airport code (e.g., SFO, JFK)"
  param :destination, type: :string, desc: "Destination airport code"
  param :departure_date, type: :string, desc: "Departure date (YYYY-MM-DD)"
  param :return_date, type: :string, desc: "Return date for round trip (YYYY-MM-DD), optional"
  param :passengers, type: :integer, desc: "Number of passengers (default: 1)"
  param :cabin_class, type: :string, desc: "Cabin class: economy, premium_economy, business, first"
  param :flexible_dates, type: :boolean, desc: "Search +/- 3 days from specified dates"

  def execute(origin:, destination:, departure_date:, return_date: nil, passengers: 1, cabin_class: "economy", flexible_dates: false)
    tracer = OpenTelemetry.tracer_provider.tracer("flight-service")

    # Simulate an internal API call with its own span
    tracer.in_span("flight_api.search", attributes: {
      "flight.origin" => origin,
      "flight.destination" => destination,
      "flight.passengers" => passengers
    }) do
      sleep(0.05) # Simulate API latency

      # Return deeply nested flight results
      {
        search_id: "FL-#{rand(100000..999999)}",
        query: {
          route: {origin: origin, destination: destination},
          dates: {
            departure: departure_date,
            return: return_date,
            flexible: flexible_dates
          },
          travelers: {count: passengers, cabin: cabin_class}
        },
        results: [
          {
            flight_id: "UA#{rand(100..999)}",
            airline: {code: "UA", name: "United Airlines"},
            segments: [
              {
                departure: {airport: origin, terminal: "2", time: "#{departure_date}T08:30:00", gate: "A12"},
                arrival: {airport: destination, terminal: "B", time: "#{departure_date}T11:45:00"},
                aircraft: {type: "Boeing 737-900", wifi: true, power_outlets: true},
                duration_minutes: 195
              }
            ],
            pricing: {
              base_fare: 299.00 * passengers,
              taxes: 45.50 * passengers,
              fees: {carrier_fee: 25.00, booking_fee: 0},
              total: (299.00 + 45.50 + 25.00) * passengers,
              currency: "USD",
              fare_class: cabin_class,
              refundable: false,
              change_fee: 75.00
            },
            availability: {seats_remaining: rand(2..9)}
          },
          {
            flight_id: "DL#{rand(100..999)}",
            airline: {code: "DL", name: "Delta Air Lines"},
            segments: [
              {
                departure: {airport: origin, terminal: "1", time: "#{departure_date}T14:15:00", gate: "C8"},
                arrival: {airport: destination, terminal: "A", time: "#{departure_date}T17:30:00"},
                aircraft: {type: "Airbus A320", wifi: true, power_outlets: true},
                duration_minutes: 195
              }
            ],
            pricing: {
              base_fare: 279.00 * passengers,
              taxes: 42.00 * passengers,
              fees: {carrier_fee: 30.00, booking_fee: 0},
              total: (279.00 + 42.00 + 30.00) * passengers,
              currency: "USD",
              fare_class: cabin_class,
              refundable: false,
              change_fee: 0
            },
            availability: {seats_remaining: rand(2..9)}
          }
        ],
        metadata: {
          search_time_ms: rand(150..300),
          providers_queried: %w[amadeus sabre travelport],
          cache_hit: false
        }
      }
    end
  end
end

# Hotel search tool with nested room and amenity preferences
class SearchHotelsTool < RubyLLM::Tool
  description "Search for hotels with detailed room preferences and amenity filters"

  param :city, type: :string, desc: "City name for hotel search"
  param :check_in, type: :string, desc: "Check-in date (YYYY-MM-DD)"
  param :check_out, type: :string, desc: "Check-out date (YYYY-MM-DD)"
  param :guests, type: :integer, desc: "Number of guests"
  param :rooms, type: :integer, desc: "Number of rooms needed"
  param :star_rating_min, type: :integer, desc: "Minimum star rating (1-5)"
  param :amenities, type: :string, desc: "Comma-separated amenities: pool,gym,spa,parking,wifi,breakfast"

  def execute(city:, check_in:, check_out:, guests: 2, rooms: 1, star_rating_min: 3, amenities: "wifi")
    tracer = OpenTelemetry.tracer_provider.tracer("hotel-service")
    requested_amenities = amenities.split(",").map(&:strip)

    tracer.in_span("hotel_api.search", attributes: {
      "hotel.city" => city,
      "hotel.guests" => guests,
      "hotel.rooms" => rooms
    }) do
      sleep(0.05)

      {
        search_id: "HT-#{rand(100000..999999)}",
        query: {
          location: {city: city, radius_km: 10, center: "downtown"},
          stay: {check_in: check_in, check_out: check_out, nights: 3},
          occupancy: {guests: guests, rooms: rooms},
          filters: {min_stars: star_rating_min, amenities: requested_amenities}
        },
        results: [
          {
            hotel_id: "HTL-#{rand(10000..99999)}",
            name: "Grand #{city} Hotel & Spa",
            brand: {name: "Luxury Collection", loyalty_program: "Marriott Bonvoy"},
            location: {
              address: {street: "123 Main Street", city: city, postal_code: "94102", country: "USA"},
              coordinates: {latitude: 37.7749, longitude: -122.4194},
              neighborhood: "Downtown",
              transit: {nearest_metro: "Powell St", distance_km: 0.3}
            },
            rating: {
              stars: 5,
              guest_score: 4.7,
              reviews: {count: 2341, recent_sentiment: "excellent"}
            },
            rooms: [
              {
                room_id: "RM-#{rand(1000..9999)}",
                type: "Deluxe King",
                description: "Spacious room with city views",
                bedding: {beds: [{type: "king", count: 1}], max_occupancy: 2},
                size: {sqft: 450, sqm: 42},
                features: %w[city_view work_desk minibar safe],
                pricing: {
                  per_night: 289.00,
                  total: 867.00,
                  taxes: 130.05,
                  fees: {resort_fee: 45.00, cleaning_fee: 0},
                  grand_total: 1042.05,
                  currency: "USD",
                  cancellation: {free_until: check_in, policy: "free_cancellation"}
                }
              }
            ],
            amenities: {
              wellness: {pool: {indoor: true, outdoor: false, hours: "6am-10pm"}, gym: true, spa: {available: true, appointment_required: true}},
              dining: {restaurants: 2, room_service: {available: true, hours: "24/7"}, breakfast: {included: false, price: 35.00}},
              business: {wifi: {free: true, speed: "high-speed"}, business_center: true, meeting_rooms: 5},
              parking: {available: true, valet: true, self_park: 45.00, valet_price: 65.00}
            },
            policies: {
              check_in_time: "15:00",
              check_out_time: "11:00",
              pets: {allowed: true, fee: 75.00, restrictions: "dogs under 25lbs"},
              smoking: false
            }
          }
        ],
        metadata: {search_time_ms: rand(200..400), availability_as_of: Time.now.utc.iso8601}
      }
    end
  end
end

# Destination info tool that aggregates multiple data sources
class GetDestinationInfoTool < RubyLLM::Tool
  description "Get comprehensive destination information including weather forecast and local events"

  param :city, type: :string, desc: "City name"
  param :travel_dates, type: :string, desc: "Travel date range (YYYY-MM-DD to YYYY-MM-DD)"
  param :interests, type: :string, desc: "Comma-separated interests: food,art,music,sports,nature,nightlife"

  def execute(city:, travel_dates:, interests: "food,art")
    tracer = OpenTelemetry.tracer_provider.tracer("destination-service")
    interest_list = interests.split(",").map(&:strip)
    dates = travel_dates.split(" to ")
    start_date = dates[0]
    end_date = dates[1] || start_date

    # This tool makes multiple internal API calls, each with their own spans
    weather_data = tracer.in_span("weather_api.forecast", attributes: {"weather.city" => city}) do
      sleep(0.03)
      {
        location: {city: city, timezone: "America/Los_Angeles"},
        forecast: [
          {date: start_date, high_f: 68, low_f: 54, conditions: "Partly Cloudy", precipitation_chance: 10, humidity: 65, wind: {speed_mph: 12, direction: "W"}},
          {date: end_date, high_f: 72, low_f: 56, conditions: "Sunny", precipitation_chance: 0, humidity: 55, wind: {speed_mph: 8, direction: "NW"}}
        ],
        alerts: [],
        best_times: {outdoor_activities: "10am-4pm", photography: "golden_hour"}
      }
    end

    events_data = tracer.in_span("events_api.search", attributes: {"events.city" => city, "events.interests" => interests}) do
      sleep(0.03)
      {
        events: [
          {
            event_id: "EVT-#{rand(10000..99999)}",
            name: "#{city} Food & Wine Festival",
            category: "food",
            venue: {name: "Civic Center Plaza", address: "123 Civic Center", capacity: 5000},
            schedule: {date: start_date, time: "11:00", duration_hours: 8},
            pricing: {general_admission: 45.00, vip: 125.00, currency: "USD"},
            highlights: ["50+ local restaurants", "Wine tastings", "Cooking demos"]
          },
          {
            event_id: "EVT-#{rand(10000..99999)}",
            name: "Modern Art Exhibition",
            category: "art",
            venue: {name: "#{city} Museum of Modern Art", address: "456 Art Street"},
            schedule: {date: start_date, time: "10:00", duration_hours: 6},
            pricing: {general_admission: 25.00, student: 15.00, currency: "USD"},
            highlights: ["New installations", "Interactive exhibits", "Guided tours available"]
          }
        ],
        total_matching: 12,
        filtered_by: interest_list
      }
    end

    {
      destination: {
        city: city,
        overview: {
          description: "A vibrant city known for its culture, cuisine, and scenic beauty",
          population: "800,000+",
          language: "English",
          currency: {code: "USD", symbol: "$"},
          time_zone: "Pacific Time (PT)"
        },
        travel_advisory: {level: "normal", last_updated: Time.now.utc.iso8601}
      },
      weather: weather_data,
      events: events_data,
      recommendations: {
        neighborhoods: [
          {name: "Downtown", vibe: "bustling", best_for: %w[dining shopping nightlife]},
          {name: "Waterfront", vibe: "scenic", best_for: %w[walking photography seafood]}
        ],
        tips: [
          "Book popular restaurants at least 2 weeks in advance",
          "Public transit is efficient - consider a visitor pass",
          "Many museums offer free admission on first Thursdays"
        ]
      },
      metadata: {generated_at: Time.now.utc.iso8601, data_sources: %w[weather_api events_api local_guides]}
    }
  end
end

# Initialize Braintrust and instrument RubyLLM
Braintrust.init(blocking_login: true)
Braintrust.instrument!(:ruby_llm)

RubyLLM.configure do |config|
  config.openai_api_key = ENV["OPENAI_API_KEY"]
end

tracer = OpenTelemetry.tracer_provider.tracer("ruby_llm-example")
root_span = nil

puts "=" * 70
puts "Travel Planning Assistant with Multi-Tool Orchestration"
puts "=" * 70
puts
puts "This example demonstrates deeply nested tracing with multiple tools."
puts "Watch the trace to see how tool calls create hierarchical spans."
puts

response = tracer.in_span("examples/contrib/ruby_llm/tool_usage.rb") do |span|
  root_span = span

  chat = RubyLLM.chat(model: "gpt-4o-mini")
  chat.with_tools(SearchFlightsTool, SearchHotelsTool, GetDestinationInfoTool)

  puts "User: I'm planning a trip from San Francisco (SFO) to New York (JFK)"
  puts "      for December 15-18, 2025. Can you help me find flights, a nice"
  puts "      hotel downtown, and tell me what's happening in the city? I'm"
  puts "      interested in food and art."
  puts
  puts "Assistant is thinking and calling tools..."
  puts "(This may take a moment as multiple tools are invoked)"
  puts

  chat.ask(<<~PROMPT)
    I'm planning a trip from San Francisco (SFO) to New York (JFK) for December 15-18, 2025.
    I need:
    1. Flight options (economy class, 1 passenger)
    2. A nice hotel downtown (4+ stars, need wifi and gym)
    3. What's the weather forecast and any food/art events happening?

    Please search for all of this and give me a summary of the best options.
  PROMPT
end

puts "-" * 70
puts "Assistant Response:"
puts "-" * 70
puts response.content
puts
puts "=" * 70
puts "Trace Information"
puts "=" * 70
puts
puts "View the full trace: #{Braintrust::Trace.permalink(root_span)}"
puts
puts "Expected span hierarchy:"
puts "  └── examples/contrib/ruby_llm/tool_usage.rb"
puts "      └── ruby_llm.chat"
puts "          ├── ruby_llm.tool.search_flights"
puts "          │   └── flight_api.search"
puts "          ├── ruby_llm.tool.search_hotels"
puts "          │   └── hotel_api.search"
puts "          └── ruby_llm.tool.get_destination_info"
puts "              ├── weather_api.forecast"
puts "              └── events_api.search"
puts

OpenTelemetry.tracer_provider.shutdown
