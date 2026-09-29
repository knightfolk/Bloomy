import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable {
    case appearance = "Appearance"
    case menuBar = "Menu Bar"
    case electricity = "Electricity"
    case updates = "Updates"
    case provider = "Provider"
    case fans = "Fans"
    case companion = "iPhone Companion"
    case support = "Support"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .appearance: "paintpalette"
        case .menuBar: "menubar.rectangle"
        case .electricity: "bolt"
        case .updates: "arrow.down.circle"
        case .provider: "cpu"
        case .fans: "fan"
        case .companion: "iphone"
        case .support: "questionmark.circle"
        }
    }
}
