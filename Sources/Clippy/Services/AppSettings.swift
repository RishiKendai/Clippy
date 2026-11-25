import AppKit
import Carbon
import ClippyCore

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

/// Shortcut that opens the popover. ⇧⌘V is reserved for plain-text paste (see CLAUDE.md).
enum OpenShortcut: String, CaseIterable, Identifiable {
    case optionCommandV, controlOptionV, controlCommandV, none
    var id: String { rawValue }
    var label: String {
        switch self {
        case .optionCommandV: "⌥⌘V"
        case .controlOptionV: "⌃⌥V"
        case .controlCommandV: "⌃⌘V"
        case .none: "None"
        }
    }
    /// Carbon modifier mask, or nil for `.none`.
    var carbonModifiers: UInt32? {
        switch self {
        case .optionCommandV: UInt32(optionKey | cmdKey)
        case .controlOptionV: UInt32(controlKey | optionKey)
        case .controlCommandV: UInt32(controlKey | cmdKey)
        case .none: nil
        }
    }
}

/// User preferences (Settings window), persisted in UserDefaults.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    @Published var appearance: Appearance { didSet { save(appearance.rawValue, "appearance"); applyAppearance() } }
    @Published var launchAtLogin: Bool { didSet { save(launchAtLogin, "launchAtLogin") } }
    @Published var openShortcut: OpenShortcut { didSet { save(openShortcut.rawValue, "openShortcut") } }
    @Published var autoPaste: Bool { didSet { save(autoPaste, "autoPaste") } }
    @Published var playSound: Bool { didSet { save(playSound, "playSound") } }
    @Published var keepDays: Int { didSet { save(keepDays, "keepDays") } }
    @Published var maxText: Int { didSet { save(maxText, "maxText") } }
    @Published var maxImages: Int { didSet { save(maxImages, "maxImages") } }
    @Published var ignoreSecrets: Bool { didSet { save(ignoreSecrets, "ignoreSecrets") } }
    /// Rows shown before the History / Pinned lists scroll (popover shrinks further if the screen is short).
    @Published var historyRows: Int { didSet { save(historyRows, "historyRows") } }
    @Published var pinnedRows: Int { didSet { save(pinnedRows, "pinnedRows") } }
    static let visibleRowsRange = 5...15

    private init() {
        defaults.register(defaults: [
            "appearance": Appearance.system.rawValue,
            "launchAtLogin": true,
            "openShortcut": OpenShortcut.optionCommandV.rawValue,
            "autoPaste": true,
            "playSound": false,
            "keepDays": 30,
            "maxText": 300,
            "maxImages": 100,
            "ignoreSecrets": true,
            "historyRows": 10,
            "pinnedRows": 10,
        ])
        appearance = Appearance(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
        launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        openShortcut = OpenShortcut(rawValue: defaults.string(forKey: "openShortcut") ?? "") ?? .optionCommandV
        autoPaste = defaults.bool(forKey: "autoPaste")
        playSound = defaults.bool(forKey: "playSound")
        keepDays = defaults.integer(forKey: "keepDays")
        maxText = defaults.integer(forKey: "maxText")
        maxImages = defaults.integer(forKey: "maxImages")
        ignoreSecrets = defaults.bool(forKey: "ignoreSecrets")
        historyRows = Self.visibleRowsRange.clamp(defaults.integer(forKey: "historyRows"))
        pinnedRows = Self.visibleRowsRange.clamp(defaults.integer(forKey: "pinnedRows"))
    }

    var limits: HistoryLimits { HistoryLimits(maxText: maxText, maxImages: maxImages, keepDays: keepDays) }

    /// True only on the very first launch (used to register the login item once).
    func consumeFirstLaunch() -> Bool {
        if defaults.bool(forKey: "didFirstLaunch") { return false }
        defaults.set(true, forKey: "didFirstLaunch")
        return true
    }

    /// System = follow macOS live; Light/Dark override both the popover and Settings.
    func applyAppearance() {
        switch appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func save(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }
}

extension ClosedRange where Bound == Int {
    func clamp(_ value: Int) -> Int { Swift.min(Swift.max(value, lowerBound), upperBound) }
}
