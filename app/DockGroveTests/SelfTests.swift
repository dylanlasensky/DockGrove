import Foundation
@testable import DockGrove

@MainActor func runSelfTests(codexFixture: String? = nil) {
    let modern = #"{"rateLimits":{"limitId":"codex","primary":{"usedPercent":70,"windowDurationMins":300,"resetsAt":2000000000}},"rateLimitsByLimitId":{"codex":{"limitId":"codex","primary":{"usedPercent":30.5,"windowDurationMins":300,"resetsAt":2000000000},"secondary":{"usedPercent":10,"windowDurationMins":10080}},"other":{"limitId":"other","limitName":"Other model","primary":{"usedPercent":100,"windowDurationMins":60}}}}"#
    do {
        try runBehaviorTests()
        try runAppManagementTests()
        try runDockStudioTests()
        try runLicensingTests()
        let response = try JSONDecoder().decode(UsageResponse.self, from: Data(modern.utf8))
        precondition(response.buckets.count == 2)
        precondition(response.buckets.first?.0 == "codex")
        precondition(response.buckets.first?.1.primary?.remaining == 69.5)
        precondition(response.buckets.first?.1.primary?.title == "5 hour")
        precondition(response.buckets.first?.1.secondary?.title == "7 day")
        let legacy = try JSONDecoder().decode(UsageResponse.self, from: Data(#"{"rateLimits":{"limitId":"codex","primary":{"usedPercent":120},"secondary":null}}"#.utf8))
        precondition(legacy.buckets.count == 1 && legacy.buckets.first?.1.primary?.remaining == 0)
        let empty = try JSONDecoder().decode(UsageResponse.self, from: Data(#"{"rateLimits":null,"rateLimitsByLimitId":{}}"#.utf8))
        precondition(empty.buckets.isEmpty)
        let profile = DockProfile(name: "Work", apps: ["/Applications/ChatGPT.app"], widgets: ["focus", "tasks"], accent: "Mint", size: 48)
        let profileData = try JSONEncoder().encode([profile])
        let roundTrip = try JSONDecoder().decode([DockProfile].self, from: profileData)
        precondition(roundTrip.first?.id == profile.id && roundTrip.first?.widgets == ["focus", "tasks"])
        let task = TaskItem(title: "Check build", done: true)
        let decodedTask = try JSONDecoder().decode(TaskItem.self, from: JSONEncoder().encode(task))
        precondition(decodedTask.done)
        precondition(Set(ToolKind.allCases.map(\.rawValue)).count == ToolKind.allCases.count)
        let supportProbe = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: supportProbe, withIntermediateDirectories: true)
        precondition(BrandStorage.supportDirectory(in: supportProbe).lastPathComponent == "DockGrove")
        try FileManager.default.createDirectory(at: supportProbe.appendingPathComponent("WaveDock"), withIntermediateDirectories: true)
        precondition(BrandStorage.supportDirectory(in: supportProbe).lastPathComponent == "WaveDock")
        try FileManager.default.removeItem(at: supportProbe)
        let suite = "DockGroveTests." + UUID().uuidString
        let isolated = UserDefaults(suiteName: suite)!
        defer { isolated.removePersistentDomain(forName: suite) }
        let model = DockModel(defaults: isolated)
        let a = DockApp(url: URL(fileURLWithPath: "/A.app"))
        let b = DockApp(url: URL(fileURLWithPath: "/B.app"))
        let c = DockApp(url: URL(fileURLWithPath: "/C.app"))
        model.apps = [a, b, c]
        model.reorder(a.id, before: c)
        precondition(model.apps == [b, a, c])
        model.reorder(c.id, before: b)
        precondition(model.apps == [c, b, a])
        model.applyProfile(DockProfile(name: "Imported", apps: [], widgets: ["focus", "focus", "unknown"], accent: "Mint", size: 500))
        precondition(model.toolkit.enabled == ["focus"] && model.iconSize == 64)
        do { _ = try UsageClient.fetch(custom: "/usr/bin/true"); preconditionFailure("Early exit must fail") } catch { }
        print("PASS: reorder in both directions, profile sanitization, early subprocess exit")
        print("PASS: layouts and tasks persist losslessly; widget identifiers are unique")
        print("PASS: multi-bucket response, legacy fallback, window labels, percentage bounds, missing windows")
        if let codexFixture {
            let fixture = try UsageClient.fetch(custom: codexFixture)
            precondition(fixture.buckets.first?.1.primary?.remaining == 63)
            print("PASS: subprocess initialize/initialized handshake and rate-limits response")
        }
    } catch { fatalError("Self-test failed: \(error)") }
}
