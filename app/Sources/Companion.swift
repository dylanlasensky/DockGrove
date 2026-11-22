import SwiftUI
import AppKit

struct CompanionState: Codable, Equatable {
    var name = "Cream cat"
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
    static func displayName(_ animal: String) -> String {
        switch animal {
        case "Miso": return "Cream cat"
        case "Black cat": return "Tuxedo cat"
        case "Golden dog": return "Golden retriever"
        default: return animal
        }
    }
    var displayName: String { state.name == "Miso" ? "Cream cat" : state.name }
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
    var playroom = false
    var sceneRequest: CompanionSceneRequest?
    var onSelectDestination: ((Double) -> Void)?
    func makeNSView(context: Context) -> CompanionStage { CompanionStage() }
    static func dismantleNSView(_ view: CompanionStage, coordinator: ()) {
        view.isPaused = true
        view.presentScene(nil)
    }
    func updateNSView(_ view: CompanionStage, context: Context) {
        view.animal = animal; view.resting = resting
        view.companionScene.playroom = playroom
        view.onSelectDestination = onSelectDestination
        view.receivePlay(playRequest)
        view.setAccessibilityLabel(Companion.displayName(animal) + (resting ? " sleeping" : " autonomous companion"))
        view.refreshScene()
        view.companionScene.receive(sceneRequest)
    }
}
/// Observe the companion directly so its selection and care state update even while
/// a floating panel is hosting a popover in a different run-loop mode.
struct LiveCompanionPortrait: View {
    @ObservedObject var pet: Companion
    var accent: Color
    var body: some View {
        CatPortrait(resting: pet.state.resting, animal: pet.animal, accent: accent, playRequest: pet.playRequest)
    }
}

struct CompanionView: View {
    @ObservedObject var pet: Companion
    var accent: Color
    @State private var name = ""
    var body: some View {
        VStack(spacing: 14) {
            CatPortrait(resting: pet.state.resting, animal: pet.animal, accent: accent, playRequest: pet.playRequest).frame(width:250, height:180)
            Picker("Companion", selection:$pet.animal) { ForEach(Companion.animals,id: \.self) { Text(Companion.displayName($0)).tag($0) } }
            Text(pet.displayName).font(.title2.bold())
            Text(pet.state.mood).foregroundStyle(.secondary)
            HStack { Button("Feed") { pet.state.feed() }; Button("Play") { pet.play() }.disabled(pet.state.resting); Button(pet.state.resting ? "Wake up" : "Rest") { pet.state.resting.toggle() } }
            VStack(alignment: .leading) { meter("Fullness", pet.state.fullness); meter("Energy", pet.state.energy); meter("Joy", pet.state.joy) }
            Text("Level \(pet.state.level) · \(pet.state.sessions) completed focus sessions").font(.caption)
            HStack { TextField("Companion name", text: $name).textFieldStyle(.roundedBorder).onSubmit { pet.rename(name) }; Button("Rename") { pet.rename(name) }.disabled(name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty) }
            Text("Finish a DockGrove focus session to earn a little joy. Your companion is safe while you’re away. No app or keyboard activity is tracked.").font(.caption).foregroundStyle(.secondary)
        }.onAppear { name = pet.displayName }
    }
    private func meter(_ name: String, _ value: Double) -> some View { HStack { Text(name).frame(width:65,alignment:.leading); ProgressView(value:value,total:100).tint(accent); Text("\(Int(value))").monospacedDigit().frame(width:28) }.font(.caption) }
}

/// Editing takes place in a regular key window, never in the Dock's nonactivating panel.
/// The same window is reused so another click cannot discard an unfinished name edit.
extension DockModel {
    func showCompanionPlayroom() {
        guard canAccess(.pet) else { settingsAction?(); return }
        if let companionWindow {
            DockSystemEffect.handler(.present(companionWindow))
            return
        }
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 980, height: 660),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Companion Playroom"
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.contentMinSize = CGSize(width: 760, height: 520)
        let host = NSHostingView(rootView: CompanionPlayroomView(pet: toolkit.pet, accent: color,
            fullscreen: { [weak window] in window?.toggleFullScreen(nil) }).preferredColorScheme(scheme))
        host.sizingOptions = [.minSize]
        window.contentView = host
        companionWindow = window
        window.center()
        DockSystemEffect.handler(.present(window))
    }
}

struct CompanionPlayroomView: View {
    @ObservedObject var pet: Companion
    var accent: Color
    var fullscreen: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingDetails = false
    @State private var feedback = "A little room to make their own."
    @State private var request: CompanionSceneRequest?
    @State private var marker = ""
    @State private var nextDestination = 0.76

