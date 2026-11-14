import SwiftUI

@MainActor
struct SettingsView: View {
    @EnvironmentObject private var settingsVM: SettingsViewModel
    @EnvironmentObject private var playback: PlaybackViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            Form {
                appearanceSection
                animationSection
                spotifySection
                generalSection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.ink.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("settingsDoneButton")
                }
            }
            .confirmationDialog("Reset all appearance and animation settings?",
                                isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset", role: .destructive) { settingsVM.resetAppearance() }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Bindings

    private var currentAlbumKey: String? { playback.track?.albumKey }

    private var styleBinding: Binding<VinylStyle> {
        Binding(get: { settingsVM.settings.style(forAlbum: currentAlbumKey) },
                set: { settingsVM.setStyle($0, forAlbum: currentAlbumKey) })
    }

    private var manualColorBinding: Binding<Color> {
        Binding(get: { settingsVM.settings.manualColor.color },
                set: { settingsVM.settings.manualColor = RGBColor($0) })
    }

    // MARK: Sections

    private var appearanceSection: some View {
        Section {
            Picker(currentAlbumKey == nil ? "Vinyl style" : "Vinyl style (this album)", selection: styleBinding) {
                ForEach(VinylStyle.allCases) { Text($0.title).tag($0) }
            }
            if let key = currentAlbumKey, settingsVM.settings.albumStyles[key] != nil {
                Button("Use the default style for this album") { settingsVM.clearStyleOverride(forAlbum: key) }
            }
            Picker("Default style for new albums", selection: $settingsVM.settings.defaultStyle) {
                ForEach(VinylStyle.allCases) { Text($0.title).tag($0) }
            }
            Picker("Background", selection: $settingsVM.settings.backgroundStyle) {
                ForEach(BackgroundStyle.allCases) { Text($0.title).tag($0) }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Background blur")
                Slider(value: $settingsVM.settings.backgroundBlur, in: 0...1)
                    .accessibilityLabel("Background blur intensity")
            }
            .disabled(settingsVM.settings.backgroundStyle != .albumBlur)
            .opacity(settingsVM.settings.backgroundStyle == .albumBlur ? 1 : 0.4)

            VStack(alignment: .leading, spacing: 6) {
                Text("Vinyl size")
                Picker("Vinyl size", selection: $settingsVM.settings.vinylSize) {
                    ForEach(VinylSize.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Groove visibility")
                Picker("Groove visibility", selection: $settingsVM.settings.grooveVisibility) {
                    ForEach(GrooveVisibility.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Toggle("Show tonearm", isOn: $settingsVM.settings.showTonearm)
            Toggle("Surface reflections", isOn: $settingsVM.settings.surfaceReflections)
            Toggle("Extract colors from album art", isOn: $settingsVM.settings.autoExtractColors)
            Toggle("Override the vinyl color", isOn: $settingsVM.settings.manualColorEnabled)
            if settingsVM.settings.manualColorEnabled {
                ColorPicker("Vinyl color", selection: manualColorBinding, supportsOpacity: false)
            }
        } header: {
            Text("Appearance")
        } footer: {
            Text("Changes apply instantly and don't interrupt playback.")
        }
    }

    private var animationSection: some View {
        Section {
            Toggle("Continuous vinyl rotation", isOn: $settingsVM.settings.continuousRotation)
            Toggle("Tonearm animation", isOn: $settingsVM.settings.tonearmAnimation)
            Toggle("Artwork transitions", isOn: $settingsVM.settings.artworkTransitions)
            Toggle("Always reduce motion", isOn: $settingsVM.settings.alwaysReduceMotion)
        } header: {
            Text("Animation")
        } footer: {
            Text("NEEDLE always follows the iOS Reduce Motion setting. With it on, the record stays still and a small “Playing” badge shows instead.")
        }
    }

    private var spotifySection: some View {
        Section {
            HStack {
                Text("Status")
                Spacer()
                Text(playback.connectionStatus.shortLabel).foregroundColor(Theme.secondaryText)
            }
            Button("Reconnect") { playback.reconnect() }
            Button("Disconnect", role: .destructive) {
                playback.disconnect()
                dismiss()
            }
            Button("Open Spotify") { playback.openSpotify() }
        } header: {
            Text("Spotify")
        } footer: {
            Text("Spotify plays the audio; NEEDLE displays and controls it. Free accounts can't pick a specific track or skip freely, and apps in Spotify's Development Mode only work for accounts listed in the app's dashboard. When Spotify refuses something, NEEDLE tells you and keeps showing what Spotify is actually doing.")
        }
    }

    private var generalSection: some View {
        Section {
            LabeledContent("Version", value: settingsVM.appVersion)
            NavigationLink("Privacy") { InfoTextView(title: "Privacy", text: LegalText.privacy) }
            NavigationLink("Open-source notices") { InfoTextView(title: "Notices", text: LegalText.notices) }
            Button("Reset appearance settings", role: .destructive) { confirmReset = true }
        } header: {
            Text("General")
        }
    }
}

struct InfoTextView: View {
    let title: String
    let text: String

    var body: some View {
        ScrollView {
            Text(text)
                .font(.body)
                .foregroundColor(Theme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
        }
        .background(Theme.ink.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

enum LegalText {
    static let privacy = """
    NEEDLE does not collect, sell or share personal data, and contains no analytics or advertising.

    What stays on your iPhone: your display preferences, cached album artwork and the colors extracted from it, and a Spotify access token stored in the iOS Keychain. You can remove the token at any time with Disconnect.

    What is sent to Spotify: signing in happens inside the official Spotify app, so NEEDLE never sees your password. NEEDLE controls playback through Spotify's App Remote. If you use Search, your search text is sent to the Spotify Web API.

    NEEDLE never downloads, records or analyzes Spotify audio. The spinning record is a visual that reflects whether Spotify is playing; it is not driven by the audio signal.
    """

    static let notices = """
    Spotify iOS SDK
    © Spotify AB. Used under the Spotify Developer Terms and the SDK's license at github.com/spotify/ios-sdk.

    Spotify is a trademark of Spotify AB. NEEDLE is an independent app and is not affiliated with or endorsed by Spotify.

    SF Symbols are provided by Apple Inc. and used according to Apple's license.

    The NEEDLE name, icon and vinyl artwork are original to this project.
    """
}
