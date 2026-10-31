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
    @Published private(set) var playRequest = 0
    func play() { guard !state.resting else { return }; state.play(); playRequest &+= 1 }
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

/// Six individually illustrated poses per animal, decoded once and shared by all docks.
@MainActor enum CompanionArtwork {
    static let names = ["Miso":"miso", "Black cat":"black-cat", "Orange cat":"orange-cat", "Golden dog":"golden-dog", "Husky":"husky", "Dragon":"dragon", "Cow":"cow", "Rabbit":"rabbit", "Fox":"fox"]
    private static var cache: [String:[NSImage]] = [:]
    static func frames(_ animal: String) -> [NSImage] {
        let key = names[animal] ?? "miso"
        if let cached = cache[key] { return cached }
        guard let source = NSImage(named: "Companion-" + key), let sheet = source.cgImage(forProposedRect:nil,context:nil,hints:nil),
              sheet.width % 3 == 0, sheet.height % 2 == 0 else { return [] }
        let w = sheet.width/3, h = sheet.height/2
        let result = (0..<6).compactMap { index -> NSImage? in
            guard let frame = sheet.cropping(to:CGRect(x:(index%3)*w,y:(index/3)*h,width:w,height:h)) else { return nil }
            return NSImage(cgImage:frame,size:NSSize(width:w,height:h))
        }
        cache[key] = result
        return result
    }
}

/// The AppKit view owns its simulation so SwiftUI redraws do not reset behavior.
struct CatPortrait: NSViewRepresentable {
    var resting: Bool
    var animal: String = "Miso"
    var accent: Color
    var playRequest = 0
    func makeNSView(context: Context) -> CompanionStage { CompanionStage() }
    static func dismantleNSView(_ view: CompanionStage, coordinator: ()) {
        view.isPaused = true
        view.presentScene(nil)
    }
    func updateNSView(_ view: CompanionStage, context: Context) {
        view.animal = animal; view.resting = resting
        view.receivePlay(playRequest)
        view.setAccessibilityLabel(animal + (resting ? " sleeping" : " autonomous companion"))
        view.refreshScene()
    }
}
struct CompanionView: View {
    @ObservedObject var pet: Companion
    var accent: Color
    @State private var name = ""
    var body: some View {
        VStack(spacing: 14) {
            CatPortrait(resting: pet.state.resting, animal: pet.animal, accent: accent, playRequest: pet.playRequest).frame(width:250, height:180)
            Picker("Companion", selection:$pet.animal) { ForEach(Companion.animals,id: \.self) { Text($0) } }
            Text(pet.state.name).font(.title2.bold())
            Text(pet.state.mood).foregroundStyle(.secondary)
            HStack { Button("Feed") { pet.state.feed() }; Button("Play") { pet.play() }.disabled(pet.state.resting); Button(pet.state.resting ? "Wake up" : "Rest") { pet.state.resting.toggle() } }
            VStack(alignment: .leading) { meter("Fullness", pet.state.fullness); meter("Energy", pet.state.energy); meter("Joy", pet.state.joy) }
            Text("Level \(pet.state.level) · \(pet.state.sessions) completed focus sessions").font(.caption)
            HStack { TextField("Companion name", text: $name).textFieldStyle(.roundedBorder); Button("Rename") { pet.rename(name) }.disabled(name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty) }
            Text("Finish a DockGrove focus session to earn a little joy. Your companion is safe while you’re away. No app or keyboard activity is tracked.").font(.caption).foregroundStyle(.secondary)
        }.onAppear { name = pet.state.name }
    }
    private func meter(_ name: String, _ value: Double) -> some View { HStack { Text(name).frame(width:65,alignment:.leading); ProgressView(value:value,total:100).tint(accent); Text("\(Int(value))").monospacedDigit().frame(width:28) }.font(.caption) }
}
