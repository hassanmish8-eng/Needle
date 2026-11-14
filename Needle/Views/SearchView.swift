import SwiftUI

@MainActor
struct SearchView: View {
    @EnvironmentObject private var search: SearchViewModel
    @EnvironmentObject private var playback: PlaybackViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                content
                if let banner = playback.banner {
                    Text(banner.message)
                        .font(.footnote)
                        .foregroundColor(Theme.primaryText)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(white: 0.16))
                }
            }
            .background(Theme.ink.ignoresSafeArea())
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .searchable(text: $search.query,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Songs, albums, artists")
            .onChange(of: search.query) { _ in search.queryChanged() }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var content: some View {
        switch search.state {
        case .idle:
            message("Search Spotify for something to put on the turntable.",
                    detail: playback.isLive ? nil : "Reconnect to Spotify to play results.")
        case .loading:
            ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let text):
            VStack(spacing: 12) {
                message(text, detail: nil)
                Button("Try again") { search.retry() }.buttonStyle(.bordered).tint(.white)
            }
        case .loaded(let results):
            if results.isEmpty {
                message("No results.", detail: nil)
            } else {
                resultList(results)
            }
        }
    }

    private func message(_ text: String, detail: String?) -> some View {
        VStack(spacing: 8) {
            Text(text).font(.subheadline).foregroundColor(Theme.secondaryText).multilineTextAlignment(.center)
            if let detail {
                Text(detail).font(.footnote).foregroundColor(Theme.tertiaryText).multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func resultList(_ results: SearchResults) -> some View {
        List {
            if !results.tracks.isEmpty {
                Section("Songs") {
                    ForEach(results.tracks) { track in
                        ResultRow(title: track.name, subtitle: "\(track.artists) · \(track.album)", imageURL: track.imageURL) { play(track.uri) }
                    }
                }
            }
            if !results.albums.isEmpty {
                Section("Albums") {
                    ForEach(results.albums) { album in
                        ResultRow(title: album.name, subtitle: album.artists, imageURL: album.imageURL) { play(album.uri) }
                    }
                }
            }
            if !results.artists.isEmpty {
                Section("Artists") {
                    ForEach(results.artists) { artist in
                        ResultRow(title: artist.name, subtitle: "Artist", imageURL: artist.imageURL, round: true) { play(artist.uri) }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func play(_ uri: String) {
        guard !uri.isEmpty else { return }
        Task {
            if await playback.play(uri: uri) { dismiss() }
        }
    }
}

struct ResultRow: View {
    let title: String
    let subtitle: String
    let imageURL: URL?
    var round = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                AsyncImage(url: imageURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.white.opacity(0.08)
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: round ? 24 : 6, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body).foregroundColor(Theme.primaryText).lineLimit(1)
                    Text(subtitle).font(.footnote).foregroundColor(Theme.secondaryText).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Plays it in Spotify")
    }
}
