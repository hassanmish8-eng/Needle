import SwiftUI

/// Layout constants shared by every turntable layer so they always stay concentric and proportional.
/// Ratios named *radius* are relative to the disc radius R; everything scales with the disc.
enum TurntableMetrics {
    static let plinthRatio: CGFloat = 1.14      // plinth side / disc diameter
    static let platterRatio: CGFloat = 1.045    // platter diameter / disc diameter
    static let labelRatio: CGFloat = 0.32       // label radius / disc radius
    static let holeRatio: CGFloat = 0.040       // spindle-hole radius / disc radius
    static let spindleRatio: CGFloat = 0.030    // spindle radius / disc radius
    /// Tonearm pivot, in disc radii from the disc center (screen coordinates, y down).
    static let pivot = CGPoint(x: 0.93, y: -0.93)
    static let armLength: CGFloat = 1.05        // pivot-to-stylus, in disc radii
    /// Arm direction in degrees, measured clockwise from +x. With the pivot above and the
    /// arm length above, 92 puts the stylus at ~0.90 R and 111.3 at ~0.55 R: the arm sweeps
    /// inward as the track progresses and never reaches the label (0.32 R).
    static let restAngle: Double = 82
    static let startAngle: Double = 92
    static let endAngle: Double = 111.3
}

/// Draws the record body: finish, grooves, sheen and rim. One Canvas, one flat layer,
/// so it can be rasterized once and rotated as a single composited texture.
enum VinylPainter {

