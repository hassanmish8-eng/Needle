import SwiftUI
import UIKit

/// Plain sRGB color value. Codable + Equatable so palettes can be cached and compared.
struct RGBColor: Codable, Equatable, Hashable {
    var r: Double
    var g: Double
    var b: Double

    static let white = RGBColor(1, 1, 1)
    static let black = RGBColor(0, 0, 0)

    init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = min(max(r, 0), 1)
        self.g = min(max(g, 0), 1)
        self.b = min(max(b, 0), 1)
    }

    init(hue: Double, saturation: Double, lightness: Double) {
        let h = hue - floor(hue)
        let s = min(max(saturation, 0), 1)
        let l = min(max(lightness, 0), 1)
        if s == 0 {
            self.init(l, l, l)
            return
        }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        self.init(RGBColor.channel(p, q, h + 1.0 / 3.0),
                  RGBColor.channel(p, q, h),
                  RGBColor.channel(p, q, h - 1.0 / 3.0))
    }

    init(_ color: Color) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        self.init(Double(red), Double(green), Double(blue))
    }

    private static func channel(_ p: Double, _ q: Double, _ tIn: Double) -> Double {
        var t = tIn
        if t < 0 { t += 1 }
        if t > 1 { t -= 1 }
        if t < 1.0 / 6.0 { return p + (q - p) * 6 * t }
        if t < 0.5 { return q }
        if t < 2.0 / 3.0 { return p + (q - p) * (2.0 / 3.0 - t) * 6 }
        return p
    }

    // MARK: Conversions

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: 1) }
    var uiColor: UIColor { UIColor(red: r, green: g, blue: b, alpha: 1) }

    /// Hue 0...1, saturation 0...1, lightness 0...1.
    var hsl: (h: Double, s: Double, l: Double) {
        let mx = max(r, g, b)
        let mn = min(r, g, b)
        let l = (mx + mn) / 2
        let d = mx - mn
        guard d > 1e-9 else { return (0, 0, l) }
        let s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
        var h: Double
        if mx == r {
            h = (g - b) / d + (g < b ? 6 : 0)
        } else if mx == g {
            h = (b - r) / d + 2
        } else {
            h = (r - g) / d + 4
        }
        h /= 6
        return (h, s, l)
    }

    /// WCAG relative luminance.
    var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    // MARK: Adjustments

    func with(hue: Double? = nil, saturation: Double? = nil, lightness: Double? = nil) -> RGBColor {
        let c = hsl
        return RGBColor(hue: hue ?? c.h, saturation: saturation ?? c.s, lightness: lightness ?? c.l)
    }

    func mixed(with other: RGBColor, _ amount: Double) -> RGBColor {
        let t = min(max(amount, 0), 1)
        return RGBColor(r + (other.r - r) * t, g + (other.g - g) * t, b + (other.b - b) * t)
    }

    func lightened(_ amount: Double) -> RGBColor { mixed(with: .white, amount) }
    func darkened(_ amount: Double) -> RGBColor { mixed(with: .black, amount) }

    // MARK: Metrics

    static func contrastRatio(_ a: RGBColor, _ b: RGBColor) -> Double {
        let l1 = max(a.luminance, b.luminance)
        let l2 = min(a.luminance, b.luminance)
        return (l1 + 0.05) / (l2 + 0.05)
    }

    /// Perceptual-ish ("redmean") distance, roughly 0...3.
    static func distance(_ a: RGBColor, _ b: RGBColor) -> Double {
        let rm = (a.r + b.r) / 2
        let dr = a.r - b.r, dg = a.g - b.g, db = a.b - b.b
        return ((2 + rm) * dr * dr + 4 * dg * dg + (3 - rm) * db * db).squareRoot()
    }

    /// Circular hue distance, 0...0.5.
    static func hueDistance(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b)
        return min(d, 1 - d)
    }
}
