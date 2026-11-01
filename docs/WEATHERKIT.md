# Apple WeatherKit

The macOS app uses `WeatherService.shared.weather(for:including: .current)` to load current temperature, apparent temperature, condition, and SF Symbol. Apple geocoding resolves the manually entered city. No device-location permission, REST token, or embedded API key is used. Both development and commercial builds use this provider.

The weather popover includes Apple Weather branding and the data-source link returned by `WeatherService.attribution`. Compact and rich weather tiles also identify Apple Weather. Temperature remains Fahrenheit, matching the existing widget. Editing the city clears the old result, and a response for an earlier query cannot overwrite the new city.

## Signing and account configuration

The Xcode project enables WeatherKit through `app/DockGrove.entitlements`, uses automatic Apple Development signing, and selects the local owner's team `G563Q4D3XW`. The development bundle identifier is `com.dylan.wavedock.development`. For another team, change `DEVELOPMENT_TEAM` in `app/project.yml`, then regenerate with `cd app && xcodegen generate`.

Apple requires WeatherKit to be enabled in **both Capabilities and App Services** for the App ID. Each production or QA identifier needs its own matching configuration and provisioning profile. The account holder must also accept any pending Apple Developer Program agreement before Xcode can update profiles. See [Apple's WeatherKit setup](https://developer.apple.com/help/account/services/weatherkit/) and [attribution requirements](https://developer.apple.com/weatherkit/).

Open `app/DockGrove.xcodeproj` and build the DockGrove scheme. The command-line equivalent from the repository root is:

```sh
xcodebuild -project app/DockGrove.xcodeproj -scheme DockGrove \
  -configuration Debug -derivedDataPath app/.build/xcode \
  -allowProvisioningUpdates build
```

The **Development** configuration is the universal, ad-hoc-signed build used by offline CI. It compiles WeatherKit support but cannot authenticate to Apple Weather. Use the provisioned Xcode build for live weather; do not attach restricted WeatherKit entitlements to an ad-hoc signature.

## Verification

Offline weather tests are included in the **DockGrove Tests** XCTest suite. They cover formatting, attribution, city changes during a request, duplicate/empty requests, missing cities, authorization and network failures, and recovery on retry. These tests do not contact Apple.

To verify the real Apple geocoding → WeatherKit → attribution flow without launching the Dock interface:

```sh
TEST_RUNNER_DOCKGROVE_LIVE_TESTS=1 TEST_RUNNER_DOCKGROVE_WEATHER_CITY="Boston, Massachusetts" \
  xcodebuild test -project app/DockGrove.xcodeproj -scheme "DockGrove Tests" -configuration Debug \
  -only-testing:DockGroveTests/LiveTests/testAppleWeather -allowProvisioningUpdates
```

This live check requires the signed, provisioned build. A successful compile or fixture run alone does not verify Apple service access.

On October 30, 2026, the local build, complete offline app regression suite (including the weather cases), and website checks passed. After the Apple account agreement block cleared, the development App ID `com.dylan.wavedock.development` was registered on team `G563Q4D3XW` with both the WeatherKit capability and service enabled. Xcode created a matching profile and successfully built the Apple Development-signed app. Its native `--weather-test "Boston, Massachusetts"` call returned current conditions and Apple's attribution link, confirming live geocoding and WeatherKit access.

MusicKit, Wi-Fi Aware, and Access Wi-Fi Information were also enabled on the development App ID at the owner's request. These are account-level capability settings, not new music playback or Wi-Fi features in the app. The app's current Xcode entitlement remains WeatherKit; ordinary network requests already work in the native macOS app. The legacy Mac Catalyst checkbox was left disabled because Apple's configuration applies to existing Catalyst apps already on the Mac App Store, not this native AppKit app. See [Apple's Catalyst configuration guidance](https://developer.apple.com/help/account/capabilities/create-a-mac-version-of-an-ipad-app/).
