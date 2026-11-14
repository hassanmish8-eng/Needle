import SwiftUI

/// The tonearm, drawn in its own local space with the pivot at the view's center and the
/// arm pointing along +x, then rotated about the pivot. It never rotates with the record.
struct TonearmView: View {
    /// Disc radius R; every dimension is a fraction of it.
    let radius: CGFloat
    /// Arm direction in degrees (clockwise from +x).
    let angle: Double
    let lifted: Bool

    var body: some View {
        Canvas { context, size in
            draw(&context, size: size)
        }
        .frame(width: radius * 3, height: radius * 3)
        .rotationEffect(.degrees(angle))
        .scaleEffect(lifted ? 1.035 : 1)
        .shadow(color: Color.black.opacity(0.55),
                radius: lifted ? radius * 0.05 : radius * 0.022,
                x: lifted ? radius * 0.04 : radius * 0.015,
                y: lifted ? radius * 0.07 : radius * 0.03)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize) {
        let p = CGPoint(x: size.width / 2, y: size.height / 2)
        let R = radius
        let length = R * TurntableMetrics.armLength
        let tilt = CGFloat.pi / 180 * 14

        // Counterweight behind the pivot (kept short so it stays inside the plinth).
        let weight = CGRect(x: p.x - R * 0.17, y: p.y - R * 0.075, width: R * 0.13, height: R * 0.15)
        let weightPath = Path(roundedRect: weight, cornerRadius: R * 0.025)
        ctx.fill(weightPath, with: .linearGradient(Gradient(colors: [Color(white: 0.34), Color(white: 0.13)]),
                                                   startPoint: CGPoint(x: weight.minX, y: weight.minY),
                                                   endPoint: CGPoint(x: weight.minX, y: weight.maxY)))
        ctx.stroke(weightPath, with: .color(Color.white.opacity(0.18)), lineWidth: 0.6)
        let stub = CGRect(x: p.x - R * 0.05, y: p.y - R * 0.022, width: R * 0.05, height: R * 0.044)
        ctx.fill(Path(roundedRect: stub, cornerRadius: R * 0.01), with: .color(Color(white: 0.45)))

        // Slim metallic shaft.
        let w = R * 0.030
        let shaft = CGRect(x: p.x, y: p.y - w / 2, width: length, height: w)
        let metal = Gradient(colors: [Color(white: 0.93), Color(white: 0.62), Color(white: 0.30)])
        ctx.fill(Path(roundedRect: shaft, cornerRadius: w / 2),
                 with: .linearGradient(metal, startPoint: CGPoint(x: p.x, y: p.y - w / 2), endPoint: CGPoint(x: p.x, y: p.y + w / 2)))

        // Angled headshell and cartridge at the tip.
        var head = Path(roundedRect: CGRect(x: -R * 0.20, y: -R * 0.038, width: R * 0.20, height: R * 0.076), cornerRadius: R * 0.018)
        head = head.applying(CGAffineTransform(rotationAngle: tilt)).applying(CGAffineTransform(translationX: p.x + length, y: p.y))
        ctx.fill(head, with: .color(Color(white: 0.16)))
        ctx.stroke(head, with: .color(Color.white.opacity(0.35)), lineWidth: 0.7)

        var cartridge = Path(roundedRect: CGRect(x: -R * 0.045, y: -R * 0.03, width: R * 0.095, height: R * 0.06), cornerRadius: R * 0.01)
        cartridge = cartridge.applying(CGAffineTransform(rotationAngle: tilt)).applying(CGAffineTransform(translationX: p.x + length, y: p.y))
        ctx.fill(cartridge, with: .color(Color(red: 0.10, green: 0.10, blue: 0.11)))
        ctx.stroke(cartridge, with: .color(Color(red: 0.62, green: 0.16, blue: 0.13)), lineWidth: 0.9)

        // Stylus tip, exactly at the end of the shaft.
        let tip = R * 0.012
        ctx.fill(Path(ellipseIn: CGRect(x: p.x + length - tip, y: p.y - tip, width: tip * 2, height: tip * 2)),
                 with: .color(Color(white: 0.92)))

        // Pivot cap, drawn last so it sits over the start of the shaft.
        let base = R * 0.105
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - base, y: p.y - base, width: base * 2, height: base * 2)),
                 with: .radialGradient(Gradient(colors: [Color(white: 0.44), Color(white: 0.15)]),
                                       center: CGPoint(x: p.x - base * 0.3, y: p.y - base * 0.3),
                                       startRadius: 0, endRadius: base * 1.3))
        ctx.stroke(Path(ellipseIn: CGRect(x: p.x - base, y: p.y - base, width: base * 2, height: base * 2)),
                   with: .color(Color.white.opacity(0.28)), lineWidth: 0.8)
        let inner = base * 0.55
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - inner, y: p.y - inner, width: inner * 2, height: inner * 2)),
                 with: .color(Color(white: 0.20)))
        let screw = base * 0.22
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - screw, y: p.y - screw, width: screw * 2, height: screw * 2)),
                 with: .color(Color(white: 0.62)))
    }
}
