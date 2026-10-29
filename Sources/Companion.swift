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
    @Published var animal: String { didSet { defaults.set(animal, forKey: "companionAnimal") } }
    static let animals = ["Miso", "Black cat", "Orange cat", "Golden dog", "Husky", "Dragon", "Cow", "Rabbit", "Fox"]
    @Published var state: CompanionState { didSet { save() } }
    private let defaults: UserDefaults
    init(defaults: UserDefaults) {
        self.defaults = defaults
        let choice = defaults.string(forKey: "companionAnimal") ?? "Miso"
        animal = Self.animals.contains(choice) ? choice : "Miso"
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
    var isCat: Bool { ["Miso","Black cat","Orange cat"].contains(animal) }
    var fur: Color {
        switch animal {
        case "Black cat": return Color(white:0.22)
        case "Orange cat","Fox": return Color(red:0.9,green:0.48,blue:0.18)
        case "Golden dog": return Color(red:0.85,green:0.65,blue:0.32)
        case "Husky": return Color(red:0.42,green:0.49,blue:0.58)
        case "Dragon": return Color(red:0.32,green:0.7,blue:0.5)
        case "Cow","Rabbit": return Color(red:0.9,green:0.87,blue:0.82)
        default: return Color(red:0.83,green:0.77,blue:0.69)
        }
    }
    var resting: Bool
    var animal: String = "Miso"
    var accent: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 60 : 0.15, paused: reduceMotion)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
            let blink = !reduceMotion && !resting && phase.truncatingRemainder(dividingBy:5) < 0.18
            let wag = reduceMotion || resting ? 0 : sin(phase*3)*0.03
            let breath = reduceMotion ? 1 : 1 + sin(context.date.timeIntervalSinceReferenceDate * 1.7) * 0.015
            Canvas { c, s in
                func ellipse(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ color: Color) { c.fill(Path(ellipseIn: CGRect(x: x*s.width, y: y*s.height, width:w*s.width,height:h*s.height)), with:.color(color)) }
                ellipse(0.05,0.65,0.9,0.28,accent.opacity(0.3)); ellipse(0.12,0.67,0.76,0.17,accent.opacity(0.22))
                if animal == "Dragon" {
                    var wing=Path(); wing.move(to:CGPoint(x:s.width*0.6,y:s.height*0.53)); wing.addLine(to:CGPoint(x:s.width*0.93,y:s.height*0.16)); wing.addLine(to:CGPoint(x:s.width*0.88,y:s.height*0.57)); wing.closeSubpath(); c.fill(wing,with:.color(fur.opacity(0.7)))
                }
                ellipse(0.22,0.36,0.61,0.39,fur)
                var ears = Path(); ears.move(to:CGPoint(x:s.width*0.25,y:s.height*0.48)); ears.addLine(to:CGPoint(x:s.width*0.26,y:s.height*0.14)); ears.addLine(to:CGPoint(x:s.width*0.45,y:s.height*0.35)); ears.move(to:CGPoint(x:s.width*0.48,y:s.height*0.34)); ears.addLine(to:CGPoint(x:s.width*0.67,y:s.height*0.14)); ears.addLine(to:CGPoint(x:s.width*0.68,y:s.height*0.5)); c.fill(ears,with:.color(fur))
                if animal == "Rabbit" { for x in [0.29,0.52] { ellipse(x,0.01,0.12,0.4,fur); ellipse(x+0.03,0.04,0.06,0.3,Color.pink.opacity(0.4)) } }
                if animal == "Golden dog" { for x in [0.18,0.62] { ellipse(x,0.3,0.17,0.39,Color.brown) } }
                if animal == "Cow" || animal == "Dragon" { for x in [0.27,0.6] { ellipse(x,0.18,0.075,0.17,Color(red:0.92,green:0.77,blue:0.45)) } }
                ellipse(0.24,0.29,0.46,0.4,fur)
                if animal == "Cow" { ellipse(0.28,0.31,0.17,0.18,Color(white:0.25)); ellipse(0.66,0.44,0.13,0.17,Color(white:0.25)) }
                if ["Husky","Fox","Golden dog","Cow"].contains(animal) { ellipse(0.34,0.48,0.29,0.18,animal == "Cow" ? Color.pink.opacity(0.65) : Color(white:0.94)) }
                for x in [0.36,0.56] { ellipse(x,0.46,0.045,resting || blink ? 0.014 : 0.055,animal == "Black cat" ? Color.yellow : Color(white:0.15)) }
                ellipse(0.46,0.54,0.04,0.025,Color(red:0.57,green:0.37,blue:0.36))
                var tail = Path(); tail.move(to:CGPoint(x:s.width*0.79,y:s.height*0.58)); tail.addCurve(to:CGPoint(x:s.width*0.58,y:s.height*0.73),control1:CGPoint(x:s.width*0.98,y:s.height*(0.69+wag)),control2:CGPoint(x:s.width*0.77,y:s.height*0.85)); c.stroke(tail,with:.color(fur.opacity(0.85)),style:StrokeStyle(lineWidth:s.width*0.075,lineCap:.round))
            }
            .scaleEffect(x: 1, y: breath, anchor: .bottom)
        }.accessibilityLabel(animal + (resting ? " asleep in a bed" : " awake in a bed"))
    }
}
struct CompanionView: View {
    @ObservedObject var pet: Companion
    var accent: Color
    @State private var name = ""
    var body: some View {
        VStack(spacing: 14) {
            CatPortrait(resting: pet.state.resting, animal: pet.animal, accent: accent).frame(width:175, height:125)
            Picker("Companion", selection:$pet.animal) { ForEach(Companion.animals,id: \.self) { Text($0) } }
            Text(pet.state.name).font(.title2.bold())
            Text(pet.state.mood).foregroundStyle(.secondary)
            HStack { Button("Feed") { pet.state.feed() }; Button("Play") { pet.state.play() }.disabled(pet.state.resting); Button(pet.state.resting ? "Wake up" : "Rest") { pet.state.resting.toggle() } }
            VStack(alignment: .leading) { meter("Fullness", pet.state.fullness); meter("Energy", pet.state.energy); meter("Joy", pet.state.joy) }
            Text("Level \(pet.state.level) · \(pet.state.sessions) completed focus sessions").font(.caption)
            HStack { TextField("Companion name", text: $name).textFieldStyle(.roundedBorder); Button("Rename") { pet.rename(name) }.disabled(name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty) }
            Text("Finish a WaveDock focus session to earn a little joy. Your cat is safe while you’re away. No app or keyboard activity is tracked.").font(.caption).foregroundStyle(.secondary)
        }.onAppear { name = pet.state.name }
    }
    private func meter(_ name: String, _ value: Double) -> some View { HStack { Text(name).frame(width:65,alignment:.leading); ProgressView(value:value,total:100).tint(accent); Text("\(Int(value))").monospacedDigit().frame(width:28) }.font(.caption) }
}
