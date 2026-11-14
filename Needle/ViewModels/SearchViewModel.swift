import Foundation

@MainActor
final class SearchViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case loaded(SearchResults)
        case failed(String)
    }

    @Published var query = ""
    @Published private(set) var state: State = .idle

    private let api: SpotifyWebAPI
    private var task: Task<Void, Never>?

    init(api: SpotifyWebAPI) {
        self.api = api
    }

    /// Debounced so typing doesn't flood the Web API (and its rate limits).
    func queryChanged() {
        task?.cancel()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            state = .idle
            return
        }
        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await self?.run(text)
        }
    }

    func retry() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        task?.cancel()
        task = Task { [weak self] in await self?.run(text) }
    }

    private func run(_ text: String) async {
        state = .loading
        do {
            let results = try await api.search(text)
            guard !Task.isCancelled else { return }
            state = .loaded(results)
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed(error.localizedDescription)
        }
    }
}
