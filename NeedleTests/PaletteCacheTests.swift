import XCTest
@testable import Needle

final class PaletteCacheTests: XCTestCase {

    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("needle-tests-\(UUID().uuidString)")
    }

    func testPaletteSurvivesANewCacheInstance() throws {
        let dir = tempDirectory()
        let palette = try XCTUnwrap(ColorExtractor.extract(from: TestImages.quadrants()))
        PaletteCache(directory: dir).store(palette, forKey: "album-1#image-1")
        XCTAssertEqual(PaletteCache(directory: dir).palette(forKey: "album-1#image-1"), palette)
    }

    func testMissingKeyReturnsNil() {
        XCTAssertNil(PaletteCache(directory: tempDirectory()).palette(forKey: "nope"))
    }

    func testStalePaletteVersionIsIgnored() throws {
        let dir = tempDirectory()
        var palette = try XCTUnwrap(ColorExtractor.extract(from: TestImages.quadrants()))
        palette.version = AlbumPalette.currentVersion - 1
        PaletteCache(directory: dir).store(palette, forKey: "k")
        XCTAssertNil(PaletteCache(directory: dir).palette(forKey: "k"))
    }

    func testServiceCachesAfterFirstExtraction() async {
        let service = ColorPaletteService(cache: PaletteCache(directory: tempDirectory()))
        XCTAssertNil(service.cachedPalette(forKey: "a"))
        let first = await service.palette(for: TestImages.blueWithRedLogo(), key: "a")
        XCTAssertEqual(service.cachedPalette(forKey: "a"), first)
        // A second call with different pixels but the same key returns the cached result.
        let second = await service.palette(for: TestImages.solid(.red), key: "a")
        XCTAssertEqual(first, second)
    }

    func testUnusableArtworkFallsBackToNeutralWithoutCaching() async {
        let service = ColorPaletteService(cache: PaletteCache(directory: tempDirectory()))
        let result = await service.palette(for: TestImages.fullyTransparent(), key: "blank")
        XCTAssertEqual(result, AlbumPalette.neutral)
        XCTAssertNil(service.cachedPalette(forKey: "blank"))
    }
}
