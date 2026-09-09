import SwiftUI

/// Design tokens for AISEE-BIN, taken from the Claude Design canvas
/// ("AISEE-BIN iPhone.dc.html", 11 artboards).
///
/// Two surfaces, deliberately opposite:
/// * **Navigate** is dark and audio-first — the visitor may never look at it, and a
///   sighted helper glances at it for one second in bright greenhouse light.
/// * **Author** is light — it is held up and read continuously by a sighted mapper.
///
/// Type uses the semantic styles rather than the canvas's fixed pixel sizes so that
/// Dynamic Type reaches the accessibility sizes; the canvas was drawn at 402 pt wide
/// (iPhone 17 Pro), where its px values map 1:1 to the base sizes below.
enum DS {

    // MARK: - Navigate (dark)

    enum N {
        static let canvas       = Color(dsHex: 0x0C0B12)
        static let dock         = Color(dsHex: 0x17151F)
        static let raised       = Color(dsHex: 0x211E2C)
        static let sunk         = Color(dsHex: 0x1E1B29)
        static let segmentTrack = Color(dsHex: 0x1B1826)
        static let panel        = Color(dsHex: 0x17151F).opacity(0.92)

        static let ink          = Color(dsHex: 0xF7F5FD)
        static let inkSecondary = Color(dsHex: 0xDCD7EA)
        static let inkTertiary  = Color(dsHex: 0xB4AEC6)
        static let inkMuted     = Color(dsHex: 0x8C86A3)
        static let inkDisabled  = Color(dsHex: 0x6B6580)

        static let talk         = Color(dsHex: 0x6B4FD8)
        static let talkStroke   = Color(dsHex: 0x9B87E8)
        static let accent       = Color(dsHex: 0xB9A6FF)

        static let okBg         = Color(dsHex: 0x0F2A1E)
        static let okStroke     = Color(dsHex: 0x2C7A56)
        static let okText       = Color(dsHex: 0x5EE6A8)
        static let okSolid      = Color(dsHex: 0x2FA878)
        static let okBody       = Color(dsHex: 0xA8EFCC)
        static let okHint       = Color(dsHex: 0xCFF3E2)

        static let warnBg       = Color(dsHex: 0x2C2005)
        static let warnStroke   = Color(dsHex: 0x8A6A17)
        static let warnText     = Color(dsHex: 0xFFC24B)
        static let warnBody     = Color(dsHex: 0xFFE0A8)

        static let stop         = Color(dsHex: 0xD92B45)
        static let stopStroke   = Color(dsHex: 0xFF7A8C)
        static let stopBody     = Color(dsHex: 0xFFDBE1)
        static let hearing      = Color(dsHex: 0xFF9AA8)

        static let offRoute     = Color(dsHex: 0xFF8A3D)
        static let offRouteInk  = Color(dsHex: 0x2A1400)
        static let offRouteBody = Color(dsHex: 0x3E1F00)

        static let hairline     = Color(dsHex: 0xF7F5FD).opacity(0.14)
        static let hairlineSoft = Color(dsHex: 0xF7F5FD).opacity(0.10)
    }

    // MARK: - Author (light)

    enum A {
        static let canvas = Color(dsHex: 0xF7F5FD)
        static let card   = Color.white
        static let inset  = Color(dsHex: 0xF1EFF7)

        static let ink          = Color(dsHex: 0x191627)
        static let inkSecondary = Color(dsHex: 0x4A4460)
        static let inkTertiary  = Color(dsHex: 0x5B5570)
        static let inkMuted     = Color(dsHex: 0x8A84A0)
        static let inkDisabled  = Color(dsHex: 0x9A94AD)

        static let hairline    = Color(dsHex: 0xE4E0F0)
        static let hairlineLav = Color(dsHex: 0xD9CFFA)

        static let lavender       = Color(dsHex: 0x5B3FD1)
        static let lavenderDeep   = Color(dsHex: 0x3E2AA0)
        static let lavenderInk    = Color(dsHex: 0x241A52)
        static let lavenderBody   = Color(dsHex: 0x4A3C7A)
        static let lavenderBg     = Color(dsHex: 0xEFEAFF)
        static let lavenderStroke = Color(dsHex: 0xC9B9F7)
        static let lavenderTrack  = Color(dsHex: 0xDCD0FB)

        static let okBg     = Color(dsHex: 0xE8F7EF)
        static let okStroke = Color(dsHex: 0x9BD8BC)
        static let okText   = Color(dsHex: 0x0E6B49)
        static let okDeep   = Color(dsHex: 0x0E5A3E)
        static let okDot    = Color(dsHex: 0x1FA97A)

        static let warnBg     = Color(dsHex: 0xFFF3E0)
        static let warnStroke = Color(dsHex: 0xE9A23B)
        static let warnIcon   = Color(dsHex: 0x8A4B00)
        static let warnText   = Color(dsHex: 0x7A4200)

