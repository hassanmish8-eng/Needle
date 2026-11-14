import UIKit

/// Retrieves artwork through an injected fetcher (App Remote), validates it, and caches it
/// on disk + in memory under the track's stable artwork key.
@MainActor
final class ArtworkService {
    static let requestSize = CGSize(width: 640, height: 640)

    private let memory = NSCache<NSString, UIImage>()
    private let directory: URL

    init(directory: URL? = nil) {
        if let directory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            self.directory = directory
        } else {
            self.directory = CacheDirectory.caches("artwork")
        }
        memory.countLimit = 12
        let dir = self.directory
        Task.detached(priority: .utility) { CacheDirectory.prune(dir, keep: 150) }
    }

    nonisolated static func isValid(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage else { return false }
        return cg.width >= 16 && cg.height >= 16
    }

    func loadImage(for track: TrackInfo, fetch: @escaping (TrackInfo) async throws -> UIImage) async throws -> UIImage {
        let key = track.artworkKey
        if let hit = memory.object(forKey: key as NSString) { return hit }

        let url = fileURL(for: key)
        let fromDisk: UIImage? = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let data = try? Data(contentsOf: url), let image = UIImage(data: data),
                  ArtworkService.isValid(image) else { return nil }
            return image
        }.value
        if let fromDisk {
            memory.setObject(fromDisk, forKey: key as NSString)
            return fromDisk
        }

        let fetched = try await fetch(track)
        guard Self.isValid(fetched) else { throw SpotifyError.artworkUnavailable }
        memory.setObject(fetched, forKey: key as NSString)
        if let data = Self.encode(fetched) {
            Task.detached(priority: .utility) { try? data.write(to: url, options: .atomic) }
        }
        return fetched
    }

    private func fileURL(for key: String) -> URL {
        directory.appendingPathComponent(key.sha256Hex + ".img")
    }

    nonisolated static func encode(_ image: UIImage) -> Data? {
        guard let cg = image.cgImage else { return image.pngData() }
        switch cg.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return image.jpegData(compressionQuality: 0.92)
        default: return image.pngData()
        }
    }
}
