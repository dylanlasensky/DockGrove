import CoreLocation
import WeatherKit

struct WeatherSnapshot {
    let city: String
    let temperature: Measurement<UnitTemperature>
    let apparentTemperature: Measurement<UnitTemperature>
    let condition: String
    let symbolName: String
    let date: Date
    let attributionURL: URL
    let lightMarkURL: URL
    let darkMarkURL: URL

    static func fahrenheit(_ value: Measurement<UnitTemperature>) -> String {
        "\(Int(value.converted(to: .fahrenheit).value.rounded()))°F"
    }
}

enum WeatherLookupError: Error { case cityNotFound }

/// The WeatherKit values DockGrove shows, separated from WeatherKit types so tests can supply them.
struct WeatherReading {
    let temperature: Measurement<UnitTemperature>
    let apparentTemperature: Measurement<UnitTemperature>
    let condition: String
    let symbolName: String
    let date: Date
    let attributionURL: URL
    let lightMarkURL: URL
    let darkMarkURL: URL
}

enum AppleWeatherClient {
    typealias Geocode = (String) async throws -> [CLPlacemark]
    typealias Current = (CLLocation) async throws -> WeatherReading
    /// Apple's geocoder and WeatherKit. Tests replace these with local fixtures.
    static var geocode: Geocode = { try await CLGeocoder().geocodeAddressString($0) }
    static var current: Current = AppleWeatherClient.liveCurrent
    @MainActor static func fetch(city: String) async throws -> WeatherSnapshot { try await fetch(city: city, geocode: geocode, current: current) }
    @MainActor static func fetch(city: String, geocode: Geocode, current: Current) async throws -> WeatherSnapshot {
        // Geocode only the entered city; never request the device's location.
        let places = try await geocode(city)
        guard let place = places.first, let location = place.location else {
            throw WeatherLookupError.cityNotFound
        }
        let weather = try await current(location)
        let name = [place.locality ?? place.name, place.administrativeArea, place.country]
            .compactMap { $0 }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            .joined(separator: ", ")
        return WeatherSnapshot(city: name.isEmpty ? city : name,
            temperature: weather.temperature, apparentTemperature: weather.apparentTemperature,
            condition: weather.condition, symbolName: weather.symbolName, date: weather.date,
            attributionURL: weather.attributionURL, lightMarkURL: weather.lightMarkURL,
            darkMarkURL: weather.darkMarkURL)
    }
    /// WeatherKit current conditions and the attribution it requires.
    static func liveCurrent(_ location: CLLocation) async throws -> WeatherReading {
        let service = WeatherService.shared
        async let current = service.weather(for: location, including: .current)
        async let attribution = service.attribution
        let (weather, credit) = try await (current, attribution)
        return WeatherReading(temperature: weather.temperature, apparentTemperature: weather.apparentTemperature,
            condition: weather.condition.description, symbolName: weather.symbolName, date: weather.date,
            attributionURL: credit.legalPageURL, lightMarkURL: credit.combinedMarkLightURL, darkMarkURL: credit.combinedMarkDarkURL)
    }
}
