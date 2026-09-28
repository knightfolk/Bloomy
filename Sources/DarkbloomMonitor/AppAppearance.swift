import AppKit

enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    init(storedValue: String?) {
        self = storedValue.flatMap(Self.init(rawValue:)) ?? .system
    }

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var appKitAppearanceName: NSAppearance.Name? {
        switch self {
        case .system: nil
        case .light: .aqua
        case .dark: .darkAqua
        }
    }
}

@MainActor
enum ApplicationAppearance {
    static let defaultsKey = "appearanceMode"

    static func storedMode(in defaults: UserDefaults = .standard) -> AppAppearanceMode {
        AppAppearanceMode(storedValue: defaults.string(forKey: defaultsKey))
    }

    static func apply(
        _ mode: AppAppearanceMode,
        to application: NSApplication = .shared
    ) {
        application.appearance = mode.appKitAppearanceName.flatMap(NSAppearance.init(named:))
    }

    static func applyStored(
        from defaults: UserDefaults = .standard,
        to application: NSApplication = .shared
    ) {
        apply(storedMode(in: defaults), to: application)
    }
}
