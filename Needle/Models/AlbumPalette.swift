import Foundation

/// Everything the UI needs to know about an album cover's colors.
struct AlbumPalette: Codable, Equatable {
    /// Bump when the extraction algorithm changes so stale cache entries are ignored.
    static let currentVersion = 3

    var version: Int = AlbumPalette.currentVersion
    /// Four to six vinyl-ready colors, best first.
    var colors: [RGBColor]
    var primary: RGBColor
    var secondary: RGBColor
    /// A readable accent for icons/controls (>= 4.5:1 on `backgroundBottom`).
    var accent: RGBColor
    /// Always dark so white text keeps >= 7:1 contrast, however bright the cover is.
    var backgroundTop: RGBColor
    var backgroundBottom: RGBColor
    var isMonochrome: Bool
    var meanLightness: Double

    /// Used when there is no artwork (nothing playing / artwork failed).
    static let neutral = PaletteBuilder.monochrome(meanLightness: 0.2)

    /// A palette built from one user-chosen color.
    static func manual(_ color: RGBColor) -> AlbumPalette {
        PaletteBuilder.fromBase(color)
    }
}

struct ColorCluster: Equatable {
    var color: RGBColor
    /// Fraction of the (weighted) image, 0...1.
    var weight: Double
}
