import XCTest
@testable import Needle

final class ColorExtractionTests: XCTestCase {

    private func palette(_ image: UIImage, file: StaticString = #filePath, line: UInt = #line) -> AlbumPalette {
        guard let p = ColorExtractor.extract(from: image) else {
            XCTFail("extraction returned nil", file: file, line: line)
            return .neutral
        }
        return p
    }

    func testRedCoverGivesRedVinyl() {
        let p = palette(TestImages.solid(UIColor(red: 0.78, green: 0.08, blue: 0.12, alpha: 1)))
        XCTAssertTrue(isRedHue(p.primary.hsl.h), "hue \(p.primary.hsl.h)")
        XCTAssertFalse(p.isMonochrome)
    }

    func testBlueCoverGivesBlueVinyl() {
        let p = palette(TestImages.solid(UIColor(red: 0.08, green: 0.20, blue: 0.63, alpha: 1)))
        XCTAssertTrue(isBlueHue(p.primary.hsl.h))
    }

    func testYellowCoverGivesAmberVinyl() {
        let p = palette(TestImages.solid(UIColor(red: 0.98, green: 0.78, blue: 0.12, alpha: 1)))
        XCTAssertTrue(isYellowOrangeHue(p.primary.hsl.h))
    }

    func testSmallRedLogoOnBlueCoverStillGivesBlueVinyl() {
        let p = palette(TestImages.blueWithRedLogo())
        XCTAssertTrue(isBlueHue(p.primary.hsl.h), "primary hue \(p.primary.hsl.h)")
    }

    func testMonochromeCoverIsDetected() {
        let p = palette(TestImages.solid(UIColor(white: 0.5, alpha: 1)))
        XCTAssertTrue(p.isMonochrome)
        XCTAssertLessThan(p.primary.hsl.s, 0.05)
    }

    func testBlackCoverGivesBlackVinylAndWhiteCoverGivesWhiteVinyl() {
        XCTAssertLessThan(palette(TestImages.solid(.black)).primary.hsl.l, 0.15)
        XCTAssertGreaterThan(palette(TestImages.solid(UIColor(white: 0.97, alpha: 1))).primary.hsl.l, 0.7)
    }

    func testMulticolorCoverGivesFourToSixDistinctColors() {
        let p = palette(TestImages.quadrants())
        XCTAssertGreaterThanOrEqual(p.colors.count, 4)
        XCTAssertLessThanOrEqual(p.colors.count, 6)
        for i in 0..<p.colors.count {
            for j in (i + 1)..<p.colors.count {
                XCTAssertGreaterThan(RGBColor.distance(p.colors[i], p.colors[j]), 0.1)
            }
        }
    }

    func testTransparentPixelsAreIgnored() {
        let p = palette(TestImages.transparentWithGreenDisc())
        XCTAssertTrue(isGreenHue(p.primary.hsl.h), "hue \(p.primary.hsl.h)")
    }

    func testFullyTransparentImageIsRejected() {
        XCTAssertNil(ColorExtractor.extract(from: TestImages.fullyTransparent()))
    }

    func testExtractionIsDeterministic() {
        let image = TestImages.quadrants()
        XCTAssertEqual(ColorExtractor.extract(from: image), ColorExtractor.extract(from: image))
    }

    func testBrightCoverNeverMakesWhiteTextUnreadable() {
        for color in [UIColor.yellow, UIColor(white: 0.97, alpha: 1), UIColor(red: 1, green: 0.9, blue: 0.5, alpha: 1)] {
            let p = palette(TestImages.solid(color))
            XCTAssertGreaterThanOrEqual(RGBColor.contrastRatio(.white, p.backgroundTop), 7)
            XCTAssertGreaterThanOrEqual(RGBColor.contrastRatio(.white, p.backgroundBottom), 7)
            XCTAssertGreaterThanOrEqual(RGBColor.contrastRatio(p.accent, p.backgroundBottom), 4.5)
        }
    }

    func testPaletteColorsAreInVinylFriendlyRange() {
        for image in [TestImages.quadrants(), TestImages.blueWithRedLogo()] {
            for c in palette(image).colors {
                XCTAssertGreaterThanOrEqual(c.hsl.l, 0.13)
                XCTAssertLessThanOrEqual(c.hsl.l, 0.63)
            }
        }
    }
}
