import Foundation

/// Pure functions that turn color clusters into a vinyl palette. No UIKit, fully deterministic.
enum PaletteBuilder {

    // MARK: Entry points

    static func build(clusters: [ColorCluster], meanLightness: Double, colorfulFraction: Double) -> AlbumPalette {
        // A cover with almost no colorful pixels becomes black / silver / gray / white vinyl.
        if colorfulFraction < 0.10 || clusters.isEmpty {
            return monochrome(meanLightness: meanLightness)
        }

        let ranked = clusters.sorted { a, b in
            let sa = score(a), sb = score(b)
            if sa != sb { return sa > sb }
            if a.weight != b.weight { return a.weight > b.weight }
            return a.color.hsl.h < b.color.hsl.h
        }

        var picks: [RGBColor] = []
        for cluster in ranked {
            let tuned = vinylTone(cluster.color)
            if picks.allSatisfy({ RGBColor.distance($0, tuned) > 0.16 }) {
                picks.append(tuned)
            }
            if picks.count == 6 { break }
        }
        guard let primary = picks.first else {
            return monochrome(meanLightness: meanLightness)
        }
        while picks.count < 4 {
            picks.append(derivedVariant(of: primary, index: picks.count))
        }
        let secondary = chooseSecondary(primary: primary, candidates: Array(picks.dropFirst()))
        return assemble(colors: picks, secondary: secondary, isMonochrome: false, meanLightness: meanLightness)
    }

    static func monochrome(meanLightness m: Double) -> AlbumPalette {
        let tones: [Double]
        if m < 0.30 {
            tones = [0.06, 0.13, 0.24, 0.42]          // black / graphite
        } else if m > 0.68 {
            tones = [0.86, 0.74, 0.62, 0.48]          // white / silver
        } else {
            tones = [0.52, 0.40, 0.66, 0.28]          // gray / silver
        }
        let colors = tones.map { RGBColor(hue: 0, saturation: 0, lightness: $0) }
        return assemble(colors: colors, secondary: colors[1], isMonochrome: true, meanLightness: m)
    }

    static func fromBase(_ base: RGBColor) -> AlbumPalette {
        let primary = vinylTone(base)
        var picks = [primary]
        while picks.count < 4 { picks.append(derivedVariant(of: primary, index: picks.count)) }
        let secondary = derivedVariant(of: primary, index: 1)
        return assemble(colors: picks, secondary: secondary, isMonochrome: false, meanLightness: primary.hsl.l)
    }

    // MARK: Ranking

    /// Prominence x saturation x suitability for a dark vinyl surface.
    static func score(_ cluster: ColorCluster) -> Double {
        let hsl = cluster.color.hsl
        let prominence = pow(max(cluster.weight, 0), 0.65)
        let saturationTerm = 0.35 + 0.65 * min(1, hsl.s * 1.4)
        let lightnessTerm: Double
        if hsl.l < 0.10 || hsl.l > 0.90 {
            lightnessTerm = 0.35
        } else {
            lightnessTerm = max(0.5, 1 - abs(hsl.l - 0.42) * 1.1)
        }
        return prominence * saturationTerm * lightnessTerm
    }

    /// Keeps the cover's identity but makes the color work as a vinyl surface.
    static func vinylTone(_ c: RGBColor) -> RGBColor {
        let hsl = c.hsl
        let lightness = min(max(hsl.l, 0.14), 0.62)
        var saturation = hsl.s
        if saturation >= 0.2 { saturation = min(1, max(saturation, 0.40)) }
        return c.with(saturation: saturation, lightness: lightness)
    }

    static func derivedVariant(of base: RGBColor, index: Int) -> RGBColor {
        let hsl = base.hsl
        switch index {
        case 1: return base.with(hue: hsl.h + 0.08, lightness: min(0.62, hsl.l + 0.10))
        case 2: return base.with(lightness: max(0.14, hsl.l * 0.60))
        case 3: return base.with(lightness: min(0.62, hsl.l + 0.18))
        case 4: return base.with(hue: hsl.h + 0.05)
        default: return base.with(hue: hsl.h - 0.05)
        }
    }

    private static func chooseSecondary(primary: RGBColor, candidates: [RGBColor]) -> RGBColor {
        // Prefer a clearly different, chromatic color from the cover itself.
        if let c = candidates.first(where: { RGBColor.distance(primary, $0) > 0.35 && $0.hsl.s >= 0.2 }) { return c }
        if let c = candidates.first(where: { RGBColor.distance(primary, $0) > 0.35 }) { return c }
        return derivedVariant(of: primary, index: 1)
    }

    // MARK: Assembly

    static func assemble(colors: [RGBColor], secondary: RGBColor, isMonochrome: Bool, meanLightness: Double) -> AlbumPalette {
        let primary = colors[0]
        let hsl = primary.hsl
        let tint = isMonochrome ? 0.0 : min(hsl.s, 0.45)
        let top = RGBColor(hue: hsl.h, saturation: tint, lightness: 0.11)
        let bottom = RGBColor(hue: hsl.h, saturation: tint * 0.8, lightness: 0.045)
        return AlbumPalette(colors: colors,
                            primary: primary,
                            secondary: secondary,
                            accent: readableAccent(for: primary, on: bottom),
                            backgroundTop: top,
                            backgroundBottom: bottom,
                            isMonochrome: isMonochrome,
                            meanLightness: meanLightness)
    }

    static func readableAccent(for primary: RGBColor, on background: RGBColor) -> RGBColor {
        let hsl = primary.hsl
        var color: RGBColor
        if hsl.s < 0.08 {
            color = RGBColor(hue: 0, saturation: 0, lightness: 0.85)
        } else {
            color = primary.with(saturation: max(hsl.s, 0.45), lightness: max(hsl.l, 0.62))
        }
        var l = color.hsl.l
        while RGBColor.contrastRatio(color, background) < 4.5 && l < 0.97 {
            l += 0.04
            color = color.with(lightness: l)
        }
        return color
    }
}
