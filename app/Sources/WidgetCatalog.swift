import Foundation

enum ToolKind: String, CaseIterable, Identifiable {
    case pet, claudeCodeUsage, geminiUsage
    case calculator, currency, voiceMemo, audio, appGroups, webSearch
    case search, focus, notes, tasks, files, system, calendar, clipboard, weather, music
    case bookmarks, folders, stopwatch, water, habits, progress, clocks, converter, capture, colors, controls, reminders, spacer, separator, github
    case windows, googleCalendar, spotify, appleMusic, openaiUsage, anthropicUsage, cursorUsage
    var id: String { rawValue }
    var title: String { switch self {
    case .pet: return "Companion cat"
    case .claudeCodeUsage: return "Claude Code limits"; case .geminiUsage: return "Gemini CLI usage"
    case .calculator: return "Calculator"; case .currency: return "Currency"; case .voiceMemo: return "Voice memo"; case .audio: return "Audio"; case .appGroups: return "App groups"; case .webSearch: return "Web search"
    case .windows: return "Windows"; case .googleCalendar: return "Google Calendar"; case .spotify: return "Spotify"; case .appleMusic: return "Apple Music"; case .openaiUsage: return "OpenAI API usage"; case .anthropicUsage: return "Claude API usage"; case .cursorUsage: return "Cursor team usage"
    case .github: return "GitHub"; case .bookmarks: return "Bookmarks"; case .folders: return "Folders & Downloads"; case .stopwatch: return "Stopwatch"
    case .water: return "Drink water"; case .habits: return "Habits"; case .progress: return "Time progress"; case .clocks: return "World clocks"
    case .converter: return "Converter"; case .capture: return "Screenshot"; case .colors: return "Color picker"; case .controls: return "Quick controls"
    case .reminders: return "Reminders"; case .spacer: return "Space"; case .separator: return "Separator"
    case .weather: return "Weather"; case .music: return "Music"; case .search: return "App search"; case .focus: return "Focus"; case .notes: return "Quick note"; case .tasks: return "Tasks"
    case .files: return "File shelf"; case .system: return "System"; case .calendar: return "Calendar"; case .clipboard: return "Clipboard"
    } }
    var icon: String { switch self {
    case .pet: return "cat"
    case .claudeCodeUsage: return "sparkles"; case .geminiUsage: return "diamond"
    case .calculator: return "equal"; case .currency: return "dollarsign.arrow.circlepath"; case .voiceMemo: return "waveform"; case .audio: return "speaker.wave.2"; case .appGroups: return "square.grid.2x2"; case .webSearch: return "globe"
    case .windows: return "rectangle.split.2x2"; case .googleCalendar: return "calendar.badge.clock"; case .spotify: return "music.note.list"; case .appleMusic: return "music.note"; case .openaiUsage, .anthropicUsage, .cursorUsage: return "chart.bar"
    case .github: return "chevron.left.forwardslash.chevron.right"; case .bookmarks: return "bookmark"; case .folders: return "folder"; case .stopwatch: return "stopwatch"
    case .water: return "drop"; case .habits: return "checkmark.seal"; case .progress: return "chart.pie"; case .clocks: return "globe"
    case .converter: return "arrow.left.arrow.right"; case .capture: return "camera.viewfinder"; case .colors: return "eyedropper"; case .controls: return "switch.2"
    case .reminders: return "list.bullet"; case .spacer: return "space"; case .separator: return "line.diagonal"
    case .weather: return "cloud.sun"; case .music: return "music.note"; case .search: return "magnifyingglass"; case .focus: return "timer"; case .notes: return "note.text"; case .tasks: return "checklist"
    case .files: return "tray.full"; case .system: return "gauge.with.dots.needle.50percent"; case .calendar: return "calendar"; case .clipboard: return "doc.on.clipboard"
    } }
}
extension ToolKind {
    var requiredAccess: AccessTier {
        switch self {
        case .search, .focus, .tasks, .spacer, .separator: return .free
        case .pet, .claudeCodeUsage, .geminiUsage, .openaiUsage, .anthropicUsage, .cursorUsage, .github: return .full
        case .calculator, .currency, .voiceMemo, .audio, .appGroups, .webSearch,
             .notes, .files, .system, .calendar, .clipboard, .weather, .music,
             .bookmarks, .folders, .stopwatch, .water, .habits, .progress, .clocks,
             .converter, .capture, .colors, .controls, .reminders,
             .windows, .googleCalendar, .spotify, .appleMusic: return .plus
        }
    }
}
