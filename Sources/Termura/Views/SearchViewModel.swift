import Combine
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "SearchViewModel")

@Observable
@MainActor
final class SearchViewModel {
    var query: String = "" {
        didSet {
            guard query != oldValue else { return }
            querySubject.send(query)
        }
    }
    private(set) var results: SearchResults = .empty
    private(set) var isSearching = false
    /// User-visible error message from the last failed search.
    var errorMessage: String?

    private let searchService: any SearchServiceProtocol
    // PassthroughSubject feeds the Combine debounce pipeline.
    // @ObservationIgnored: mutation here must not trigger SwiftUI re-renders.
    @ObservationIgnored private let querySubject = PassthroughSubject<String, Never>()
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    init(searchService: any SearchServiceProtocol) {
        self.searchService = searchService
        setupDebounce()
    }

    deinit {
        searchTask?.cancel()
        // cancellables: AnyCancellable auto-cancels on deallocation; removeAll() is redundant
        // and illegal here since Set<AnyCancellable> is non-Sendable in nonisolated deinit.
    }

    private func setupDebounce() {
        querySubject
            .debounce(
                for: .seconds(AppConfig.Runtime.searchDebounceSeconds),
                scheduler: RunLoop.main
            )
            .removeDuplicates()
            .sink { [weak self] queryText in
                guard let self else { return }
                searchTask?.cancel()
                guard queryText.count >= AppConfig.Search.minQueryLength else {
                    results = .empty
                    isSearching = false
                    return
                }
                isSearching = true
                searchTask = Task { @MainActor [weak self] in
                    guard let self else { return }
                    do {
                        let found = try await searchService.search(query: queryText)
                        guard !Task.isCancelled else { return }
                        results = found
                        errorMessage = nil
                    } catch {
                        guard !Task.isCancelled else { return }
                        errorMessage = "Search failed: \(error.localizedDescription)"
                        logger.error("Search failed: \(error)")
                    }
                    isSearching = false
                }
            }
            .store(in: &cancellables)
    }
}
