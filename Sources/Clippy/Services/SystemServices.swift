import AppKit
import ApplicationServices
import Carbon
import ServiceManagement

/// Launch at login via SMAppService (works only from the installed .app bundle).
enum LoginItemManager {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
            return true
        } catch {
            NSLog("Clippy: launch at login change failed: \(error)")
            return false
        }
    }
}

/// Accessibility permission, needed to synthesize ⌘V into other apps.
enum Permissions {
    /// The Accessibility switch in System Settings. `AXIsProcessTrusted` reflects changes live;
    /// `CGPreflightPostEventAccess` only updates when the app restarts, so it must not gate pasting
    /// (it kept a freshly granted Clippy from pasting until relaunch). See `needsRelaunchForEvents`.
    static var accessibilityGranted: Bool { AXIsProcessTrusted() || CGPreflightPostEventAccess() }

    /// Granted in System Settings, but this process still can't post events: it must restart.
    static var needsRelaunchForEvents: Bool { AXIsProcessTrusted() && !CGPreflightPostEventAccess() }

    /// Shows the system prompt (once per app identity) if not yet granted.
    @discardableResult
    static func requestAccessibility() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if !CGPreflightPostEventAccess() { CGRequestPostEventAccess() }
        return trusted || CGPreflightPostEventAccess()
    }

    /// Starts a new instance of Clippy and quits this one.
    @MainActor
    static func relaunch() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        config.activates = false
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Global hotkeys through Carbon's RegisterEventHotKey (no extra permission needed).
@MainActor
final class HotKeyManager {
    static let shared = HotKeyManager()

    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: () -> Void] = [:]
    private var installed = false
    private static let signature: OSType = 0x434C_5059 // 'CLPY'

    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        installHandlerIfNeeded()
        unregister(id: id)
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            refs[id] = ref
            handlers[id] = handler
        } else {
            NSLog("Clippy: could not register hotkey \(id) (status \(status))")
        }
    }

    func unregister(id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
        handlers.removeValue(forKey: id)
    }

    fileprivate func fire(_ id: UInt32) { handlers[id]?() }

    private func installHandlerIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let id = hotKeyID.id
            // Carbon delivers application events on the main thread.
            MainActor.assumeIsolated { HotKeyManager.shared.fire(id) }
            return noErr
        }, 1, &spec, nil, nil)
    }
}

enum KeyCode {
    static let v: UInt16 = 9
    static let p: UInt16 = 35
    static let q: UInt16 = 12
    static let comma: UInt16 = 43
    static let returnKey: UInt16 = 36
    static let keypadEnter: UInt16 = 76
    static let escape: UInt16 = 53
    static let delete: UInt16 = 51
    static let forwardDelete: UInt16 = 117
    static let up: UInt16 = 126
    static let down: UInt16 = 125
}
