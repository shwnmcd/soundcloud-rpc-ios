import SwiftUI

// MARK: - Appearance & Theme Modes

enum AppThemeMode: String, CaseIterable, Identifiable {
    case dark = "dark"
    case light = "light"
    case amoled = "amoled"
    case system = "system"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dark: return "Dark"
        case .light: return "Light"
        case .amoled: return "Midnight OLED"
        case .system: return "System"
        }
    }

    var icon: String {
        switch self {
        case .dark: return "moon.fill"
        case .light: return "sun.max.fill"
        case .amoled: return "sparkles"
        case .system: return "circle.lefthalf.filled"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .dark, .amoled: return .dark
        case .light: return .light
        case .system: return nil
        }
    }

    func resolvedIsDark(systemScheme: ColorScheme) -> Bool {
        switch self {
        case .dark, .amoled: return true
        case .light: return false
        case .system: return systemScheme == .dark
        }
    }
}

// MARK: - Accent Color Presets

enum AppAccentPreset: String, CaseIterable, Identifiable {
    case soundcloudOrange = "orange"
    case crimson = "crimson"
    case electricBlue = "blue"
    case emerald = "emerald"
    case violet = "violet"
    case warmGold = "gold"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .soundcloudOrange: return "SoundCloud"
        case .crimson: return "Crimson"
        case .electricBlue: return "Electric"
        case .emerald: return "Emerald"
        case .violet: return "Violet"
        case .warmGold: return "Gold"
        }
    }

    var color: Color {
        switch self {
        case .soundcloudOrange: return Color(red: 1.0, green: 0.333, blue: 0.0)
        case .crimson: return Color(red: 1.0, green: 0.215, blue: 0.372)
        case .electricBlue: return Color(red: 0.039, green: 0.517, blue: 1.0)
        case .emerald: return Color(red: 0.188, green: 0.82, blue: 0.345)
        case .violet: return Color(red: 0.686, green: 0.321, blue: 0.87)
        case .warmGold: return Color(red: 1.0, green: 0.70, blue: 0.0)
        }
    }

    var secondaryGradientColor: Color {
        switch self {
        case .soundcloudOrange: return Color(red: 1.0, green: 0.52, blue: 0.14)
        case .crimson: return Color(red: 1.0, green: 0.42, blue: 0.32)
        case .electricBlue: return Color(red: 0.28, green: 0.72, blue: 1.0)
        case .emerald: return Color(red: 0.12, green: 0.68, blue: 0.54)
        case .violet: return Color(red: 0.90, green: 0.40, blue: 0.85)
        case .warmGold: return Color(red: 1.0, green: 0.48, blue: 0.0)
        }
    }
}

// MARK: - Now Playing Visual Styles

enum PlaybackStyle: String, CaseIterable, Identifiable {
    case vinyl = "vinyl"
    case fullscreen = "fullscreen"
    case card = "card"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .vinyl: return "Vinyl Record"
        case .fullscreen: return "Full Artwork"
        case .card: return "Ambient Card"
        }
    }

    var shortName: String {
        switch self {
        case .vinyl: return "Vinyl"
        case .fullscreen: return "Full"
        case .card: return "Card"
        }
    }

    var icon: String {
        switch self {
        case .vinyl: return "record.circle"
        case .fullscreen: return "rectangle.portrait.fill"
        case .card: return "square.stack.fill"
        }
    }
}

// MARK: - Semantic Theme Palette

struct SCThemePalette: Equatable {
    let isDark: Bool
    let isAmoled: Bool
    let accent: Color
    let accentSecondary: Color

    var bg: Color {
        if !isDark { return Color(red: 0.965, green: 0.965, blue: 0.975) }
        return isAmoled ? Color.black : Color(red: 0.067, green: 0.067, blue: 0.067)
    }

    var surface: Color {
        if !isDark { return Color.white }
        return isAmoled ? Color(red: 0.07, green: 0.07, blue: 0.08) : Color(white: 0.125)
    }

