import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "SearchViewModel")

@Observable
@MainActor
final class SearchViewModel {
    var query: String = "" {
        didSet {
            guard query != oldValue else { return }
            scheduleSearch(for: query)
        }
    }

    private(set) var results: SearchResults = .empty
    private(set) var isSearching = false
    /// User-visible error message from the last failed search.
    var errorMessage: String?

    private let searchService: any SearchServiceProtocol
    private let clock: any AppClock
    private let debounceDuration: Duration
    @ObservationIgnored private var debounceTask: Task<Void, Never>?

    init(
        searchService: any SearchServiceProtocol,
        clock: any AppClock = LiveClock(),
        debounceDuration: Duration = .seconds(AppConfig.Runtime.searchDebounceSeconds)
    ) {
        self.searchService = searchService
        self.clock = clock
        self.debounceDuration = debounceDuration
    }

    deinit {
        debounceTask?.cancel()
    }

    private func scheduleSearch(for queryText: String) {
        debounceTask?.cancel()
        guard queryText.count >= AppConfig.Search.minQueryLength else {
            results = .empty
            isSearching = false
            errorMessage = nil
            return
        }
        let service = searchService
        let clock = clock
        let debounce = debounceDuration
        debounceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await clock.sleep(for: debounce)
            } catch is CancellationError {
                // CancellationError is expected — a newer query superseded this search.
                return
            } catch {
                logger.warning("Search debounce interrupted: \(error.localizedDescription)")
                return
            }
            guard !Task.isCancelled, query == queryText else { return }
            isSearching = true
            do {
                let found = try await service.search(query: queryText)
                guard !Task.isCancelled, query == queryText else { return }
                results = found
                errorMessage = nil
            } catch {
                guard !Task.isCancelled, query == queryText else { return }
                errorMessage = "Search failed: \(error.localizedDescription)"
                logger.error("Search failed: \(error)")
            }
            isSearching = false
        }
    }

    /// Await the currently scheduled debounce/search task.
    /// Used by tests to wait for the latest query to settle without wall-clock sleeps.
    func waitForIdle() async {
        await debounceTask?.value
    }
}
