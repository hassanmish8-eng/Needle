import Foundation

enum ConnectionStatus: Equatable {
    case notConfigured
    case spotifyNotInstalled
    case notAuthorized(String?)
    case authorizing
    case sessionExpired
    case connecting
    case connected
    case disconnected(String?)
    case failed(String)

    var isConnected: Bool { self == .connected }

    /// Shown with the first-launch screen instead of the player.
    var needsOnboarding: Bool {
        switch self {
        case .notConfigured, .notAuthorized, .spotifyNotInstalled, .authorizing: return true
        default: return false
        }
    }

    var isTransient: Bool { self == .connecting || self == .authorizing }

    /// Compact label for the header pill. Never says "Connected" unless App Remote is connected.
    var shortLabel: String {
        switch self {
        case .connected: return "Connected"
        case .connecting: return "Connecting…"
        case .authorizing: return "Signing in…"
        case .sessionExpired: return "Session expired"
        default: return "Not connected"
        }
    }

    var detail: String {
        switch self {
        case .notConfigured:
            return "NEEDLE needs a Spotify Client ID. See the README, then rebuild."
        case .spotifyNotInstalled:
            return "The official Spotify app is required. It plays the music; NEEDLE only displays and controls it."
        case .notAuthorized(let message):
            return message ?? "Connect your Spotify account to start."
        case .authorizing:
            return "Waiting for Spotify…"
        case .sessionExpired:
            return "Your Spotify sign-in expired. Sign in again to continue."
        case .connecting:
            return "Connecting to the Spotify app…"
        case .connected:
            return "Connected to the Spotify app."
        case .disconnected(let message):
            return message ?? "NEEDLE lost its connection to Spotify."
        case .failed(let message):
            return message
        }
    }
}

enum SpotifyError: LocalizedError, Equatable {
    case notConnected
    case premiumRequired
    case rejected(String)
    case artworkUnavailable

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "NEEDLE isn't connected to Spotify right now. Reconnect and try again."
        case .premiumRequired:
            return "Spotify only allows this on Premium accounts."
        case .rejected(let message):
            return message.isEmpty ? "Spotify rejected that command." : "Spotify rejected that command: \(message)"
        case .artworkUnavailable:
            return "Spotify didn't return artwork for this track."
        }
    }

    static func from(_ error: Error) -> SpotifyError {
        if let known = error as? SpotifyError { return known }
        let text = error.localizedDescription
        if text.lowercased().contains("premium") { return .premiumRequired }
        return .rejected(text)
    }
}