    var surfaceElevated: Color {
        if !isDark { return Color(red: 0.925, green: 0.925, blue: 0.945) }
        return isAmoled ? Color(red: 0.12, green: 0.12, blue: 0.14) : Color(white: 0.16)
    }

    var sidebarBg: Color {
        if !isDark { return Color(red: 0.94, green: 0.94, blue: 0.96) }
        return isAmoled ? Color(red: 0.04, green: 0.04, blue: 0.05) : Color(red: 0.055, green: 0.055, blue: 0.06)
    }

    var tabBarBg: Color {
        if !isDark { return Color.white }
        return isAmoled ? Color.black : Color(red: 0.067, green: 0.067, blue: 0.067)
    }

    var pillFill: Color {
        isDark ? Color.white.opacity(0.09) : Color.black.opacity(0.06)
    }

    var pillStroke: Color {
        isDark ? Color.white.opacity(0.15) : Color.black.opacity(0.10)
    }

    var circleButtonFill: Color {
        isDark ? Color.white.opacity(0.11) : Color.black.opacity(0.075)
    }

    var textPrimary: Color {
        isDark ? Color.white : Color(red: 0.08, green: 0.08, blue: 0.10)
    }

    var textSecondary: Color {
        isDark ? Color(white: 0.64) : Color(white: 0.40)
    }

    var textTertiary: Color {
        isDark ? Color(white: 0.50) : Color(white: 0.52)
    }

    var divider: Color {
        isDark ? Color.white.opacity(0.14) : Color.black.opacity(0.09)
    }

    var artworkPlaceholder: Color {
        isDark ? Color(white: 0.14) : Color(white: 0.88)
    }

    var playCircleBg: Color {
        isDark ? Color.white : Color(red: 0.09, green: 0.09, blue: 0.11)
    }

    var playCircleFg: Color {
        isDark ? Color.black : Color.white
    }

    var miniPlayerBg: Color {
        isDark
            ? Color(red: 0.14, green: 0.14, blue: 0.16).opacity(0.80)
            : Color.white.opacity(0.88)
    }

    var miniPlayerBorder: Color {
        isDark ? Color.white.opacity(0.14) : Color.black.opacity(0.10)
    }

    var miniPlayerShadow: Color {
        isDark ? Color.black.opacity(0.45) : Color.black.opacity(0.14)
    }

    var likesHeroGradient: [Color] {
        if isDark {
            return [accent.opacity(0.48), Color(red: 0.15, green: 0.10, blue: 0.09)]
        } else {
            return [accent, accentSecondary]
        }
    }

    var likesPageTopGradient: [Color] {
        if isDark {
            return [accent.opacity(0.35), bg]
        } else {
            return [accent.opacity(0.16), bg]
        }
    }

    var fallbackBannerGradient: [Color] {
        if isDark {
            return [accent.opacity(0.35), bg]
        } else {
            return [accent.opacity(0.24), bg]
        }
    }

    var tabSelectedColor: Color {
        isDark ? .white : accent
    }

    var tabUnselectedColor: Color {
        isDark ? Color.white.opacity(0.48) : Color.black.opacity(0.42)
    }

    static func resolve(mode: AppThemeMode, systemScheme: ColorScheme, accent: AppAccentPreset) -> SCThemePalette {
        let isDark = mode.resolvedIsDark(systemScheme: systemScheme)
        return SCThemePalette(
            isDark: isDark,
            isAmoled: mode == .amoled,
            accent: accent.color,
            accentSecondary: accent.secondaryGradientColor
        )
    }
}

private struct SCThemePaletteKey: EnvironmentKey {
    static let defaultValue: SCThemePalette = .resolve(mode: .dark, systemScheme: .dark, accent: .soundcloudOrange)
}

extension EnvironmentValues {
    var scTheme: SCThemePalette {
        get { self[SCThemePaletteKey.self] }
        set { self[SCThemePaletteKey.self] = newValue }
    }
}
