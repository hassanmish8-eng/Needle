import Foundation

enum RepeatMode: String, Equatable, Codable {
    case off, track, context
}

struct PlaybackRestrictions: Equatable {
    var canSkipNext = true
    var canSkipPrevious = true
    var canSeek = true
    var canToggleShuffle = true
    var canRepeatTrack = true
    var canRepeatContext = true
}

enum PlaybackControl: Hashable {
    case playPause, next, previous, shuffle, repeatMode, seek
}

struct TrackInfo: Equatable, Hashable, Identifiable {
    let uri: String
    let title: String
    let artist: String
    let album: String
    let albumURI: String
    let imageIdentifier: String
    let durationMs: Int

    var id: String { uri }

    /// Stable cache key: album + image identifier. Tracks on the same album share it,
    /// so the vinyl is not regenerated when moving between tracks of one album.
    var artworkKey: String {
        if albumURI.isEmpty && imageIdentifier.isEmpty { return "track:" + uri }
        return albumURI + "#" + imageIdentifier
    }

    /// Key used for per-album vinyl style overrides.
    var albumKey: String { albumURI.isEmpty ? artworkKey : albumURI }
}

/// One immutable observation of Spotify's player. The UI never assumes a command
/// succeeded; it only ever renders the latest snapshot Spotify reported.
struct PlaybackSnapshot: Equatable {
    var track: TrackInfo?
    var isPaused: Bool
    var positionMs: Int
    var playbackSpeed: Double = 1
    var isShuffling: Bool
    var repeatMode: RepeatMode
    var restrictions: PlaybackRestrictions = PlaybackRestrictions()
    /// When Spotify reported `positionMs`; used to extrapolate between updates.
    var receivedAt: Date

    var isPlaying: Bool { !isPaused && track != nil }

    /// Position extrapolated from the last real report. Re-synced on every Spotify update.
    func positionMs(at date: Date) -> Int {
        var position = max(positionMs, 0)
        if isPlaying {
            let elapsed = max(0, date.timeIntervalSince(receivedAt))
            position += Int(elapsed * 1000 * playbackSpeed)
        }
        if let duration = track?.durationMs, duration > 0 {
            position = min(position, duration)
        }
        return position
    }

    /// 0...1, or nil when the duration is unknown.
    func progress(at date: Date) -> Double? {
        guard let duration = track?.durationMs, duration > 0 else { return nil }
        return Double(positionMs(at: date)) / Double(duration)
    }
}

enum TimeFormat {
    /// "3:07", or "1:02:03" for long items. Nil/negative renders as a placeholder.
    static func string(ms: Int?) -> String {
        guard let ms, ms >= 0 else { return "–:––" }
        let total = ms / 1000
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
