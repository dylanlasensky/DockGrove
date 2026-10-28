import AppKit

/// A page contains whole tiles only. Navigation and Settings are outside the page.
struct DockPageLayout {
    static let gap: CGFloat = 12
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
    func width(iconSize: Double) -> CGFloat {
        switch self { case .app: return iconSize + 8; case .add: return 28; case .usage: return 177; case .clock: return 100
        case .tool(let kind): return kind == .separator ? 1 : kind == .spacer ? 24 : 72 }
    }
}
