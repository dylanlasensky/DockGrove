import AppKit
import SwiftUI
import Darwin
import CoreAudio

struct SystemSample {
    var cpu: Double
    var memory: Double
    var received: UInt64
    var sent: UInt64
}
@MainActor final class SystemMonitor: ObservableObject {
    @Published var cpu = 0.0
    @Published var memory = 0.0
    @Published var download = 0.0
    @Published var upload = 0.0
    @Published var history: [Double] = []
    @Published var available = false
    private var timer: Timer?
    private var previousCPU: (UInt64, UInt64)?
    private var previousNetwork: (UInt64, UInt64, Date)?
    func start() {
        guard timer == nil else { return }; sample()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in Task { @MainActor in self?.sample() } }
    }
    func stop() { timer?.invalidate(); timer = nil; previousNetwork = nil; previousCPU = nil }
    deinit { timer?.invalidate() }
    static func rate(previous: UInt64, current: UInt64, elapsed: Double) -> Double {
        guard elapsed > 0, current >= previous else { return 0 }; return Double(current - previous) / elapsed
    }
    func sample() {
        var load = host_cpu_load_info(), count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &load) { ptr in ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) } }
        if result == KERN_SUCCESS {
            let ticks = load.cpu_ticks
            let idle = UInt64(ticks.2), total = UInt64(ticks.0) + UInt64(ticks.1) + idle + UInt64(ticks.3)
            if let old = previousCPU, total > old.0, idle >= old.1 {
                cpu = max(0, min(100, 100 * (1 - Double(idle - old.1) / Double(total - old.0))))
                history.append(cpu); history = Array(history.suffix(40)); available = true
            }
            previousCPU = (total, idle)
        }
        var vm = vm_statistics64(), vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &vm) { ptr in ptr.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &vmCount) } }
        if status == KERN_SUCCESS {
            let used = UInt64(vm.active_count) + UInt64(vm.wire_count) + UInt64(vm.compressor_page_count)
            memory = min(100, Double(used) * Double(vm_kernel_page_size) / Double(ProcessInfo.processInfo.physicalMemory) * 100)
        }
        var address: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&address) == 0 {
            defer { freeifaddrs(address) }
            var current = address, received: UInt64 = 0, sent: UInt64 = 0
            while let item = current {
                defer { current = item.pointee.ifa_next }
                guard item.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK), item.pointee.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
                      let data = item.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
                received += UInt64(data.pointee.ifi_ibytes); sent += UInt64(data.pointee.ifi_obytes)
            }
            let now = Date()
            if let old = previousNetwork { download = Self.rate(previous: old.0, current: received, elapsed: now.timeIntervalSince(old.2)); upload = Self.rate(previous: old.1, current: sent, elapsed: now.timeIntervalSince(old.2)) }
            previousNetwork = (received, sent, now)
        }
    }
    static func speed(_ value: Double) -> String { ByteCountFormatter.string(fromByteCount: Int64(max(0, min(value, Double(Int64.max / 2)))), countStyle: .file) + "/s" }
}

struct AudioOutput: Identifiable, Hashable { let id: AudioDeviceID; let name: String }
@MainActor final class AudioControl: ObservableObject {
    @Published var outputs: [AudioOutput] = []
    @Published var selected: AudioDeviceID = 0
    @Published var volume: Float = 0
    @Published var adjustable = false
    @Published var status = ""
    static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }
    func refresh() {
        var key = Self.address(kAudioHardwarePropertyDevices), size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &key, 0, nil, &size) == noErr else { status = "Audio outputs unavailable."; return }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &key, 0, nil, &size, &ids) == noErr else { return }
        outputs = ids.compactMap { id in
            var streams = Self.address(kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput), bytes: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &bytes) == noErr, bytes > 0 else { return nil }
            var name: Unmanaged<CFString>?, nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size), nameKey = Self.address(kAudioObjectPropertyName)
            guard AudioObjectGetPropertyData(id, &nameKey, 0, nil, &nameSize, &name) == noErr else { return nil }
            guard let name else { return nil }; return AudioOutput(id: id, name: name.takeRetainedValue() as String)
        }
        var deviceKey = Self.address(kAudioHardwarePropertyDefaultOutputDevice), deviceSize = UInt32(MemoryLayout<AudioDeviceID>.size), device: AudioDeviceID = 0
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &deviceKey, 0, nil, &deviceSize, &device) == noErr else { return }
        selected = device
        var volumeKey = Self.address(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput), volumeSize = UInt32(MemoryLayout<Float>.size), value: Float = 0, writable: DarwinBoolean = false
        adjustable = AudioObjectGetPropertyData(device, &volumeKey, 0, nil, &volumeSize, &value) == noErr && AudioObjectIsPropertySettable(device, &volumeKey, &writable) == noErr && writable.boolValue
        volume = value
        status = adjustable ? "System output volume" : "This output uses its own volume controls."
    }
    func setVolume(_ value: Float) {
        guard adjustable else { return }
        var key = Self.address(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput), v = min(1, max(0, value))
        if AudioObjectSetPropertyData(selected, &key, 0, nil, UInt32(MemoryLayout<Float>.size), &v) == noErr { volume = v } else { status = "The output refused the volume change." }
    }
    func select(_ id: AudioDeviceID) {
        guard outputs.contains(where: { $0.id == id }) else { return }
        var key = Self.address(kAudioHardwarePropertyDefaultOutputDevice), value = id
        if AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &key, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &value) == noErr { refresh() } else { status = "Could not change the audio output." }
    }
}
struct SystemDetailView: View {
    @ObservedObject var monitor: SystemMonitor
    @ObservedObject var kit: Toolkit
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Label("CPU", systemImage: "cpu"); Spacer(); Text(monitor.available ? "\(Int(monitor.cpu))%" : "Sampling…").monospacedDigit() }
            Sparkline(values: monitor.history, color: .cyan).frame(height: 70)
            HStack { Text("Memory in use"); Spacer(); Text("\(Int(monitor.memory))%") }
            ProgressView(value: monitor.memory, total: 100)
            HStack { Label(SystemMonitor.speed(monitor.download), systemImage: "arrow.down"); Spacer(); Label(SystemMonitor.speed(monitor.upload), systemImage: "arrow.up") }.font(.caption).monospacedDigit()
            Divider(); Text(kit.battery); Text(kit.memory); Text(kit.storage)
            Text("CPU sampled every 2 seconds. Memory includes active, wired and compressed pages. Network totals include active interfaces; VPN traffic may be counted twice.").font(.caption).foregroundStyle(.secondary)
        }.onAppear { monitor.start() }
    }
}
struct AudioControlView: View {
    @ObservedObject var audio: AudioControl
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Output", selection: Binding(get: { audio.selected }, set: { audio.select($0) })) { ForEach(audio.outputs) { Text($0.name).tag($0.id) } }
            HStack { Image(systemName: "speaker.fill"); Slider(value: Binding(get: { audio.volume }, set: { audio.setVolume($0) }), in: 0...1).disabled(!audio.adjustable); Image(systemName: "speaker.wave.3.fill") }
            Text(audio.status).font(.caption).foregroundStyle(.secondary)
            Button("Refresh outputs", action: audio.refresh)
        }.onAppear(perform: audio.refresh)
    }
}
