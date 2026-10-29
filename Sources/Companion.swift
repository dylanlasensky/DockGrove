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

/// Six individually illustrated poses per animal, decoded once and shared by all docks.
@MainActor enum CompanionArtwork {
    static let names = ["Miso":"miso", "Black cat":"black-cat", "Orange cat":"orange-cat", "Golden dog":"golden-dog", "Husky":"husky", "Dragon":"dragon", "Cow":"cow", "Rabbit":"rabbit", "Fox":"fox"]
    private static var cache: [String:[NSImage]] = [:]
    static func frames(_ animal: String) -> [NSImage] {
        let key = names[animal] ?? "miso"
        if let cached = cache[key] { return cached }
        guard let url = Bundle.main.url(forResource:key,withExtension:"png",subdirectory:"Companions"),
              let source = NSImage(contentsOf:url), let sheet = source.cgImage(forProposedRect:nil,context:nil,hints:nil),
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

struct CompanionPose: Equatable {
    var frame: Int
    var x: Double = 0
    var y: Double = 0
    var breath: Double = 1
    static func at(_ time: TimeInterval, animal: String, resting: Bool, reduceMotion: Bool) -> Self {
        if reduceMotion { return Self(frame:resting ? 5 : 1) }
        if resting { return Self(frame:5,breath:1+sin(time*1.6)*0.012) }
        let t = abs(time.truncatingRemainder(dividingBy:18))
        let sequence: [Int]; let speed: Double
        switch animal {
        case "Dragon": sequence=[0,1,2,3,2,4]; speed=0.18
        case "Rabbit": sequence=[0,0,1,2,2,3,3,4,4]; speed=0.3
        case "Cow": sequence=[0,1,1,2,1,1,3,3,4,1]; speed=0.6
        case "Golden dog": sequence=[0,1,2,1,0,2,3,3,4,4]; speed=0.32
        case "Husky": sequence=[0,1,2,1,0,2,3,3,3,4]; speed=0.4
        case "Fox": sequence=[0,1,2,1,0,2,3,3,4,2]; speed=0.3
        case "Black cat": sequence=[0,1,2,1,0,2,3,3,3,4,4]; speed=0.45
        case "Orange cat": sequence=[0,1,2,1,0,2,3,3,4,4]; speed=0.5
        default: sequence=[0,1,2,1,0,2,3,3,4,4,1]; speed=0.4
        }
        let frame = sequence[Int(t/speed)%sequence.count]
        let x = sin(t*0.6)*0.035
        let y = animal == "Dragon" ? sin(t*2)*0.055 : animal == "Rabbit" && frame == 1 ? -0.06 : 0
        return Self(frame:frame,x:x,y:y)
    }
}

struct CatPortrait: View {
    var resting: Bool
    var animal: String = "Miso"
    var accent: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval:0.08,paused:reduceMotion)) { context in
            let pose = CompanionPose.at(context.date.timeIntervalSinceReferenceDate,animal:animal,resting:resting,reduceMotion:reduceMotion)
            let frames = CompanionArtwork.frames(animal)
            GeometryReader { geometry in
                if frames.indices.contains(pose.frame) {
                    Image(nsImage:frames[pose.frame]).resizable().interpolation(.high).scaledToFit()
                        .padding(geometry.size.height*0.065)
                        .scaleEffect(x:1,y:pose.breath,anchor:.bottom)
                        .offset(x:geometry.size.width*pose.x,y:geometry.size.height*pose.y)
                }
            }
        }.accessibilityLabel(animal + (resting ? " sleeping" : " animated companion"))
    }
}
struct CompanionView: View {
    @ObservedObject var pet: Companion
    var accent: Color
    @State private var name = ""
    var body: some View {
        VStack(spacing: 14) {
            CatPortrait(resting: pet.state.resting, animal: pet.animal, accent: accent).frame(width:250, height:180)
            Picker("Companion", selection:$pet.animal) { ForEach(Companion.animals,id: \.self) { Text($0) } }
            Text(pet.state.name).font(.title2.bold())
            Text(pet.state.mood).foregroundStyle(.secondary)
            HStack { Button("Feed") { pet.state.feed() }; Button("Play") { pet.state.play() }.disabled(pet.state.resting); Button(pet.state.resting ? "Wake up" : "Rest") { pet.state.resting.toggle() } }
            VStack(alignment: .leading) { meter("Fullness", pet.state.fullness); meter("Energy", pet.state.energy); meter("Joy", pet.state.joy) }
            Text("Level \(pet.state.level) · \(pet.state.sessions) completed focus sessions").font(.caption)
            HStack { TextField("Companion name", text: $name).textFieldStyle(.roundedBorder); Button("Rename") { pet.rename(name) }.disabled(name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty) }
            Text("Finish a WaveDock focus session to earn a little joy. Your companion is safe while you’re away. No app or keyboard activity is tracked.").font(.caption).foregroundStyle(.secondary)
        }.onAppear { name = pet.state.name }
    }
    private func meter(_ name: String, _ value: Double) -> some View { HStack { Text(name).frame(width:65,alignment:.leading); ProgressView(value:value,total:100).tint(accent); Text("\(Int(value))").monospacedDigit().frame(width:28) }.font(.caption) }
}
