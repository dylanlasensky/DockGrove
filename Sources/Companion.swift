import SwiftUI
import AppKit

struct CompanionState: Codable, Equatable {
    var name = "Miso"
    var fullness = 75.0
    var energy = 80.0
    var joy = 70.0
    var resting = false
    var sessions = 0
    var lastUpdate = Date()
    mutating func advance(to now: Date) {
        // No punishment for time away: needs change only during brief active updates.
        let minutes = min(2, max(0, now.timeIntervalSince(lastUpdate) / 60))
        fullness = max(25, fullness - minutes * 0.2)
        energy = min(100, max(25, energy + minutes * (resting ? 3 : -0.15)))
        joy = min(100, max(35, joy))
        lastUpdate = now
    }
    mutating func feed() { fullness = min(100, fullness + 20); joy = min(100, joy + 5) }
    mutating func play() { guard !resting else { return }; joy = min(100, joy + 12); energy = max(25, energy - 5) }
    mutating func reward() { sessions += 1; joy = min(100, joy + 15); energy = min(100, energy + 5) }
    var level: Int { 1 + sessions / 3 }
    var mood: String { resting ? "Dreaming softly" : fullness < 45 ? "A little snack?" : energy < 45 ? "Ready for a nap" : "Happy to be here" }
}
@MainActor final class Companion: ObservableObject {
    @Published var state: CompanionState { didSet { save() } }
    private let defaults: UserDefaults
    init(defaults: UserDefaults) {
        self.defaults = defaults
        var restored = defaults.data(forKey: "companion").flatMap { try? JSONDecoder().decode(CompanionState.self, from: $0) } ?? CompanionState()
        restored.fullness = restored.fullness.isFinite ? min(100, max(25, restored.fullness)) : 75
        restored.energy = restored.energy.isFinite ? min(100, max(25, restored.energy)) : 80
        restored.joy = restored.joy.isFinite ? min(100, max(35, restored.joy)) : 70
        restored.sessions = min(1_000_000, max(0, restored.sessions)); restored.name = String(restored.name.prefix(24)); restored.lastUpdate = Date()
        state = restored
    }
    private func save() { if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: "companion") } }
    func tick() { state.advance(to: Date()) }
    func rename(_ name: String) { let name = name.trimmingCharacters(in: .whitespacesAndNewlines); if !name.isEmpty { state.name = String(name.prefix(24)) } }
}

/// Original vector illustration, drawn at any Dock scale without downloaded artwork.
struct CatPortrait: View {
    var resting: Bool
    var accent: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 60 : 0.15, paused: reduceMotion)) { context in
            let breath = reduceMotion ? 1 : 1 + sin(context.date.timeIntervalSinceReferenceDate * 1.7) * 0.015
            Canvas { c, s in
                func ellipse(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ color: Color) { c.fill(Path(ellipseIn: CGRect(x: x*s.width, y: y*s.height, width:w*s.width,height:h*s.height)), with:.color(color)) }
                ellipse(0.05,0.65,0.9,0.28,accent.opacity(0.3)); ellipse(0.12,0.67,0.76,0.17,accent.opacity(0.22))
                ellipse(0.22,0.36,0.61,0.39,Color(red:0.72,green:0.65,blue:0.57))
                var ears = Path(); ears.move(to:CGPoint(x:s.width*0.25,y:s.height*0.48)); ears.addLine(to:CGPoint(x:s.width*0.26,y:s.height*0.14)); ears.addLine(to:CGPoint(x:s.width*0.45,y:s.height*0.35)); ears.move(to:CGPoint(x:s.width*0.48,y:s.height*0.34)); ears.addLine(to:CGPoint(x:s.width*0.67,y:s.height*0.14)); ears.addLine(to:CGPoint(x:s.width*0.68,y:s.height*0.5)); c.fill(ears,with:.color(Color(red:0.79,green:0.72,blue:0.64)))
                ellipse(0.24,0.29,0.46,0.4,Color(red:0.83,green:0.77,blue:0.69))
                for x in [0.36,0.56] { ellipse(x,0.46,0.045,resting ? 0.014 : 0.055,Color(white:0.2)) }
                ellipse(0.46,0.54,0.04,0.025,Color(red:0.57,green:0.37,blue:0.36))
                var tail = Path(); tail.move(to:CGPoint(x:s.width*0.79,y:s.height*0.58)); tail.addCurve(to:CGPoint(x:s.width*0.58,y:s.height*0.73),control1:CGPoint(x:s.width*0.98,y:s.height*0.69),control2:CGPoint(x:s.width*0.77,y:s.height*0.85)); c.stroke(tail,with:.color(Color(red:0.62,green:0.55,blue:0.47)),style:StrokeStyle(lineWidth:s.width*0.075,lineCap:.round))
            }.scaleEffect(x: 1, y: breath, anchor: .bottom)
        }.accessibilityLabel(resting ? "Cat asleep in a bed" : "Cat resting in a bed")
    }
}
struct CompanionView: View {
    @ObservedObject var pet: Companion
    var accent: Color
    @State private var name = ""
    var body: some View {
        VStack(spacing: 14) {
            CatPortrait(resting: pet.state.resting, accent: accent).frame(height: 125)
            Text(pet.state.name).font(.title2.bold())
            Text(pet.state.mood).foregroundStyle(.secondary)
            HStack { Button("Feed") { pet.state.feed() }; Button("Play") { pet.state.play() }.disabled(pet.state.resting); Button(pet.state.resting ? "Wake up" : "Rest") { pet.state.resting.toggle() } }
            VStack(alignment: .leading) { meter("Fullness", pet.state.fullness); meter("Energy", pet.state.energy); meter("Joy", pet.state.joy) }
            Text("Level \(pet.state.level) · \(pet.state.sessions) completed focus sessions").font(.caption)
            HStack { TextField("Cat name", text: $name).textFieldStyle(.roundedBorder); Button("Rename") { pet.rename(name) }.disabled(name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty) }
            Text("Finish a WaveDock focus session to earn a little joy. Your cat is safe while you’re away. No app or keyboard activity is tracked.").font(.caption).foregroundStyle(.secondary)
        }.onAppear { name = pet.state.name }
    }
    private func meter(_ name: String, _ value: Double) -> some View { HStack { Text(name).frame(width:65,alignment:.leading); ProgressView(value:value,total:100).tint(accent); Text("\(Int(value))").monospacedDigit().frame(width:28) }.font(.caption) }
}
