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

enum AppleWeatherClient {
    @MainActor static func fetch(city: String) async throws -> WeatherSnapshot {
        // Geocode only the entered city; never request the device's location.
        let places = try await CLGeocoder().geocodeAddressString(city)
        guard let place = places.first, let location = place.location else {
            throw WeatherLookupError.cityNotFound
        }
        let service = WeatherService.shared
        async let current = service.weather(for: location, including: .current)
        async let attribution = service.attribution
        let (weather, credit) = try await (current, attribution)
        let name = [place.locality ?? place.name, place.administrativeArea, place.country]
            .compactMap { $0 }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            .joined(separator: ", ")
        return WeatherSnapshot(city: name.isEmpty ? city : name,
            temperature: weather.temperature, apparentTemperature: weather.apparentTemperature,
            condition: weather.condition.description, symbolName: weather.symbolName, date: weather.date,
            attributionURL: credit.legalPageURL, lightMarkURL: credit.combinedMarkLightURL,
            darkMarkURL: credit.combinedMarkDarkURL)
    }
}
