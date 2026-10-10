import SwiftUI

extension Color {
    static let flowAccent = adaptive(0x0F766E, 0x5ED3BE)
    static let flowCanvas = adaptive(0xF7F5F1, 0x141816)
    static let flowSurface = adaptive(0xFFFFFF, 0x1C211F)
    static let flowRaised = adaptive(0xFBFAF7, 0x242A27)
    static let flowSeparator = adaptive(0xE4E0D8, 0x323936)
    static let flowText = adaptive(0x1E2422, 0xECEFEC)
    static let flowSecondary = adaptive(0x5B6460, 0xA7B0AC)
    static let flowSoft = adaptive(0xDCEFE8, 0x16332D)
    static let flowAccentText = adaptive(0x0B5F58, 0x7FE0CE)
    static let flowWarning = adaptive(0x8F5600, 0xE7B04A)
    static let flowDanger = adaptive(0xB42318, 0xFF7B6E)

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((value >> 16) & 255) / 255,
                           green: Double((value >> 8) & 255) / 255,
                           blue: Double(value & 255) / 255, alpha: 1)
        })
    }
}
