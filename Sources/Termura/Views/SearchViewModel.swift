import Combine
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "SearchViewModel")

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query: String = ""
    @Published private(set) var results: SearchResults = .empty
    @Published private(set) var isSearching = false

    private let searchService: SearchService
    private var cancellables = Set<AnyCancellable>()
    private var searchTask: Task<Void, Never>?

    init(searchService: SearchService) {
        self.searchService = searchService
        setupDebounce()
    }

    private func setupDebounce() {
        $query
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
                    } catch {
                        logger.error("Search failed: \(error)")
                    }
                    isSearching = false
                }
            }
            .store(in: &cancellables)
    }
}
