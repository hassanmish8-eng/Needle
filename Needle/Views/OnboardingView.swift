import SwiftUI

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(Color.black)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.75 : 0.95)))
    }
}

/// First launch: wordmark, an illustration of a record, one clear action.
/// Credentials are never typed into NEEDLE; sign-in happens inside the Spotify app.
@MainActor
struct OnboardingView: View {
    @EnvironmentObject private var playback: PlaybackViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let sample = VinylAppearance(style: .translucent,
                                         palette: .manual(RGBColor(0.80, 0.20, 0.12)),
                                         grooves: .normal,
                                         reflections: true)

    var body: some View {
        let status = playback.connectionStatus
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [Color(red: 0.10, green: 0.065, blue: 0.06), Theme.ink],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: 16)
                        illustration(size: min(geo.size.width * 0.74, geo.size.height * 0.40, 340))
                        Spacer(minLength: 24)
                        VStack(spacing: 10) {
                            Text("NEEDLE")
                                .font(.system(size: 15, weight: .semibold))
                                .tracking(5)
                                .foregroundColor(Theme.secondaryText)
                                .accessibilityAddTraits(.isHeader)
                            Text("Your music, pressed into vinyl.")
                                .font(.system(.title, design: .serif).weight(.semibold))
                                .foregroundColor(Theme.primaryText)
                                .multilineTextAlignment(.center)
                                .accessibilityIdentifier("tagline")
                        }
                        Spacer(minLength: 28)
                        bottomBlock(status: status)
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 20)
                    .frame(minHeight: geo.size.height)
                }
            }
        }
    }

    private func illustration(size: CGFloat) -> some View {
        SpinningDisc(disc: VinylDiscView(appearance: sample, artwork: .placeholder, animateTransitions: false),
                     spinning: !reduceMotion)
            .frame(width: size, height: size)
            .shadow(color: Color.black.opacity(0.6), radius: size * 0.08, y: size * 0.05)
            .accessibilityHidden(true)
    }

    @ViewBuilder private func bottomBlock(status: ConnectionStatus) -> some View {
        VStack(spacing: 14) {
            if let message = message(for: status) {
                Text(message)
                    .font(.footnote)
                    .foregroundColor(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("onboardingMessage")
            }
            switch status {
            case .authorizing:
                HStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text("Waiting for Spotify…").foregroundColor(Theme.secondaryText)
                }
                .frame(minHeight: 54)
                Button("Cancel") { playback.disconnect() }
                    .foregroundColor(Theme.secondaryText)
                    .accessibilityIdentifier("cancelAuthButton")
            case .spotifyNotInstalled:
                Button("Get Spotify") { playback.openSpotify() }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("getSpotifyButton")
                Button("I've installed it, try again") { playback.reauthorize() }
                    .foregroundColor(Theme.secondaryText)
            default:
                Button("Connect Spotify") { playback.reauthorize() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(status == .notConfigured)
                    .opacity(status == .notConfigured ? 0.4 : 1)
                    .accessibilityIdentifier("connectSpotifyButton")
            }
            Text("Needs the official Spotify app, which plays the music. NEEDLE never sees your password.")
                .font(.caption)
                .foregroundColor(Theme.tertiaryText)
                .multilineTextAlignment(.center)
        }
    }

    private func message(for status: ConnectionStatus) -> String? {
        switch status {
        case .notConfigured, .spotifyNotInstalled:
            return status.detail
        case .notAuthorized(let message):
            return message
        default:
            return nil
        }
    }
}
