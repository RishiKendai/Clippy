import SwiftUI

/// DESIGN.md §2 colour tokens. Views read colours only from here.
extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }

    static func black(_ a: Double) -> Color { Color(.sRGB, white: 0, opacity: a) }
    static func white(_ a: Double) -> Color { Color(.sRGB, white: 1, opacity: a) }
}

/// Popover tokens (`.clippy` / `.clippy.dark`).
struct PopoverTheme {
    let text, sub, field, divider, hover, icon, accent, popline, imageBorder: Color

    init(_ scheme: ColorScheme) {
        let dark = scheme == .dark
        text = dark ? Color(hex: 0xF5F5F7) : Color(hex: 0x1D1D1F)
        sub = dark ? Color(hex: 0xA5A5AA) : Color(hex: 0x636368)
        field = dark ? .white(0.08) : .black(0.06)
        divider = dark ? .white(0.10) : .black(0.10)
        hover = dark ? .white(0.12) : .black(0.08)
        icon = dark ? Color(hex: 0xB8B8BD) : Color(hex: 0x55555A)
        accent = dark ? Color(hex: 0x1A66D6) : Color(hex: 0x0A64D8)
        popline = dark ? .white(0.14) : .black(0.14)
        imageBorder = .black(0.18)
    }
}

/// Settings window tokens (`.set` / `.set.dark`).
struct SettingsTheme {
    let win, bar, card, text, sub, line, rowline, ring: Color
    let tabText, tabOnText, tabHover, tabOn: Color
    let accent, link, btn, btnBorder, btnActive: Color
    let danger, dangerBg, ok, okDot, swOff, swOn, seg, segOn: Color

    init(_ scheme: ColorScheme) {
        let dark = scheme == .dark
        win = dark ? Color(hex: 0x1C1C1E) : Color(hex: 0xECECEE)
        bar = dark ? Color(hex: 0x2B2B2D) : Color(hex: 0xF6F6F7)
        card = dark ? Color(hex: 0x2C2C2E) : .white
        text = dark ? Color(hex: 0xF5F5F7) : Color(hex: 0x1D1D1F)
        sub = dark ? Color(hex: 0xA5A5AA) : Color(hex: 0x636368)
        line = dark ? .white(0.10) : .black(0.10)
        rowline = dark ? .white(0.08) : .black(0.08)
        ring = dark ? .white(0.08) : .black(0.07)
        tabText = dark ? Color(hex: 0xB8B8BD) : Color(hex: 0x55555A)
        tabOnText = dark ? Color(hex: 0x7AB8FF) : Color(hex: 0x0A5BC4)
        tabHover = dark ? .white(0.07) : .black(0.05)
        tabOn = dark ? .white(0.12) : .black(0.08)
        accent = dark ? Color(hex: 0x1A66D6) : Color(hex: 0x0A64D8)
        link = dark ? Color(hex: 0x6CB0FF) : Color(hex: 0x0A64D8)
        btn = dark ? .white(0.10) : .white
        btnBorder = dark ? .white(0.18) : .black(0.15)
        btnActive = dark ? .white(0.16) : Color(hex: 0xF0F0F0)
        danger = dark ? Color(hex: 0xFF7D75) : Color(hex: 0xC4271C)
        dangerBg = dark ? Color(.sRGB, red: 1, green: 69 / 255, blue: 58 / 255, opacity: 0.12) : Color(hex: 0xFFF6F5)
        ok = dark ? Color(hex: 0x4CD964) : Color(hex: 0x1B7A34)
        okDot = dark ? Color(hex: 0x30D158) : Color(hex: 0x28A745)
        swOff = Color(.sRGB, red: 120 / 255, green: 120 / 255, blue: 128 / 255, opacity: dark ? 0.40 : 0.30)
        swOn = dark ? Color(hex: 0x0A84FF) : Color(hex: 0x007AFF)
        seg = dark ? .white(0.10) : .black(0.07)
        segOn = dark ? Color(hex: 0x636366) : .white
    }
}

/// In this SDK `@State` is a macro whose plugin ships only with Xcode, not the Command Line
/// Tools. This alias names the underlying property wrapper directly. Use `@ViewState`, never `@State`.
typealias ViewState = SwiftUI.State
