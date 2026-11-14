import SwiftUI

/// A simple three-arc broadcast glyph. Swap in Spotify's official logo asset from their
/// brand guidelines if you distribute the app (see README).
struct SpotifyGlyph: View {
    var color: Color

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) / 2
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(color))
            let widths: [CGFloat] = [1.26, 1.04, 0.80]
            let ys: [CGFloat] = [-0.42, -0.04, 0.34]
            for i in 0..<3 {
                var arc = Path()
                let half = r * widths[i] / 2
                let y = c.y + r * ys[i]
                arc.move(to: CGPoint(x: c.x - half, y: y + r * 0.08))
                arc.addQuadCurve(to: CGPoint(x: c.x + half, y: y + r * 0.08), control: CGPoint(x: c.x, y: y - r * 0.30))
                ctx.stroke(arc, with: .color(Theme.ink), style: StrokeStyle(lineWidth: r * 0.15, lineCap: .round))
            }
        }
        .accessibilityHidden(true)
    }
}

struct ConnectionPill: View {
    let status: ConnectionStatus
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                SpotifyGlyph(color: status.isConnected ? Theme.spotifyGreen : Color.white.opacity(0.4))
                    .frame(width: 14, height: 14)
                Text(status.shortLabel)
                    .font(.footnote)
                    .foregroundColor(Theme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 32)
            .background(Capsule().fill(Color.white.opacity(0.08)))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Spotify: \(status.shortLabel)")
        .accessibilityHint("Opens connection details")
        .accessibilityIdentifier("connectionPill")
    }
}

/// Wordmark left, live connection state, then search and settings.
@MainActor
struct HeaderView: View {
    @EnvironmentObject private var playback: PlaybackViewModel
    let onConnection: () -> Void
    let onSearch: () -> Void
    let onSettings: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text("NEEDLE")
                .font(.system(size: 13, weight: .semibold))
                .tracking(3.2)
                .foregroundColor(Theme.secondaryText)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 6)
            ConnectionPill(status: playback.connectionStatus, action: onConnection)
            Spacer(minLength: 6)
            iconButton("magnifyingglass", label: "Search music", id: "searchButton", action: onSearch)
            iconButton("gearshape", label: "Settings", id: "settingsButton", action: onSettings)
        }
        .frame(minHeight: 48)
    }

    private func iconButton(_ symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .regular))
                .foregroundColor(Theme.primaryText)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}

struct StripButton {
    let title: String
    let id: String
    let action: () -> Void
}

struct StripContent {
    let text: String
    var spinner = false
    var buttons: [StripButton] = []
}

/// Inline status under the header for every non-connected state, always with a way out.
@MainActor
struct StatusStrip: View {
    @EnvironmentObject private var playback: PlaybackViewModel

    var body: some View {
        if let content = content {
            HStack(spacing: 10) {
                if content.spinner {
                    ProgressView().scaleEffect(0.8)
                }
                Text(content.text)
                    .font(.footnote)
                    .foregroundColor(Theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(content.buttons, id: \.id) { button in
                    Button(button.title, action: button.action)
                        .font(.footnote.weight(.semibold))
                        .buttonStyle(.bordered)
                        .tint(.white)
                        .accessibilityIdentifier(button.id)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))
            .padding(.bottom, 6)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("statusStrip")
        }
    }

    private var content: StripContent? {
        let reconnect = StripButton(title: "Reconnect", id: "reconnectButton") { playback.reconnect() }
        let open = StripButton(title: "Open Spotify", id: "openSpotifyButton") { playback.openSpotify() }
        switch playback.connectionStatus {
        case .connecting:
            return StripContent(text: "Connecting to Spotify…", spinner: true)
        case .disconnected(let message):
            return StripContent(text: message ?? "Disconnected from Spotify.", buttons: [reconnect, open])
        case .failed(let message):
            return StripContent(text: message, buttons: [reconnect, open])
        case .sessionExpired:
            let signIn = StripButton(title: "Sign in again", id: "signInAgainButton") { playback.reauthorize() }
            return StripContent(text: ConnectionStatus.sessionExpired.detail, buttons: [signIn])
        case .connected:
            return playback.isOffline
                ? StripContent(text: "You're offline. Spotify may not report live playback.")
                : nil
        default:
            return nil
        }
    }
}

struct BannerView: View {
    let banner: Banner
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: banner.kind == .error ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundColor(Theme.primaryText)
                .accessibilityHidden(true)
            Text(banner.message)
                .font(.footnote)
                .foregroundColor(Theme.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: dismiss) {
                Image(systemName: "xmark").font(.footnote.weight(.semibold)).foregroundColor(Theme.secondaryText)
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel("Dismiss message")
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(white: 0.16)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
        .shadow(color: Color.black.opacity(0.4), radius: 12, y: 6)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("errorBanner")
        .onAppear { UIAccessibility.post(notification: .announcement, argument: banner.message) }
    }
}
