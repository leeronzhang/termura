// HARNESS_ENABLED=1 is set in project.yml for the private (paid) build.
// When that flag is absent, this stub compiles in its place.
// The private package provides the real HarnessViewModel with full functionality.

#if !HARNESS_ENABLED
import Foundation

@MainActor
open class HarnessViewModel: ObservableObject {
    @Published public var ruleFiles: [RuleFileRecord] = []
    @Published public var selectedSections: [RuleSection] = []
    @Published public var corruptionResults: [CorruptionResult] = []
    @Published public var versionHistory: [RuleFileRecord] = []
    @Published public var selectedFilePath: String?
    @Published public var isScanning = false
    @Published public var errorMessage: String?

    public init(repository: any RuleFileRepositoryProtocol, projectRoot: String) {}

    open func loadRuleFiles() async {}
    open func selectFile(_ path: String) async {}
    open func runCorruptionScan() async {}
}
#endif
