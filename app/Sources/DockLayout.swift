import AppKit

/// A page contains whole tiles only. Navigation and Settings are outside the page.
struct DockPageLayout {
    static let gap: CGFloat = 10
    static let chrome: CGFloat = 154 // padding, previous/next, count and Settings
    static func pages(widths: [CGFloat], available: CGFloat) -> [[Int]] {
        guard !widths.isEmpty else { return [[]] }
        let capacity = max(1, available)
        var result: [[Int]] = [], page: [Int] = [], used: CGFloat = 0
        for (i, width) in widths.enumerated() {
            let needed = width + (page.isEmpty ? 0 : gap)
            if !page.isEmpty && used + needed > capacity { result.append(page); page = []; used = 0 }
            used += width + (page.isEmpty ? 0 : gap); page.append(i)
        }
        if !page.isEmpty { result.append(page) }
        return result
    }
    static func bodyWidth(screenWidth: CGFloat, naturalWidth: CGFloat) -> CGFloat {
        max(1, min(screenWidth - 44, naturalWidth + chrome))
    }
}

enum DockEntry: Identifiable {
    case app(DockApp), add, usage, tool(ToolKind), clock
    var id: String {
        switch self { case .app(let a): return "app:" + a.id; case .add: return "add"; case .usage: return "usage"; case .tool(let k): return k.rawValue; case .clock: return "clock" }
    }
    var title: String {
        switch self { case .app(let a): return a.name; case .add: return "Add app"; case .usage: return "Codex usage"; case .tool(let k): return k.title; case .clock: return "Clock" }
    }
    func width(iconSize: Double, rich: Bool = true) -> CGFloat {
        switch self { case .app: return iconSize + 8; case .add: return 28; case .usage: return rich ? 202 : 177; case .clock: return rich ? 136 : 100
        case .tool(let kind):
            if kind == .separator { return 1 }; if kind == .spacer { return 24 }; if !rich { return 72 }
            switch kind { case .spotify, .appleMusic, .music, .calendar, .googleCalendar: return 236
            case .tasks, .notes: return 208
            case .focus, .stopwatch: return 170
            case .system, .progress, .appGroups, .water: return 184
            default: return 174 } }
    }
}
