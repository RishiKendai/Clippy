import AppKit
import SwiftUI

/// The 600×540 Settings window. Its title follows the selected tab.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let settings: AppSettings
    private let model: ClipListModel
    private let nav = SettingsNavigation()

    init(settings: AppSettings, model: ClipListModel) {
        self.settings = settings
        self.model = model
    }

    func show(tab: SettingsTab? = nil) {
        if let tab { nav.tab = tab }
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 540),
                             styleMask: [.titled, .closable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.title = nav.tab.rawValue
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(settings: settings, model: model, onTabChange: { [weak w] tab in
                w?.title = tab.rawValue
            }, nav: nav))
            w.center()
            window = w
        }
        window?.title = nav.tab.rawValue
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
