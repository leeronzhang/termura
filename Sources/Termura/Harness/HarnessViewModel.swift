import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "HarnessViewModel")

/// ViewModel for the Harness management sidebar.
/// Drives rule file browsing, version history, and corruption alerts.
@MainActor
final class HarnessViewModel: ObservableObject {
    // MARK: - Published

    @Published private(set) var ruleFiles: [RuleFileRecord] = []
    @Published private(set) var selectedSections: [RuleSection] = []
    @Published private(set) var corruptionResults: [CorruptionResult] = []
    @Published private(set) var versionHistory: [RuleFileRecord] = []
    @Published var selectedFilePath: String?
    @Published private(set) var isScanning = false
    /// User-visible error message from the last failed operation.
    @Published var errorMessage: String?

    // MARK: - Dependencies

    private let repository: any RuleFileRepositoryProtocol
    private let corruptionDetector: CorruptionDetector
    private let projectRoot: String

    init(
        repository: any RuleFileRepositoryProtocol,
        projectRoot: String
    ) {
        self.repository = repository
        corruptionDetector = CorruptionDetector()
        self.projectRoot = projectRoot
    }

    // MARK: - Actions

    func loadRuleFiles() async {
        let paths = RuleFileParser.findRuleFiles(in: projectRoot)
        var records: [RuleFileRecord] = []

        for path in paths {
            do {
                let (record, _) = try RuleFileParser.loadAndParse(at: path)
                records.append(record)
                // Check if content changed since last saved version
                try await snapshotIfChanged(record)
            } catch {
                errorMessage = "Failed to load rule file \(path): \(error.localizedDescription)"
                logger.error("Failed to load rule file \(path): \(error)")
            }
        }
        ruleFiles = records
    }

    func selectFile(_ path: String) async {
        selectedFilePath = path
        do {
            let (_, sections) = try RuleFileParser.loadAndParse(at: path)
            selectedSections = sections
            let history = try await repository.fetchHistory(for: path)
            versionHistory = history
            errorMessage = nil
        } catch {
            errorMessage = "Failed to load rule file: \(error.localizedDescription)"
            logger.error("Failed to select rule file: \(error)")
        }
    }

    func runCorruptionScan() async {
        guard let path = selectedFilePath else { return }
        isScanning = true
        defer { isScanning = false }

        do {
            let (_, sections) = try RuleFileParser.loadAndParse(at: path)
            let detector = corruptionDetector
            let results = await detector.scan(sections: sections, projectRoot: projectRoot)
            corruptionResults = results
            errorMessage = nil
            logger.info("Corruption scan: \(results.count) issues found")
        } catch {
            errorMessage = "Corruption scan failed: \(error.localizedDescription)"
            logger.error("Corruption scan failed: \(error)")
        }
    }

    // MARK: - Private

    private func snapshotIfChanged(_ record: RuleFileRecord) async throws {
        let latest = try await repository.fetchLatest(for: record.filePath)
        if let existing = latest, existing.contentHash == record.contentHash {
            return // No change
        }
        let nextVersion = (latest?.version ?? 0) + 1
        let versioned = RuleFileRecord(
            filePath: record.filePath,
            content: record.content,
            contentHash: record.contentHash,
            version: nextVersion
        )
        try await repository.save(versioned)
    }
}
