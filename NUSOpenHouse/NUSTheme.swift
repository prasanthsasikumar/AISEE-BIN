import SwiftUI

/// NUS colours for NUS Computing Tour (AISEE-BIN's `DS` tokens are untouched).
enum NUS {
    /// The guide's name on screen. One place, so the mascot can be renamed.
    static let mascot = "SoCCat"
    static let blue = Color(dsHex: 0x003D7C)
    static let orange = Color(dsHex: 0xEF7C00)
    static let ink = Color(dsHex: 0x14213D)
    static let inkSecondary = Color(dsHex: 0x4A5876)
    static let canvas = Color(dsHex: 0xF5F7FB)
    static let card = Color.white
    static let ok = Color(dsHex: 0x1F9D6B)
    static let warn = Color(dsHex: 0xC77700)
}

/// Big rounded action button.
struct NUSButtonStyle: ButtonStyle {
    var fill: Color
    var ink: Color = .white
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? 1 : 0.6)
            .font(.title3.weight(.semibold))
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity, minHeight: 64)
            .padding(.horizontal, 20)
            .background(fill.opacity(!isEnabled ? 0.35 : configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
