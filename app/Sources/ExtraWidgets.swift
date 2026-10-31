import AppKit
import SwiftUI
import AVFoundation

/// Bounded arithmetic parser; never evaluates code or an NSExpression.
enum Calculator {
    enum Failure: Error { case invalid, divisionByZero }
    static func evaluate(_ text: String) throws -> Double {
        guard !text.isEmpty, text.count <= 256 else { throw Failure.invalid }
        var parser = Parser(chars: Array(text.filter { !$0.isWhitespace })); let value = try parser.expression()
        guard parser.index == parser.chars.count, value.isFinite else { throw Failure.invalid }; return value
    }
    private struct Parser {
        var chars: [Character]; var index = 0
        mutating func take(_ char: Character) -> Bool { if index < chars.count && chars[index] == char { index += 1; return true }; return false }
        mutating func expression() throws -> Double {
            var value = try term()
            while index < chars.count {
                if take("+") { value += try term() } else if take("-") { value -= try term() } else { break }
            }; return value
        }
        mutating func term() throws -> Double {
            var value = try unary()
            while index < chars.count {
                if take("*") || take("×") { value *= try unary() }
                else if take("/") || take("÷") { let rhs = try unary(); guard rhs != 0 else { throw Failure.divisionByZero }; value /= rhs }
                else { break }
            }; return value
        }
        mutating func unary() throws -> Double {
            if take("+") { return try unary() }; if take("-") { return try -unary() }
            var value = try atom()
            if take("^") { value = pow(value, try unary()) }
            if take("%") { value /= 100 }
            return value
        }
        mutating func atom() throws -> Double {
            if take("(") { let value = try expression(); guard take(")") else { throw Failure.invalid }; return value }
            let start = index
            while index < chars.count && (chars[index].isNumber || chars[index] == ".") { index += 1 }
            guard index > start, let value = Double(String(chars[start..<index])) else { throw Failure.invalid }; return value
        }
    }
}
struct CalculatorView: View {
    @State private var input = ""
    @State private var answer = "0"
    var body: some View {
        VStack(alignment: .trailing, spacing: 12) {
            TextField("Expression", text: $input).font(.title3.monospaced()).onSubmit(calculate)
            Text(answer).font(.system(size: 32, weight: .medium)).lineLimit(2).textSelection(.enabled).accessibilityLabel("Result " + answer)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                ForEach(["C", "(", ")", "÷", "7", "8", "9", "×", "4", "5", "6", "-", "1", "2", "3", "+", "0", ".", "%", "="], id: \.self) { key in
                    Button { if key == "C" { input = ""; answer = "0" } else if key == "=" { calculate() } else { input += key } } label: { Text(key).font(.title3).frame(maxWidth: .infinity, minHeight: 34) }.buttonStyle(.bordered)
                }
            }
            Text("Supports parentheses, powers (^) and percentages.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func calculate() {
        do { answer = try Calculator.evaluate(input).formatted(.number.precision(.significantDigits(1...12))) }
        catch Calculator.Failure.divisionByZero { answer = "Cannot divide by zero" }
        catch { answer = "Check the expression" }
    }
}
struct ExchangeRate: Decodable { let date: String; let base: String; let quote: String; let rate: Double }
@MainActor final class CurrencyWidget: ObservableObject {
    static let currencies = ["USD", "EUR", "GBP", "CAD", "AUD", "JPY", "CHF", "CNY", "INR", "MXN", "BRL", "COP", "KRW", "NZD", "SEK"]
    @Published var base = "USD" { didSet { report = nil } }
    @Published var quote = "EUR" { didSet { report = nil } }
    @Published var amount = "100"
    @Published var report: ExchangeRate?
    @Published var loading = false
    @Published var status = "Refresh to load a daily reference rate."
    private let configuration: URLSessionConfiguration
    init(configuration: URLSessionConfiguration = .ephemeral) { self.configuration = configuration }
    var converted: Double? {
        guard let amount = Double(amount), amount.isFinite, let report else { return nil }
        let result = amount * report.rate; return result.isFinite ? result : nil
    }
    static func decode(_ data: Data, base: String, quote: String) throws -> ExchangeRate {
        let value = try JSONDecoder().decode(ExchangeRate.self, from: data)
        guard value.base == base, value.quote == quote, value.rate.isFinite, value.rate > 0, value.date.count == 10 else { throw UsageError.service }; return value
    }
    func refresh() {
        guard !loading, Self.currencies.contains(base), Self.currencies.contains(quote) else { return }
        let from = base, to = quote
        if from == to { report = ExchangeRate(date: Date().formatted(.iso8601.year().month().day().dateSeparator(.dash)), base: from, quote: to, rate: 1); status = "Same currency"; return }
        loading = true; report = nil
        Task {
            defer { loading = false }
            do {
                var request = URLRequest(url: URL(string: "https://api.frankfurter.dev/v2/rate/\(from.lowercased())/\(to.lowercased())")!); request.timeoutInterval = 15
                let session = URLSession(configuration: configuration); defer { session.invalidateAndCancel() }
                let (data, response) = try await session.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 100_000 else { throw UsageError.service }
                let result = try Self.decode(data, base: from, quote: to)
                guard base == from, quote == to else { return }; report = result; status = "Reference rate · " + result.date
            } catch { status = "Could not load the rate. Check your connection and retry." }
        }
    }
}
struct CurrencyView: View {
    @ObservedObject var widget: CurrencyWidget
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Amount", text: $widget.amount).font(.title2)
            HStack {
                Picker("From", selection: $widget.base) { ForEach(CurrencyWidget.currencies, id: \.self) { Text($0) } }
                Button { let old = widget.base; widget.base = widget.quote; widget.quote = old } label: { Image(systemName: "arrow.left.arrow.right") }.help("Swap currencies")
                Picker("To", selection: $widget.quote) { ForEach(CurrencyWidget.currencies, id: \.self) { Text($0) } }
            }
            if let result = widget.converted { Text(result.formatted(.number.precision(.fractionLength(2))) + " " + widget.quote).font(.title).textSelection(.enabled) }
            Text(widget.status).font(.caption).foregroundStyle(.secondary)
            Button(widget.loading ? "Refreshing…" : "Refresh rate", action: widget.refresh).disabled(widget.loading)
            Link("Daily rates by Frankfurter", destination: URL(string: "https://frankfurter.dev")!).font(.caption)
            Text("Only the currency pair is sent. Your amount stays on this Mac. Rates are indicative, not a bank quote.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// The microphone, audio objects and save panel behind a voice memo; replaceable in tests.
protocol VoiceMemoDevice {
    @MainActor func requestMicrophone() async -> Bool
    func recorder(url: URL, settings: [String: Any]) throws -> AVAudioRecorder
    func player(url: URL) throws -> AVAudioPlayer
    @MainActor func exportDestination() -> URL?
}
struct LiveVoiceMemoDevice: VoiceMemoDevice {
    func requestMicrophone() async -> Bool { await AVCaptureDevice.requestAccess(for: .audio) }
    func recorder(url: URL, settings: [String: Any]) throws -> AVAudioRecorder { try AVAudioRecorder(url: url, settings: settings) }
    func player(url: URL) throws -> AVAudioPlayer { try AVAudioPlayer(contentsOf: url) }
    func exportDestination() -> URL? { let panel = NSSavePanel(); panel.nameFieldStringValue = "Voice memo.m4a"; return panel.runModal() == .OK ? panel.url : nil }
}
@MainActor final class VoiceMemo: NSObject, ObservableObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    @Published var recording = false
    @Published var requesting = false
    @Published var playing = false
    @Published var recordings: [URL] = []
    @Published var paused = false
    @Published var elapsed = 0.0
    @Published var level: Float = 0
    @Published var file: URL?
    @Published var status = "Record a memo locally on this Mac."
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private let library: URL
    private let device: VoiceMemoDevice
    init(library: URL = BrandStorage.supportDirectory.appendingPathComponent("Voice Memos"), device: VoiceMemoDevice = LiveVoiceMemoDevice()) {
        self.library = library; self.device = device
        super.init(); loadLibrary(); file = recordings.first
    }
    func loadLibrary() {
        recordings = ((try? FileManager.default.contentsOfDirectory(at: library, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? [])
            .filter { $0.pathExtension == "m4a" && $0.lastPathComponent.hasPrefix("Memo-") }
            .sorted { Self.modified($0) > Self.modified($1) }
    }
    func selectMemo(_ url: URL) { guard !recording, recordings.contains(url) else { return }; player?.stop(); player = nil; playing = false; file = url; status = "Ready for local playback." }
    static func modified(_ url: URL) -> Date { (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast }
    static func label(_ url: URL) -> String {
        guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { return "Saved memo" }
        return date.formatted(.dateTime.month(.abbreviated).day().hour().minute().second())
    }
    func start() {
        guard !recording, !requesting else { return }; player?.stop(); player = nil; playing = false; requesting = true
        Task { [self] in
            defer { requesting = false }
            let allowed = await device.requestMicrophone()
            guard allowed else { status = "Microphone access is required. Enable DockGrove in Privacy & Security > Microphone."; return }
            do {
                let folder = library
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let url = folder.appendingPathComponent("Memo-\(UUID().uuidString).m4a")
                let r = try device.recorder(url: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue])
                r.delegate = self; r.isMeteringEnabled = true
                guard r.record() else { throw UsageError.service }
                recorder = r; file = url; recording = true; paused = false; elapsed = 0; status = "Recording · saved locally"
                timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in Task { @MainActor [weak self] in
                    guard let self, let recorder = self.recorder else { return }
                    self.elapsed = recorder.currentTime; recorder.updateMeters(); self.level = max(0, min(1, pow(10, recorder.averagePower(forChannel: 0) / 20)))
                } }
            } catch { status = "Could not start recording. Check the microphone and available storage." }
        }
    }
    func togglePause() { guard let recorder, recording else { return }; if paused { if recorder.record() { paused = false; status = "Recording · saved locally" } } else { recorder.pause(); paused = true; status = "Paused" } }
    func stop() { recorder?.stop(); recorder = nil; timer?.invalidate(); timer = nil; recording = false; paused = false; level = 0; loadLibrary(); status = "Memo saved on this Mac." }
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) { Task { @MainActor in self.stop(); self.status = "Recording stopped because the audio encoder failed. Check the saved file." } }
    func play() {
        guard !recording, let file else { return }
        if playing { player?.stop(); player = nil; playing = false; status = "Playback stopped."; return }
        do {
            let audio = try device.player(url: file); audio.delegate = self
            guard audio.play() else { throw UsageError.service }
            player = audio; playing = true; status = "Playing locally in DockGrove."
        } catch { status = "Could not play this recording."; playing = false }
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.playing = false; self.player = nil; self.status = flag ? "Playback complete." : "Playback could not finish." }
    }
    /// Creates the library folder for "All recordings in Finder"; nil (with a status) when it cannot.
    func libraryFolder() -> URL? {
        do { try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true); return library } catch { status = "Could not open the memo folder."; return nil }
    }
    func export() {
        guard !recording, let file else { return }
        if let url = device.exportDestination() {
            do { try Data(contentsOf: file).write(to: url, options: .atomic); status = "Exported memo." } catch { status = "Could not export the memo." }
        }
    }
    deinit { timer?.invalidate(); recorder?.stop(); player?.stop() }
}
struct VoiceMemoView: View {
    @ObservedObject var memo: VoiceMemo
    @Environment(\.widgetEffects) private var effects
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !memo.recording, !memo.recordings.isEmpty {
                Picker("Saved recording", selection: Binding(get: { memo.file }, set: { if let url = $0 { memo.selectMemo(url) } })) { ForEach(memo.recordings, id: \.self) { url in Text(VoiceMemo.label(url)).tag(Optional(url)) } }
            }
            Text(String(format: "%02d:%02d", Int(memo.elapsed) / 60, Int(memo.elapsed) % 60)).font(.system(size: 42, weight: .light)).monospacedDigit()
            ProgressView(value: Double(memo.level)).tint(.red)
            Text(memo.status).font(.caption).foregroundStyle(.secondary)
            if memo.recording { HStack { Button(memo.paused ? "Resume" : "Pause", action: memo.togglePause); Button("Stop & save", action: memo.stop) } }
            else { Button(memo.requesting ? "Requesting microphone…" : "Record new memo", action: memo.start).tint(.red).disabled(memo.requesting) }
            if let file = memo.file, !memo.recording { HStack { Button(memo.playing ? "Stop playback" : "Play", action: memo.play); Button("Export…", action: memo.export); Button("Show in Finder") { effects(.reveal([file])) } } }
            Button("All recordings in Finder") { if let folder = memo.libraryFolder() { effects(.open(folder)) } }
            Text("Recording begins only when you press Record. No audio is uploaded. Memos remain in your local application-support library.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct AppGroup: Identifiable, Codable { var id = UUID(); var name: String; var paths: [String] }
@MainActor final class AppGroups: ObservableObject {
    @Published var groups: [AppGroup] { didSet { if let data = try? JSONEncoder().encode(groups) { defaults.set(data, forKey: "appGroups") } } }
    private let defaults: UserDefaults
    init(defaults: UserDefaults) { self.defaults = defaults; groups = defaults.data(forKey: "appGroups").flatMap { try? JSONDecoder().decode([AppGroup].self, from: $0) } ?? [] }
    func add(name: String, paths: [String]) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var seen = Set<String>(); let paths = paths.filter { $0.hasSuffix(".app") && seen.insert($0).inserted }
        guard !name.isEmpty, !paths.isEmpty else { return }; groups.append(AppGroup(name: String(name.prefix(80)), paths: paths))
    }
}
struct AppGroupsView: View {
    @ObservedObject var groups: AppGroups
    @ObservedObject var model: DockModel
    @State private var name = ""
    @State private var selection = Set<String>()
    @Environment(\.widgetEffects) private var effects
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView { VStack(alignment: .leading, spacing: 16) { ForEach(groups.groups) { group in
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text(group.name).font(.headline); Spacer(); Button("Remove") { groups.groups.removeAll { $0.id == group.id } } }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4)) { ForEach(group.paths, id: \.self) { path in
                        let app = DockApp(url: URL(fileURLWithPath: path))
                        Button { effects(.launch(model, app)) } label: { VStack { Image(nsImage: app.icon).resizable().frame(width: 36, height: 36); Text(app.name).font(.caption2).lineLimit(1) } }.buttonStyle(.plain).disabled(!FileManager.default.fileExists(atPath: path)).help(app.name)
                    } }
                }
            } } }.frame(maxHeight: 180)
            Divider(); TextField("New group name", text: $name)
            ScrollView { VStack(alignment: .leading) { ForEach(model.apps) { app in Toggle(app.name, isOn: Binding(get: { selection.contains(app.id) }, set: { if $0 { selection.insert(app.id) } else { selection.remove(app.id) } })) } } }.frame(maxHeight: 120)
            Button("Create group") { groups.add(name: name, paths: model.apps.map(\.id).filter { selection.contains($0) }); name = ""; selection = [] }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || selection.isEmpty)
            Text("Choose from your pinned apps. Removing a group never deletes its apps.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
struct WebSearchView: View {
    @State private var query = ""
    @State private var engine = "DuckDuckGo"
    @Environment(\.widgetEffects) private var effects
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Search the web", text: $query).onSubmit(search)
            Picker("Search engine", selection: $engine) { ForEach(["DuckDuckGo", "Google", "Bing"], id: \.self) { Text($0) } }
            Button("Search in browser", action: search).disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
    private func search() {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let site = engine == "Google" ? "https://www.google.com/search" : engine == "Bing" ? "https://www.bing.com/search" : "https://duckduckgo.com/"
        var url = URLComponents(string: site)!; url.queryItems = [URLQueryItem(name: "q", value: query)]; if let url = url.url { effects(.open(url)) }
    }
}