        static let dangerBg   = Color(dsHex: 0xFDEAE8)
        static let dangerText = Color(dsHex: 0x9B2A22)
        static let destructive = Color(dsHex: 0xC23A32)

        static let segmentIdleBg = Color(dsHex: 0xE7E2F5)
    }

    // MARK: - Node categories
    //
    // Never colour alone: every use pairs the dot with the category word.

    enum Cat {
        static func dot(_ c: POICategory) -> Color {
            switch c {
            case .destination: return Color(dsHex: 0x5B7CFA)
            case .junction:    return Color(dsHex: 0x8E8AA3)
            case .exhibit:     return Color(dsHex: 0x1FA97A)
            case .hazard:      return Color(dsHex: 0xE0524A)
            }
        }

        static func chipBg(_ c: POICategory) -> Color {
            switch c {
            case .destination: return Color(dsHex: 0xE9EEFF)
            case .junction:    return Color(dsHex: 0xEFEEF3)
            case .exhibit:     return Color(dsHex: 0xE8F7EF)
            case .hazard:      return Color(dsHex: 0xFDEAE8)
            }
        }

        static func chipInk(_ c: POICategory) -> Color {
            switch c {
            case .destination: return Color(dsHex: 0x2340B8)
            case .junction:    return Color(dsHex: 0x4C4859)
            case .exhibit:     return Color(dsHex: 0x0E6B49)
            case .hazard:      return Color(dsHex: 0x9B2A22)
            }
        }
    }

    // MARK: - Radii

    enum R {
        static let dock: CGFloat     = 36
        static let card: CGFloat     = 28
        static let panel: CGFloat    = 22
        static let control: CGFloat  = 22
        static let field: CGFloat    = 16
        static let row: CGFloat      = 18
        static let segment: CGFloat  = 14
        static let chip: CGFloat     = 6
    }
}

extension Color {
    /// `Color(dsHex: 0x9B87E8)` — sRGB, opaque.
    init(dsHex hex: UInt32) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >>  8) & 0xFF) / 255,
                  blue:  Double( hex        & 0xFF) / 255,
                  opacity: 1)
    }
}

extension Font {
    // Canvas px -> nearest semantic style, so accessibility sizes still grow.
    static let dsDisplay  = Font.largeTitle.weight(.bold)   // 32–34
    static let dsTitle    = Font.title.weight(.bold)        // 28–30
    static let dsTitle2   = Font.title2.weight(.bold)       // 22–23
    static let dsTitle3   = Font.title3.weight(.semibold)   // 20–21
    static let dsHeadline = Font.headline                   // 17–19 semibold
    static let dsBody     = Font.body                       // 17
    static let dsCallout  = Font.callout                    // 16
    static let dsSubhead  = Font.subheadline                // 15
    static let dsFootnote = Font.footnote                   // 13–14
    static let dsCaption  = Font.caption.weight(.semibold)  // 12–13
    static let dsMono     = Font.footnote.monospaced()
    static let dsMonoTiny = Font.caption2.monospaced()
}

extension View {
    /// Inset hairline stroke, the canvas's `box-shadow: inset 0 0 0 Npx C`.
    func dsStroke(_ color: Color, _ width: CGFloat = 1, radius: CGFloat) -> some View {
        overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(color, lineWidth: width))
    }

    /// Uppercase tracked label used for section eyebrows.
    func dsEyebrow(_ color: Color) -> some View {
        font(.dsCaption).textCase(.uppercase).kerning(1.2).foregroundStyle(color)
    }
}

/// Navigate / Author switcher. Chrome follows the mode it is sitting on:
/// dark over the Navigate camera, light over the Author tool.
struct ModeSwitcher: View {
    @Binding var mode: AppMode

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppMode.allCases) { candidate in
                let isOn = candidate == mode
                Button { mode = candidate } label: {
                    Text(candidate.rawValue)
                        .font(isOn ? .dsHeadline : .dsBody)
                        .foregroundStyle(ink(on: isOn))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(fill(on: isOn), in: RoundedRectangle(cornerRadius: DS.R.segment, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .background(mode == .navigation ? DS.N.canvas : DS.A.canvas)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mode")
    }

    private func ink(on selected: Bool) -> Color {
        switch (mode, selected) {
        case (.navigation, true):  return DS.A.ink
        case (.navigation, false): return DS.N.inkTertiary
        case (.authoring, true):   return DS.N.ink
        case (.authoring, false):  return DS.A.inkTertiary
        }
    }

    private func fill(on selected: Bool) -> Color {
        switch (mode, selected) {
        case (.navigation, true):  return DS.N.ink
        case (.navigation, false): return DS.N.segmentTrack
        case (.authoring, true):   return DS.A.ink
        case (.authoring, false):  return DS.A.segmentIdleBg
        }
    }
}
