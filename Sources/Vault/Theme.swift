import AppKit
import CoreText
import SwiftUI

/// Tokens of the Vault design system (claude.ai/artifact/21hQm2FSHgtY5X8UWwFkbm).
/// Visual fixes go here, not in the views.
enum Theme {
    // MARK: Colour — OKLCH tokens converted to sRGB. Dark is primary; light follows the system.
    static let bg = color(dark: 0x120f0c, light: 0xf8f6f4)
    static let surface = color(dark: 0x1a1713, light: 0xf2f0ec)
    static let surfaceRaised = color(dark: 0x24201b, light: 0xfefdfc)
    static let line = color(dark: 0x34302b, light: 0xdddad6)
    static let lineStrong = color(dark: 0x78746e, light: 0x847f7a)
    static let ink = color(dark: 0xf1eeea, light: 0x1e1a16)
    static let inkMuted = color(dark: 0xafaaa4, light: 0x5f5a54)
    static let brass = color(dark: 0xe6b463, light: 0x885716)
    static let brassSubtle = color(dark: 0x3a2b16, light: 0xf4e6ce)
    static let onBrass = color(dark: 0x1c140c, light: 0xfdfbf9)
    static let danger = color(dark: 0xf28058, light: 0xb63613)
    static let scrim = Color(red: 0x0a / 255, green: 0x08 / 255, blue: 0x06 / 255, opacity: 0xe0 / 255)
    static let viewerBackground = Color(red: 0x12 / 255, green: 0x0f / 255, blue: 0x0c / 255) // dark `bg`: media always on dark
    static let onScrim = Color(red: 0xf1 / 255, green: 0xee / 255, blue: 0xea / 255)

    // MARK: Type — Hanken Grotesk for UI, IBM Plex Mono for names, sizes, dates and counts.
    static let display = sans(34, .semibold)
    static let title = sans(22, .semibold)
    static let headline = sans(15, .semibold)
    static let body = sans(13)
    static let label = sans(13, .medium)
    static let caption = sans(11, .medium)
    static let meta = Font.custom("IBM Plex Mono", fixedSize: 11).monospacedDigit()

    // MARK: Space, shape, size
    static let space1: CGFloat = 4
    static let space2: CGFloat = 8
    static let space3: CGFloat = 12
    static let space4: CGFloat = 16
    static let space6: CGFloat = 24
    static let space8: CGFloat = 32
    static let space12: CGFloat = 48
    static let radiusSm: CGFloat = 4
    static let radiusMd: CGFloat = 8
    static let radiusLg: CGFloat = 12
    static let controlH: CGFloat = 28
    static let controlHLg: CGFloat = 40
    static let sidebarW: CGFloat = 220
    static let lockColumn: CGFloat = 320

    static let thumbRange: ClosedRange<Double> = 80...400
    static let thumbDefault: Double = 160  // tile-min
    static let thumbPixels: CGFloat = 640  // sharp up to ~320pt tiles on Retina; larger ones upscale slightly
    static let thumbMemory = 200 << 20     // NSCache cost limit in bytes

    // MARK: Motion — ease-out quart; locking itself is never animated.
    static let quick = Animation.timingCurve(0.25, 1, 0.5, 1, duration: 0.12)

    // MARK: Assets bundled in Contents/Resources

    static func registerFonts() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "woff2", subdirectory: "Fonts") ?? []
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
    }

    /// The design system's 24px line icons, as template images that take the surrounding colour.
    static func icon(_ name: String, size: CGFloat = 16) -> some View {
        Image(nsImage: icons[name] ?? load(name)).resizable().frame(width: size, height: size)
    }

    private static var icons: [String: NSImage] = [:]

    private static func load(_ name: String) -> NSImage {
        let image = Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: "Icons")
            .flatMap(NSImage.init(contentsOf:)) ?? NSImage()
        image.isTemplate = true
        icons[name] = image
        return image
    }

    private static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Hanken Grotesk", fixedSize: size).weight(weight)
    }

    private static func color(dark: Int, light: Int) -> Color {
        func ns(_ hex: Int) -> NSColor {
            NSColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255,
                    blue: CGFloat(hex & 0xff) / 255, alpha: 1)
        }
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? ns(dark) : ns(light)
        })
    }
}

/// `brass` fill for the single most important action on screen.
struct PrimaryButton: ButtonStyle {
    var large = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(large ? Theme.headline : Theme.label)
            .foregroundStyle(Theme.onBrass)
            .padding(.horizontal, large ? Theme.space4 : Theme.space3)
            .frame(maxWidth: large ? .infinity : nil, minHeight: large ? Theme.controlHLg : Theme.controlH)
            .background(Theme.brass.opacity(configuration.isPressed ? 0.85 : 1), in: RoundedRectangle(cornerRadius: Theme.radiusMd))
            .opacity(enabled ? 1 : 0.45)
            .contentShape(Rectangle())
    }
}
