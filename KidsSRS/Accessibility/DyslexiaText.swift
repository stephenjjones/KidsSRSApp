import SwiftUI
import CoreText
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Bundled OpenDyslexic font (Spec §11). The `.otf` files ship in the app
/// (`KidsSRS/Resources/Fonts`, SIL OFL — see `OFL.txt`) and are registered at
/// launch via Core Text, so registration works identically on iOS and macOS
/// without per-platform Info.plist keys.
enum DyslexiaFontProvider {
    /// The registered family name (verified from the font's name table).
    static let familyName = "OpenDyslexic"

    private static var didRegister = false

    /// Register the bundled OpenDyslexic fonts. Idempotent — safe to call from
    /// app launch and from tests.
    static func registerBundledFonts() {
        guard !didRegister else { return }
        didRegister = true
        let urls = Bundle.main.urls(forResourcesWithExtension: "otf", subdirectory: nil) ?? []
        for url in urls where url.lastPathComponent.localizedCaseInsensitiveContains("dyslexic") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    /// Whether the OpenDyslexic family is registered and usable.
    static var isAvailable: Bool {
        #if canImport(UIKit)
        return !UIFont.fontNames(forFamilyName: familyName).isEmpty
        #elseif canImport(AppKit)
        return NSFontManager.shared.availableFontFamilies.contains(familyName)
        #else
        return false
        #endif
    }
}

/// Dyslexia-friendly text styling (Spec §11), shared across child-facing
/// surfaces (study flow, Game Mode). When the child has dyslexia mode on it uses
/// the bundled **OpenDyslexic** face (scaled with Dynamic Type via `relativeTo:`)
/// with generous letter/line spacing; off, it's the normal system style.
///
/// Apply with `.dyslexiaText(_:enabled:)`, passing the text style instead of a
/// separate `.font(...)` so the modifier owns the font for both states.
struct DyslexiaFriendly: ViewModifier {
    let style: Font.TextStyle
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content
                .font(dyslexiaFont)
                .tracking(0.5)
                .lineSpacing(8)
        } else {
            content.font(.system(style))
        }
    }

    private var dyslexiaFont: Font {
        if DyslexiaFontProvider.isAvailable {
            return .custom(DyslexiaFontProvider.familyName,
                           size: Self.baseSize(for: style),
                           relativeTo: style)
        }
        // Fallback if the asset is ever missing: rounded system + the spacing.
        return .system(style, design: .rounded)
    }

    /// Default point sizes per text style; `relativeTo:` scales them for Dynamic Type.
    static func baseSize(for style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle:  return 34
        case .title:       return 28
        case .title2:      return 22
        case .title3:      return 20
        case .headline, .body: return 17
        case .callout:     return 16
        case .subheadline: return 15
        case .footnote:    return 13
        case .caption:     return 12
        case .caption2:    return 11
        @unknown default:  return 17
        }
    }
}

extension View {
    /// Render this text at `style`, switching to dyslexia-friendly styling when
    /// `enabled` (Spec §11). Add `.fontWeight(.bold)` after for bold.
    func dyslexiaText(_ style: Font.TextStyle, enabled: Bool) -> some View {
        modifier(DyslexiaFriendly(style: style, enabled: enabled))
    }
}
