import SwiftUI
import ClashClientUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

 
 
enum ClashTheme {
    static var canvas: Color { canvas(pureBlack: AppPreferences.pureBlack()) }

    static func canvas(pureBlack: Bool) -> Color {
#if os(macOS)
         
         
         
         
        _ = pureBlack
        return Color(
            nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? .black
                    : .windowBackgroundColor
            }
        )
#else
        return pureBlack ? pureBlackCanvas : groupedCanvas
#endif
    }
#if !os(macOS)
     
     
     
     
     
    private static let groupedCanvas = Color(uiColor: .systemGroupedBackground)
    private static let pureBlackCanvas = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .black : .systemGroupedBackground
    })
#endif
#if os(macOS)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let raisedFill = Color(
        nsColor: .unemphasizedSelectedContentBackgroundColor
    )
    static let separator = Color(nsColor: .separatorColor)
     
     
     
     
    static let card = Color(
        nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(
                    red: 0x2E / 255,
                    green: 0x2E / 255,
                    blue: 0x2E / 255,
                    alpha: 1
                )
            }
            return NSColor.alternatingContentBackgroundColors[1]
        }
    )
#else
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let raisedFill = Color(uiColor: .tertiarySystemFill)
    static let separator = Color(uiColor: .separator)
#endif

     
     
     
     
    enum Spacing {
        static let tight = ClashClientUI.ClashTheme.Spacing.tight
        static let compact = ClashClientUI.ClashTheme.Spacing.compact
        static let row = ClashClientUI.ClashTheme.Spacing.row
        static let standard = ClashClientUI.ClashTheme.Spacing.standard
        static let section = ClashClientUI.ClashTheme.Spacing.section
    }

     
     
     
    enum Typography {
        static func rowSubtitle(_ locale: Locale) -> Font {
            ClashClientUI.ClashTheme.Typography.rowSubtitle(locale)
        }

        static func rowSubtitleGap(_ locale: Locale) -> CGFloat {
            ClashClientUI.ClashTheme.Typography.rowSubtitleGap(locale)
        }
    }

    enum Radius {
        static let control = ClashClientUI.ClashTheme.Radius.control
        static let icon = ClashClientUI.ClashTheme.Radius.icon
        static let card = ClashClientUI.ClashTheme.Radius.card
         
         
        static let groupedSection = ClashClientUI.ClashTheme.Radius.groupedSection
        static let liquidGlassCard = ClashClientUI.ClashTheme.Radius.liquidGlassCard
    }

    enum Layout {
         
         
        static let primaryPageGlassBleed = ClashClientUI.ClashTheme.Layout.primaryPageGlassBleed
    }
}

extension ClashClientUI.ClashProductPalette {
     
     
     
     
     
     
     
     
     
    static var clashProduct: ClashClientUI.ClashProductPalette {
#if os(macOS)
        ClashClientUI.ClashProductPalette(
            canvas: ClashTheme.canvas,
            surface: ClashTheme.surface,
            raisedFill: ClashTheme.raisedFill,
            separator: ClashTheme.separator,
            card: ClashTheme.card
        )
#else
        ClashClientUI.ClashProductPalette(
            canvas: ClashTheme.canvas,
            surface: ClashTheme.surface,
            raisedFill: ClashTheme.raisedFill,
            separator: ClashTheme.separator
        )
#endif
    }
}
