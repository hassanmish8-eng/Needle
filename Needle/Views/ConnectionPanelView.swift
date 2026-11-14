import SwiftUI

/// Small sheet behind the header's connection pill.
@MainActor
struct ConnectionPanelView: View {
    @EnvironmentObject private var playback: PlaybackViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let status = playback.connectionStatus
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                SpotifyGlyph(color: status.isConnected ? Theme.spotifyGreen : Color.white.opacity(0.4))
                    .frame(width: 22, height: 22)
                Text("Spotify").font(.headline).foregroundColor(Theme.primaryText)
                Spacer()
                Button("Done") { dismiss() }
                    .accessibilityIdentifier("connectionDoneButton")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(status.shortLabel)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(Theme.primaryText)
                Text(status.detail)
                    .font(.subheadline)
                    .foregroundColor(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let name = playback.accountName, status.isConnected {
                    Label(name, systemImage: "person.crop.circle")
                        .font(.subheadline)
                        .foregroundColor(Theme.secondaryText)
                }
            }

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Button(status.isConnected ? "Reconnect" : "Reconnect to Spotify") {
                    playback.reconnect()
                    if !status.isConnected { dismiss() }
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("panelReconnectButton")

                Button("Open Spotify") { playback.openSpotify() }
                    .buttonStyle(.bordered).tint(.white)

                Button("Disconnect", role: .destructive) {
                    playback.disconnect()
                    dismiss()
                }
                .accessibilityIdentifier("panelDisconnectButton")
            }
        }
        .padding(24)
        .background(Theme.ink.ignoresSafeArea())
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }
}
