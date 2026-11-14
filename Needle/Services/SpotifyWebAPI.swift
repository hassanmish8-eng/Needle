import Foundation

struct SearchTrack: Identifiable, Equatable { let id: String; let uri: String; let name: String; let artists: String; let album: String; let imageURL: URL? }
struct SearchAlbum: Identifiable, Equatable { let id: String; let uri: String; let name: String; let artists: String; let imageURL: URL? }
struct SearchArtist: Identifiable, Equatable { let id: String; let uri: String; let name: String; let imageURL: URL? }

struct SearchResults: Equatable {
    var tracks: [SearchTrack] = []
    var albums: [SearchAlbum] = []
    var artists: [SearchArtist] = []
    var isEmpty: Bool { tracks.isEmpty && albums.isEmpty && artists.isEmpty }
}

/// Minimal Spotify Web API client (search + display name). Optional: the vinyl player
/// works without it, and unsupported endpoints never affect basic playback.
@MainActor
final class SpotifyWebAPI {
    enum APIError: LocalizedError, Equatable {
        case notSignedIn, unauthorized, forbidden, rateLimited(Int?), http(Int), network(String)

        var errorDescription: String? {
            switch self {
            case .notSignedIn: return "Connect Spotify to search."
            case .unauthorized: return "Your Spotify sign-in expired. Sign in again to search."
            case .forbidden: return "Spotify didn't allow this request. Apps in Development Mode only work for accounts added to the app's User Management list."
            case .rateLimited(let seconds):
                return seconds.map { "Spotify is rate limiting NEEDLE. Try again in \($0) s." } ?? "Spotify is rate limiting NEEDLE. Try again shortly."
            case .http(let code): return "Spotify returned an error (HTTP \(code))."
            case .network(let text): return "Couldn't reach Spotify: \(text)"
            }
        }
    }

    private let tokenProvider: () -> String?
    private let session: URLSession

    init(tokenProvider: @escaping () -> String?, session: URLSession = .shared) {
        self.tokenProvider = tokenProvider
        self.session = session
    }

    func search(_ query: String, limit: Int = 10) async throws -> SearchResults {
        var components = URLComponents(string: "https://api.spotify.com/v1/search")!
        components.queryItems = [URLQueryItem(name: "q", value: query),
                                 URLQueryItem(name: "type", value: "track,album,artist"),
                                 URLQueryItem(name: "limit", value: String(limit))]
        let data = try await get(components.url!)
        do {
            let raw = try JSONDecoder().decode(RawSearch.self, from: data)
            return SearchResults(
                tracks: (raw.tracks?.items ?? []).compactMap { $0 }.map {
                    SearchTrack(id: $0.uri, uri: $0.uri, name: $0.name,
                                artists: Self.names($0.artists), album: $0.album?.name ?? "",
                                imageURL: Self.pick($0.album?.images))
                },
                albums: (raw.albums?.items ?? []).compactMap { $0 }.map {
                    SearchAlbum(id: $0.uri, uri: $0.uri, name: $0.name, artists: Self.names($0.artists), imageURL: Self.pick($0.images))
                },
                artists: (raw.artists?.items ?? []).compactMap { $0 }.map {
                    SearchArtist(id: $0.uri ?? $0.name, uri: $0.uri ?? "", name: $0.name, imageURL: Self.pick($0.images))
                })
        } catch {
            throw APIError.network("unexpected response")
        }
    }

    /// Best effort; nil on any failure (the connection panel just omits the account line).
    func currentUserName() async -> String? {
        guard let url = URL(string: "https://api.spotify.com/v1/me"),
              let data = try? await get(url),
              let me = try? JSONDecoder().decode(RawMe.self, from: data) else { return nil }
        return me.display_name ?? me.id
    }

    private func get(_ url: URL) async throws -> Data {
        guard let token = tokenProvider() else { throw APIError.notSignedIn }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.network("no response") }
            switch http.statusCode {
            case 200..<300: return data
            case 401: throw APIError.unauthorized
            case 403: throw APIError.forbidden
            case 429: throw APIError.rateLimited(Int(http.value(forHTTPHeaderField: "Retry-After") ?? ""))
            default: throw APIError.http(http.statusCode)
            }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.network(error.localizedDescription)
        }
    }

    private static func names(_ artists: [RawArtist]?) -> String {
        (artists ?? []).map(\.name).joined(separator: ", ")
    }

    /// Prefer the image closest to 160 px wide; thumbnails are shown at ~48 pt.
    private static func pick(_ images: [RawImage]?) -> URL? {
        guard let images, !images.isEmpty else { return nil }
        let best = images.min { abs(($0.width ?? 640) - 160) < abs(($1.width ?? 640) - 160) }
        return best.flatMap { URL(string: $0.url) }
    }
}

private struct RawImage: Decodable { let url: String; let width: Int? }
private struct RawArtist: Decodable { let uri: String?; let name: String; let images: [RawImage]? }
private struct RawAlbum: Decodable { let uri: String; let name: String; let artists: [RawArtist]?; let images: [RawImage]? }
private struct RawTrack: Decodable { let uri: String; let name: String; let artists: [RawArtist]?; let album: RawAlbum? }
private struct RawPage<T: Decodable>: Decodable { let items: [T?] }
private struct RawSearch: Decodable {
    let tracks: RawPage<RawTrack>?
    let albums: RawPage<RawAlbum>?
    let artists: RawPage<RawArtist>?
}
private struct RawMe: Decodable { let id: String; let display_name: String? }
