import SwiftUI

enum Theme {
    static let accent = Color(hex: 0x3D7BF7)
    static let accentDeep = Color(hex: 0x2A44D2)
    static let lavender = Color(hex: 0xA9B8FF)
    static let orange = Color(hex: 0xFF9F0A)
    static let green = Color(hex: 0x32D583)
    static let red = Color(hex: 0xFF5A5F)
    static let purple = Color(hex: 0x7B61FF)

    static let text = Color.white
    static let secondary = Color.white.opacity(0.62)
    static let tertiary = Color.white.opacity(0.38)
    static let card = Color.white.opacity(0.045)
    static let cardHover = Color.white.opacity(0.08)
    static let stroke = Color.white.opacity(0.08)

    static let sidebar = Color(hex: 0x070B1C)
    static let background = LinearGradient(
        colors: [Color(hex: 0x14204F), Color(hex: 0x0B1131), Color(hex: 0x070A19)],
        startPoint: .topTrailing, endPoint: .bottomLeading
    )
    static let ringColors = [Color(hex: 0x2A44D2), Color(hex: 0x3D7BF7), Color(hex: 0x7FB0FF)]

    /// Blue while there's room, warming up as the disk fills.
    static func diskColors(_ used: Double) -> [Color] {
        if used > 0.9 { return [Color(hex: 0xFF9F0A), Color(hex: 0xFF6B3D), Color(hex: 0xFF5A5F)] }
        if used > 0.75 { return [Color(hex: 0x3D7BF7), Color(hex: 0x9B7BFF), Color(hex: 0xFF9F0A)] }
        return ringColors
    }

    static let ring = AngularGradient(
        colors: [Color(hex: 0x2A44D2), Color(hex: 0x3D7BF7), Color(hex: 0x7FB0FF), Color(hex: 0x3D7BF7)],
        center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)
    )
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}
