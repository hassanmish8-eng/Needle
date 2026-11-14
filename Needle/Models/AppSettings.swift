import Foundation

/// Every user preference. Decoding tolerates missing keys so new settings never wipe old ones.
struct AppSettings: Codable, Equatable {
    // Appearance
    var defaultStyle: VinylStyle = .solid
    var albumStyles: [String: VinylStyle] = [:]
    var backgroundStyle: BackgroundStyle = .albumBlur
    var backgroundBlur: Double = 0.7
    var vinylSize: VinylSize = .large
    var grooveVisibility: GrooveVisibility = .normal
    var showTonearm = true
    var surfaceReflections = true
    var autoExtractColors = true
    var manualColorEnabled = false
    var manualColor = RGBColor(0.78, 0.12, 0.18)
    // Animation
    var continuousRotation = true
    var tonearmAnimation = true
    var artworkTransitions = true
    var alwaysReduceMotion = false

    init() {}

    /// Per-album override if the user picked one, otherwise the default for new albums.
    func style(forAlbum key: String?) -> VinylStyle {
        if let key, let override = albumStyles[key] { return override }
        return defaultStyle
    }

    private enum CodingKeys: String, CodingKey {
        case defaultStyle, albumStyles, backgroundStyle, backgroundBlur, vinylSize, grooveVisibility
        case showTonearm, surfaceReflections, autoExtractColors, manualColorEnabled, manualColor
        case continuousRotation, tonearmAnimation, artworkTransitions, alwaysReduceMotion
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        defaultStyle = try c.decodeIfPresent(VinylStyle.self, forKey: .defaultStyle) ?? d.defaultStyle
        albumStyles = try c.decodeIfPresent([String: VinylStyle].self, forKey: .albumStyles) ?? d.albumStyles
        backgroundStyle = try c.decodeIfPresent(BackgroundStyle.self, forKey: .backgroundStyle) ?? d.backgroundStyle
        backgroundBlur = try c.decodeIfPresent(Double.self, forKey: .backgroundBlur) ?? d.backgroundBlur
        vinylSize = try c.decodeIfPresent(VinylSize.self, forKey: .vinylSize) ?? d.vinylSize
        grooveVisibility = try c.decodeIfPresent(GrooveVisibility.self, forKey: .grooveVisibility) ?? d.grooveVisibility
        showTonearm = try c.decodeIfPresent(Bool.self, forKey: .showTonearm) ?? d.showTonearm
        surfaceReflections = try c.decodeIfPresent(Bool.self, forKey: .surfaceReflections) ?? d.surfaceReflections
        autoExtractColors = try c.decodeIfPresent(Bool.self, forKey: .autoExtractColors) ?? d.autoExtractColors
        manualColorEnabled = try c.decodeIfPresent(Bool.self, forKey: .manualColorEnabled) ?? d.manualColorEnabled
        manualColor = try c.decodeIfPresent(RGBColor.self, forKey: .manualColor) ?? d.manualColor
        continuousRotation = try c.decodeIfPresent(Bool.self, forKey: .continuousRotation) ?? d.continuousRotation
        tonearmAnimation = try c.decodeIfPresent(Bool.self, forKey: .tonearmAnimation) ?? d.tonearmAnimation
        artworkTransitions = try c.decodeIfPresent(Bool.self, forKey: .artworkTransitions) ?? d.artworkTransitions
        alwaysReduceMotion = try c.decodeIfPresent(Bool.self, forKey: .alwaysReduceMotion) ?? d.alwaysReduceMotion
    }
}
