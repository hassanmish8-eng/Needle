import UIKit
@testable import Needle

enum TestImages {
    private static func render(size: CGFloat = 128, opaque: Bool = true, _ draw: (CGContext, CGFloat) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = opaque
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format).image { ctx in
            draw(ctx.cgContext, size)
        }
    }

    static func solid(_ color: UIColor) -> UIImage {
        render { ctx, s in
            ctx.setFillColor(color.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
        }
    }

    /// Mostly blue with a small red logo in the corner (the spec's "don't pick the logo" case).
    static func blueWithRedLogo() -> UIImage {
        render { ctx, s in
            ctx.setFillColor(UIColor(red: 0.08, green: 0.20, blue: 0.63, alpha: 1).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
            ctx.setFillColor(UIColor(red: 0.86, green: 0.08, blue: 0.12, alpha: 1).cgColor)
            ctx.fill(CGRect(x: 6, y: 6, width: s * 0.09, height: s * 0.09))
        }
    }

    static func quadrants() -> UIImage {
        render { ctx, s in
            let colors: [UIColor] = [UIColor(red: 0.86, green: 0.12, blue: 0.12, alpha: 1),
                                     UIColor(red: 0.12, green: 0.70, blue: 0.24, alpha: 1),
                                     UIColor(red: 0.12, green: 0.24, blue: 0.78, alpha: 1),
                                     UIColor(red: 0.94, green: 0.82, blue: 0.16, alpha: 1)]
            let h = s / 2
            for (i, color) in colors.enumerated() {
                ctx.setFillColor(color.cgColor)
                ctx.fill(CGRect(x: CGFloat(i % 2) * h, y: CGFloat(i / 2) * h, width: h, height: h))
            }
        }
    }

    /// Transparent background with a green disc: the transparent pixels must be ignored.
    static func transparentWithGreenDisc() -> UIImage {
        render(opaque: false) { ctx, s in
            ctx.setFillColor(UIColor(red: 0.12, green: 0.67, blue: 0.27, alpha: 1).cgColor)
            ctx.fillEllipse(in: CGRect(x: s * 0.25, y: s * 0.25, width: s * 0.5, height: s * 0.5))
        }
    }

    static func fullyTransparent() -> UIImage {
        render(opaque: false) { _, _ in }
    }
}

func isRedHue(_ h: Double) -> Bool { h < 0.04 || h > 0.94 }
func isBlueHue(_ h: Double) -> Bool { h > 0.55 && h < 0.72 }
func isGreenHue(_ h: Double) -> Bool { h > 0.25 && h < 0.48 }
func isYellowOrangeHue(_ h: Double) -> Bool { h > 0.07 && h < 0.18 }