    var body: some View {
        VStack(spacing: 20) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(pet.displayName).font(.system(size: 25, weight: .semibold, design: .rounded))
                    Text(pet.state.mood).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button { showingDetails.toggle() } label: { Label("Details", systemImage: "slider.horizontal.3") }
                    .accessibilityIdentifier("companion-details")
                Button(action: fullscreen) { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                    .help("Enter or leave full screen").accessibilityLabel("Toggle playroom full screen")
            }
            HStack(alignment: .top, spacing: 20) {
                room
                if showingDetails {
                    CompanionDetailsView(pet: pet, accent: accent)
                        .frame(width: 240).frame(maxHeight: .infinity, alignment: .top)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(spacing: 12) {
                Text(feedback).font(.callout).foregroundStyle(.secondary)
                    .accessibilityIdentifier("companion-feedback").accessibilityAddTraits(.updatesFrequently)
                HStack(spacing: 12) {
                    Button(action: feed) { Label("Feed", systemImage: "carrot.fill") }
                        .disabled(pet.state.resting)
                    Button(action: play) { Label("Play", systemImage: "tennisball.fill") }
                        .disabled(pet.state.resting)
                    Button(action: rest) { Label(pet.state.resting ? "Wake up" : "Rest", systemImage: pet.state.resting ? "sun.max" : "moon.zzz") }
                }.buttonStyle(.bordered).controlSize(.large)
                Text(pet.state.resting ? "Let them dream, or wake them when you’re ready." : reduceMotion ? "Feed, play and rest. Motion follows your Mac’s accessibility settings." : "Click in the room to explore. Feed a snack or toss a toy.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(24).frame(minWidth: 712, minHeight: 472)
            .background(Color(nsColor: .windowBackgroundColor))
            .onChange(of: pet.animal) { _, _ in request = nil; marker = ""; feedback = "Make yourself at home, \(pet.displayName)." }
    }

    private var room: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 24).fill(accent.opacity(0.055))
                LinearGradient(colors: [.clear, accent.opacity(0.055)], startPoint: .top, endPoint: .bottom)
                    .overlay(alignment: .bottom) {
                        // Decoration must not enlarge the room's layout proposal.
                        Ellipse().fill(accent.opacity(0.07))
                            .frame(width: geometry.size.width * 1.2, height: geometry.size.height * 0.48)
                            .offset(y: geometry.size.height * 0.22)
                    }
                if let request, !marker.isEmpty, !pet.state.resting,
                   let metrics = CompanionSpriteScene.geometry(for: pet.animal, size: geometry.size, playroom: true) {
                    Image(systemName: marker).font(.system(size: 24)).foregroundStyle(accent)
                        .position(x: metrics.x(at: request.destination), y: geometry.size.height - metrics.floor - 12)
                        .accessibilityHidden(true)
                }
                CatPortrait(resting: pet.state.resting, animal: pet.animal, accent: accent,
                            playRequest: pet.playRequest, playroom: true, sceneRequest: request,
                            onSelectDestination: explore)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }.frame(width: geometry.size.width, height: geometry.size.height)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(accent.opacity(0.10)))
                .accessibilityElement(children: .contain)
                .accessibilityAction(named: Text("Explore the room")) { explore(nextSpot()) }
        }.frame(minWidth: 380, minHeight: 270)
    }
    private func nextSpot() -> Double {
        nextDestination = nextDestination < 0.5 ? 0.76 : 0.24
        return nextDestination
    }
    private func explore(_ destination: Double) {
        guard !pet.state.resting else { feedback = "\(pet.displayName) is resting. Wake them to explore."; return }
        marker = ""
        request = CompanionSceneRequest(destination: destination)
        feedback = reduceMotion ? "\(pet.displayName) is happy here." : "\(pet.displayName) is exploring."
    }
    private func feed() {
        pet.state.feed()
        marker = "carrot.fill"
        request = CompanionSceneRequest(destination: nextSpot(), arrival: .groom)
        feedback = "A little snack for \(pet.displayName)."
    }
    private func play() {
        pet.play()
        marker = "tennisball.fill"
        request = CompanionSceneRequest(destination: nextSpot(), arrival: .play)
        feedback = reduceMotion ? "\(pet.displayName) enjoyed playing with you." : "\(pet.displayName) is coming to play."
    }
    private func rest() {
        pet.state.resting.toggle()
        marker = ""; request = nil
        feedback = pet.state.resting ? "Sweet dreams, \(pet.displayName)." : "Good morning, \(pet.displayName)."
    }
}

struct CompanionDetailsView: View {
    @ObservedObject var pet: Companion
    var accent: Color
    @State private var name = ""
    @FocusState private var editingName: Bool
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Make them yours").font(.headline)
                VStack(alignment: .leading, spacing: 7) {
                    Text("Name").font(.caption).foregroundStyle(.secondary)
                    TextField("Companion name", text: $name).textFieldStyle(.roundedBorder)
                        .focused($editingName).onSubmit(rename)
                        .accessibilityIdentifier("companion-name")
                    Button("Rename", action: rename)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("companion-rename")
                }
                Picker("Companion", selection: $pet.animal) {
                    ForEach(Companion.animals, id: \.self) { Text(Companion.displayName($0)).tag($0) }
                }.labelsHidden().accessibilityLabel("Companion species")
                Divider()
                meter("Fullness", pet.state.fullness)
                meter("Energy", pet.state.energy)
                meter("Joy", pet.state.joy)
                Text("Level \(pet.state.level) · \(pet.state.sessions) focus sessions").font(.caption).foregroundStyle(.secondary)
                Text("Your companion is safe while you’re away. No keyboard or app activity is tracked.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(1)
        }.onAppear { name = pet.displayName }
            .onChange(of: pet.state.name) { _, _ in if !editingName { name = pet.displayName } }
    }
    private func rename() { pet.rename(name); name = pet.displayName; editingName = false }
    private func meter(_ title: String, _ value: Double) -> some View {
        VStack(spacing: 6) {
            HStack { Text(title); Spacer(); Text("\(Int(value))").monospacedDigit().foregroundStyle(.secondary) }.font(.caption)
            ProgressView(value: value, total: 100).tint(accent)
        }
    }
}
