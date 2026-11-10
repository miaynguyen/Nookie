import SwiftUI

enum CrowdPalette {
    static func color(_ level: Int) -> Color {
        switch level {
        case 1: Color(hex: 0xE9F0DB)
        case 2: Color(hex: 0xCEDFBB)
        case 3: Color(hex: 0xA7C594)
        case 4: Color(hex: 0x71986A)
        default: Color(hex: 0x365C42)
        }
    }
}

enum OutletLevel {
    static func label(_ value: Int) -> String {
        switch value { case 1: "Few"; case 2: "Moderate"; default: "Many" }
    }
}
