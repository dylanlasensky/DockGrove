import SwiftUI

struct WeatherAttributionView: View {
    let snapshot: WeatherSnapshot
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack {
            AsyncImage(url: colorScheme == .dark ? snapshot.lightMarkURL : snapshot.darkMarkURL) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Label("Weather", systemImage: "apple.logo").font(.caption)
            }
            .frame(width: 90, height: 20)
            .accessibilityLabel("Apple Weather")
            Spacer()
            Link("Other data sources", destination: snapshot.attributionURL).font(.caption)
        }
    }
}
