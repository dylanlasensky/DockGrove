import Foundation
import WeatherKit

@MainActor func runWeatherTests() async throws {
    let suite = "DockGroveWeatherTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let kit = Toolkit(store: defaults)
    let fixture = WeatherSnapshot(city: "Boston, Massachusetts, United States",
        temperature: Measurement(value: 0, unit: .celsius),
        apparentTemperature: Measurement(value: -5, unit: .celsius),
        condition: "Snow", symbolName: "snow", date: Date(timeIntervalSince1970: 1_700_000_000),
        attributionURL: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!,
        lightMarkURL: URL(string: "https://example.invalid/light.svg")!,
        darkMarkURL: URL(string: "https://example.invalid/dark.svg")!)
    var requests = 0
    await kit.loadWeather { _ in requests += 1; return fixture }
    precondition(requests == 0 && !kit.weatherLoading)
    kit.weatherCity = "  Boston  "
    await kit.loadWeather { city in
        precondition(city == "Boston" && kit.weatherLoading)
        requests += 1
        await kit.loadWeather { _ in preconditionFailure("Duplicate weather request") }
        return fixture
    }
    precondition(requests == 1 && !kit.weatherLoading && kit.weatherText == "32°F")
    precondition(kit.weatherDetail.contains("Feels like 23°F") && kit.weatherDetail.contains("Snow"))
    precondition(kit.weatherSnapshot?.attributionURL == fixture.attributionURL)
    kit.weatherCity = "Tokyo"
    precondition(kit.weatherSnapshot == nil && kit.weatherDetail.isEmpty)
    await kit.loadWeather { _ in
        kit.weatherCity = "Paris"
        kit.weatherCity = "Tokyo"
        return fixture
    }
    precondition(kit.weatherSnapshot == nil && kit.weatherText == "Choose a city" && !kit.weatherLoading)
    await kit.loadWeather { _ in throw WeatherLookupError.cityNotFound }
    precondition(kit.weatherText == "Unavailable" && kit.weatherDetail.contains("City not found"))
    await kit.loadWeather { _ in throw WeatherError.permissionDenied }
    precondition(kit.weatherDetail.contains("this build") && !kit.weatherLoading)
    await kit.loadWeather { _ in throw URLError(.notConnectedToInternet) }
    precondition(kit.weatherDetail.contains("connection") && kit.weatherSnapshot == nil)
    await kit.loadWeather { _ in fixture }
    precondition(kit.weatherText == "32°F" && !kit.weatherLoading)
    print("PASS: WeatherKit presentation, Fahrenheit conversion, attribution, empty/duplicate requests, stale city responses, missing city, authorization/network failures, and retry")
}
