import UIKit

enum VinylStyle: String, CaseIterable, Codable, Identifiable {
    case solid, twoTone, multicolor, classic, translucent
    var id: String { rawValue }
    var title: String {
        switch self {
        case .solid: return "Solid"
        case .twoTone: return "Two-tone"
        case .multicolor: return "Multicolor"
        case .classic: return "Classic black"
        case .translucent: return "Translucent"
        }
    }
}

enum BackgroundStyle: String, CaseIterable, Codable, Identifiable {
    case albumBlur, solidDark, adaptiveGradient
    var id: String { rawValue }
    var title: String {
        switch self {
        case .albumBlur: return "Album blur"
        case .solidDark: return "Solid dark"
        case .adaptiveGradient: return "Adaptive gradient"
        }
    }
}

enum VinylSize: String, CaseIterable, Codable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    /// Disc diameter as a fraction of the available content width.
    var widthFraction: CGFloat {
        switch self {
        case .small: return 0.68
        case .medium: return 0.78
        case .large: return 0.86
        }
    }
}

enum GrooveVisibility: String, CaseIterable, Codable, Identifiable {
    case subtle, normal, pronounced
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var count: Int {
        switch self {
        case .subtle: return 60
        case .normal: return 90
        case .pronounced: return 130
        }
    }
    var darkAlpha: Double {
        switch self {
        case .subtle: return 0.10
        case .normal: return 0.16
        case .pronounced: return 0.26
        }
    }
    var lightAlpha: Double {
        switch self {
        case .subtle: return 0.025
        case .normal: return 0.04
        case .pronounced: return 0.065
        }
    }
}

/// The concrete colors a renderer needs for one vinyl style.
struct VinylFinish: Equatable {
    var base: RGBColor
    var secondary: RGBColor
    var segments: [RGBColor]
    var accent: RGBColor

    static func make(style: VinylStyle, palette: AlbumPalette) -> VinylFinish {
        let segments = Array(palette.colors.prefix(5))
        switch style {
        case .solid, .twoTone, .multicolor, .translucent:
            return VinylFinish(base: palette.primary, secondary: palette.secondary, segments: segments, accent: palette.accent)
        case .classic:
            // Almost-black record that still carries a hint of the album in its edge lighting.
            return VinylFinish(base: RGBColor(0.045, 0.045, 0.05), secondary: palette.secondary, segments: segments, accent: palette.accent)
        }
    }
}

struct VinylSurface: Equatable {
    var style: VinylStyle
    var finish: VinylFinish
    var grooves: GrooveVisibility
    var reflections: Bool
}

struct VinylAppearance: Equatable {
    var style: VinylStyle
    var palette: AlbumPalette
    var grooves: GrooveVisibility
    var reflections: Bool

    var surface: VinylSurface {
        VinylSurface(style: style,
                     finish: VinylFinish.make(style: style, palette: palette),
                     grooves: grooves,
                     reflections: reflections)
    }
}

/// Album art for the center label. Equality is by key so crossfades only run on real changes.
struct ArtworkImage: Equatable {
    let key: String
    let image: UIImage?
    static let placeholder = ArtworkImage(key: "placeholder", image: nil)
    static func == (lhs: ArtworkImage, rhs: ArtworkImage) -> Bool { lhs.key == rhs.key }
}

/// Which animations are allowed, after merging user settings with iOS Reduce Motion.
struct MotionPolicy: Equatable {
    var reduceMotion: Bool
    var spinsRecord: Bool
    var animatesTonearm: Bool
    var animatesArtwork: Bool

    init(settings: AppSettings, systemReduceMotion: Bool) {
        let reduce = systemReduceMotion || settings.alwaysReduceMotion
        reduceMotion = reduce
        spinsRecord = settings.continuousRotation && !reduce
        animatesTonearm = settings.tonearmAnimation && !reduce
        animatesArtwork = settings.artworkTransitions && !reduce
    }
}
