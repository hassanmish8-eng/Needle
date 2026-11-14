import UIKit

/// Memory + disk cache of extracted palettes, keyed by a stable artwork key.
final class PaletteCache: @unchecked Sendable {
    private let directory: URL
    private var memory: [String: AlbumPalette] = [:]
    private let lock = NSLock()
    private let maxEntries = 300

    init(directory: URL? = nil) {
        if let directory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            self.directory = directory
        } else {
            self.directory = CacheDirectory.caches("palettes")
        }
    }

    func palette(forKey key: String) -> AlbumPalette? {
        lock.lock(); defer { lock.unlock() }
        if let hit = memory[key] { return hit }
        guard let data = try? Data(contentsOf: fileURL(for: key)),
              let palette = try? JSONDecoder().decode(AlbumPalette.self, from: data),
              palette.version == AlbumPalette.currentVersion else { return nil }
        memory[key] = palette
        return palette
    }

    func store(_ palette: AlbumPalette, forKey key: String) {
        lock.lock(); defer { lock.unlock() }
        memory[key] = palette
        if let data = try? JSONEncoder().encode(palette) {
            try? data.write(to: fileURL(for: key), options: .atomic)
        }
        CacheDirectory.prune(directory, keep: maxEntries)
    }

    private func fileURL(for key: String) -> URL {
        directory.appendingPathComponent(key.sha256Hex + ".json")
    }
}

/// Runs extraction off the main thread and caches the result.
final class ColorPaletteService {
    private let cache: PaletteCache

    init(cache: PaletteCache = PaletteCache()) {
        self.cache = cache
    }

    func cachedPalette(forKey key: String) -> AlbumPalette? {
        cache.palette(forKey: key)
    }

    func palette(for image: UIImage, key: String) async -> AlbumPalette {
        if let cached = cache.palette(forKey: key) { return cached }
        let extracted: AlbumPalette? = await Task.detached(priority: .userInitiated) {
            ColorExtractor.extract(from: image)
        }.value
        guard let palette = extracted else { return .neutral }   // unusable art: neutral, uncached
        cache.store(palette, forKey: key)
        return palette
    }
}