    static func paint(_ ctx: inout GraphicsContext, size: CGSize, surface: VinylSurface) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) / 2
        guard radius > 1 else { return }
        let disc = circle(center, radius)

        ctx.drawLayer { layer in
            layer.clip(to: disc)
            fillBody(&layer, surface: surface, center: center, radius: radius, disc: disc)
            drawGrooves(&layer, surface: surface, center: center, radius: radius)
            if surface.reflections {
                drawSheen(&layer, style: surface.style, center: center, radius: radius)
            }
            drawRim(&layer, center: center, radius: radius)
        }
    }

    // MARK: Geometry helpers

    private static func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }

    private static func ringRect(_ c: CGPoint, _ r: CGFloat) -> CGRect {
        CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
    }

    private static func radial(_ colors: [RGBColor], center: CGPoint, radius: CGFloat, alpha: Double = 1) -> GraphicsContext.Shading {
        .radialGradient(Gradient(colors: colors.map { $0.color.opacity(alpha) }),
                        center: center, startRadius: 0, endRadius: radius)
    }

    private static func shaded(_ base: RGBColor) -> [RGBColor] {
        [base.lightened(0.10), base, base.darkened(0.32)]
    }

    // MARK: Body (one branch per vinyl style)

    private static func fillBody(_ g: inout GraphicsContext, surface: VinylSurface, center: CGPoint, radius R: CGFloat, disc: Path) {
        let f = surface.finish
        switch surface.style {
        case .solid:
            g.fill(disc, with: radial(shaded(f.base), center: center, radius: R))

        case .twoTone:
            g.fill(disc, with: radial(shaded(f.base), center: center, radius: R))
            // A clean split that follows the circular silhouette, slightly off-center.
            var half = Path(CGRect(x: -2 * R, y: R * 0.07, width: 4 * R, height: 4 * R))
            half = half.applying(CGAffineTransform(rotationAngle: CGFloat(Angle.degrees(-32).radians)))
            half = half.applying(CGAffineTransform(translationX: center.x, y: center.y))
            g.drawLayer { sub in
                sub.clip(to: half)
                sub.fill(disc, with: radial(shaded(f.secondary), center: center, radius: R))
            }

        case .multicolor:
            let segs = f.segments.count >= 3 ? f.segments : [f.base, f.secondary, f.base.darkened(0.3)]
            let n = segs.count
            var stops: [Gradient.Stop] = []
            for i in 0...n {
                stops.append(Gradient.Stop(color: segs[i % n].color, location: CGFloat(i) / CGFloat(n)))
            }
            g.fill(disc, with: .conicGradient(Gradient(stops: stops), center: center, angle: .degrees(-70)))
            // Restrained marbling: three soft blobs from the cover's own colors.
            g.drawLayer { m in
                m.addFilter(.blur(radius: R * 0.12))
                for k in 0..<3 {
                    let a = Double(k) * 2.3 + 0.6
                    let rr = R * (0.30 + 0.18 * CGFloat(k))
                    let c = CGPoint(x: center.x + CGFloat(cos(a)) * rr, y: center.y + CGFloat(sin(a)) * rr)
                    let blob = Path(ellipseIn: CGRect(x: c.x - R * 0.28, y: c.y - R * 0.18, width: R * 0.56, height: R * 0.36))
                    m.fill(blob, with: .color(segs[(k + 1) % n].color.opacity(0.35)))
                }
            }
            let vignette = Gradient(stops: [
                Gradient.Stop(color: Color.black.opacity(0), location: 0),
                Gradient.Stop(color: Color.black.opacity(0), location: 0.55),
                Gradient.Stop(color: Color.black.opacity(0.28), location: 1)
            ])
            g.fill(disc, with: .radialGradient(vignette, center: center, startRadius: 0, endRadius: R))

        case .classic:
            let inks = [RGBColor(0.15, 0.15, 0.16), RGBColor(0.06, 0.06, 0.065), RGBColor(0.03, 0.03, 0.035)]
            g.fill(disc, with: radial(inks, center: center, radius: R))
            // A hint of the album stays in the lighting.
            let tint = Gradient(colors: [f.accent.color.opacity(0.10), Color.clear])
            g.fill(disc, with: .radialGradient(tint,
                                               center: CGPoint(x: center.x + R * 0.25, y: center.y + R * 0.35),
                                               startRadius: 0, endRadius: R * 0.9))

        case .translucent:
            let colors = [f.base.darkened(0.20), f.base, f.base.lightened(0.22)]
            g.fill(disc, with: radial(colors, center: center, radius: R, alpha: 0.88))
            g.drawLayer { sub in
                sub.addFilter(.blur(radius: R * 0.05))
                let glow = circle(center, R * 0.93)
                sub.stroke(glow, with: .color(f.base.lightened(0.35).color.opacity(0.35)), lineWidth: R * 0.05)
            }
        }
    }

    // MARK: Grooves

    private static func luminance(of surface: VinylSurface) -> Double {
        switch surface.style {
        case .classic:
            return 0.02
        case .multicolor:
            let s = surface.finish.segments
            return s.isEmpty ? surface.finish.base.luminance : s.map { $0.luminance }.reduce(0, +) / Double(s.count)
        default:
            return surface.finish.base.luminance
        }
    }

    /// Track-gap bands (smooth rings between "songs"), as (radius fraction, half-width fraction).
    private static let gaps: [(CGFloat, CGFloat)] = [(0.47, 0.007), (0.60, 0.010), (0.73, 0.008), (0.85, 0.011)]

    private static func drawGrooves(_ g: inout GraphicsContext, surface: VinylSurface, center: CGPoint, radius R: CGFloat) {
        let outer = R * 0.955
        let inner = R * (TurntableMetrics.labelRatio + 0.07)
        let count = surface.grooves.count
        let lum = luminance(of: surface)
        // Visible on bright colors, subtle on dark ones.
        let darkScale = 0.8 + 0.7 * lum
        let lightScale = 1.3 - 0.7 * lum

        var dark = [Path](repeating: Path(), count: 4)
        var light = [Path](repeating: Path(), count: 3)
        for i in 0..<count {
            let t = CGFloat(i) / CGFloat(max(count - 1, 1))
            let r = inner + (outer - inner) * t
            var inGap = false
            for (c, h) in gaps where abs(r - R * c) < R * h { inGap = true }
            if inGap { continue }
            dark[min(3, Int(Noise.value(i) * 4))].addEllipse(in: ringRect(center, r))
            if i % 2 == 0 {
                light[min(2, Int(Noise.value(i + 977) * 3))].addEllipse(in: ringRect(center, r + 0.6))
            }
        }

        let lineWidth = max(0.35, R * 0.0012)
        for (k, path) in dark.enumerated() {
            let alpha = min(0.5, surface.grooves.darkAlpha * darkScale * (0.55 + 0.30 * Double(k)))
            g.stroke(path, with: .color(Color.black.opacity(alpha)), lineWidth: lineWidth)
        }
        for (k, path) in light.enumerated() {
            let alpha = min(0.2, surface.grooves.lightAlpha * lightScale * (0.6 + 0.4 * Double(k)))
            g.stroke(path, with: .color(Color.white.opacity(alpha)), lineWidth: lineWidth)
        }
        for (c, h) in gaps {
            g.stroke(circle(center, R * c), with: .color(Color.white.opacity(0.05)), lineWidth: R * h * 2)
        }
    }

    // MARK: Reflections

    private static func drawSheen(_ g: inout GraphicsContext, style: VinylStyle, center: CGPoint, radius R: CGFloat) {
        var annulus = circle(center, R * 0.965)
        annulus.addPath(circle(center, R * (TurntableMetrics.labelRatio + 0.02)))
        let k: Double = style == .classic ? 1.15 : 1.0

        func stop(_ alpha: Double, _ location: CGFloat) -> Gradient.Stop {
            Gradient.Stop(color: Color.white.opacity(alpha * k), location: location)
        }
        // Two main lobes with irregular sub-lobes: deliberately asymmetric, like real lacquer.
        let sheen = Gradient(stops: [
            stop(0, 0.00), stop(0, 0.04), stop(0.16, 0.09), stop(0.05, 0.115), stop(0.12, 0.14), stop(0, 0.19),
            stop(0, 0.35), stop(0.07, 0.375), stop(0, 0.40),
            stop(0, 0.54), stop(0.20, 0.60), stop(0.08, 0.625), stop(0.15, 0.66), stop(0, 0.72),
            stop(0, 1.00)
        ])
        g.drawLayer { s in
            s.clip(to: annulus, style: FillStyle(eoFill: true))
            s.blendMode = .plusLighter
            s.fill(circle(center, R), with: .conicGradient(sheen, center: center, angle: .degrees(-25)))
            let spec = Gradient(colors: [Color.white.opacity(0.10 * k), Color.clear])
            s.fill(circle(center, R), with: .radialGradient(spec,
                                                            center: CGPoint(x: center.x - R * 0.28, y: center.y - R * 0.34),
                                                            startRadius: 0, endRadius: R * 0.7))
        }
    }

    // MARK: Rim

    private static func drawRim(_ g: inout GraphicsContext, center: CGPoint, radius R: CGFloat) {
        let width = R * 0.035
        let rim = circle(center, R - width / 2)
        g.stroke(rim,
                 with: .linearGradient(Gradient(colors: [Color.white.opacity(0.16), Color.black.opacity(0.18)]),
                                       startPoint: CGPoint(x: center.x - R, y: center.y - R),
                                       endPoint: CGPoint(x: center.x + R, y: center.y + R)),
                 lineWidth: width)
        g.stroke(circle(center, R - 0.5), with: .color(Color.black.opacity(0.5)), lineWidth: 1)

        // Thin highlight along part of the circumference.
        let edge = Gradient(stops: [
            Gradient.Stop(color: Color.white.opacity(0), location: 0.00),
            Gradient.Stop(color: Color.white.opacity(0), location: 0.10),
            Gradient.Stop(color: Color.white.opacity(0.55), location: 0.14),
            Gradient.Stop(color: Color.white.opacity(0), location: 0.18),
            Gradient.Stop(color: Color.white.opacity(0), location: 0.50),
            Gradient.Stop(color: Color.white.opacity(0.22), location: 0.55),
            Gradient.Stop(color: Color.white.opacity(0), location: 0.60),
            Gradient.Stop(color: Color.white.opacity(0), location: 1.00)
        ])
        g.stroke(circle(center, R * 0.992),
                 with: .conicGradient(edge, center: center, angle: .degrees(-60)),
                 lineWidth: R * 0.012)
    }
}
