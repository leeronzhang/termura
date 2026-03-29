// HARNESS_ENABLED=1 is set in project.yml for the private (paid) build.
// When that flag is absent, this stub compiles in its place.
// The private package provides the real HarnessViewModel with full functionality.

#if !HARNESS_ENABLED
import Foundation

// open-core base: subclassed by termura-harness, kept ObservableObject for binary compatibility.
// Must only be injected via @ObservedObject or @StateObject — never via @Environment.
// Remove this exception once termura-harness migrates to @Observable.
@MainActor
open class HarnessViewModel: ObservableObject {
    @Published var ruleFiles: [RuleFileRecord] = []
    @Published var selectedSections: [RuleSection] = []
    @Published var corruptionResults: [CorruptionResult] = []
    @Published var versionHistory: [RuleFileRecord] = []
    @Published var selectedFilePath: String?
    @Published var isScanning = false
    @Published var errorMessage: String?

    init(repository: any RuleFileRepositoryProtocol, projectRoot: String) {}

    open func loadRuleFiles() async {}
    open func selectFile(_ path: String) async {}
    open func runCorruptionScan() async {}
}
#endif
