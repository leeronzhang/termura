import Testing
@testable import Termura

@Suite("TerminalViewModel Prompt Detection")
struct PromptDetectionTests {

    // MARK: - Factory

    @MainActor
    private func makeViewModel(
        lines: [String] = []
    ) -> (TerminalViewModel, MockTerminalEngine, InputModeController) {
        let engine = MockTerminalEngine()
        engine.stubbedLinesNearCursor = lines
        let sessionStore = MockSessionStore()
        let sessionID = SessionID()
        let outputStore = OutputStore(sessionID: sessionID)
        let tokenService = TokenCountingService()
        let modeController = InputModeController()
        let coordinator = AgentCoordinator(sessionID: sessionID)
        let processor = OutputProcessor(
            sessionID: sessionID,
            outputStore: outputStore,
            tokenCountingService: tokenService
        )
        let services = SessionServices()
        let vm = TerminalViewModel(
            sessionID: sessionID,
            engine: engine,
            sessionStore: sessionStore,
            modeController: modeController,
            agentCoordinator: coordinator,
            outputProcessor: processor,
            sessionServices: services
        )
        return (vm, engine, modeController)
    }

    // MARK: - isShellPromptLine

    @Test("Trailing $ is shell prompt")
    @MainActor func shellPromptDollar() {
        let (vm, _, _) = makeViewModel()
        #expect(vm.isShellPromptLine("user@host ~ $"))
    }

    @Test("Trailing % is shell prompt (zsh)")
    @MainActor func shellPromptPercent() {
        let (vm, _, _) = makeViewModel()
        #expect(vm.isShellPromptLine("~ %"))
    }

    @Test("Trailing # is shell prompt (root)")
    @MainActor func shellPromptHash() {
        let (vm, _, _) = makeViewModel()
        #expect(vm.isShellPromptLine("root@host #"))
    }

    @Test("Bare $ is shell prompt")
    @MainActor func shellPromptBareDollar() {
        let (vm, _, _) = makeViewModel()
        #expect(vm.isShellPromptLine("$"))
    }

    @Test("Bare % is shell prompt")
    @MainActor func shellPromptBarePercent() {
        let (vm, _, _) = makeViewModel()
        #expect(vm.isShellPromptLine("%"))
    }

    @Test("Bare # is shell prompt")
    @MainActor func shellPromptBareHash() {
        let (vm, _, _) = makeViewModel()
        #expect(vm.isShellPromptLine("#"))
    }

    @Test("Empty string is not shell prompt")
    @MainActor func shellPromptEmpty() {
        let (vm, _, _) = makeViewModel()
        #expect(!vm.isShellPromptLine(""))
    }

    @Test("Regular output is not shell prompt")
    @MainActor func shellPromptRegularOutput() {
        let (vm, _, _) = makeViewModel()
        #expect(!vm.isShellPromptLine("some regular output"))
    }

    @Test("Dollar mid-text is not shell prompt")
    @MainActor func shellPromptDollarMidText() {
        let (vm, _, _) = makeViewModel()
        #expect(!vm.isShellPromptLine("echo $HOME"))
    }

    // MARK: - isAIPromptLine

    @Test("Bare > is AI prompt")
    @MainActor func aiPromptBareGreaterThan() {
        let (vm, _, _) = makeViewModel()
        #expect(vm.isAIPromptLine(">"))
    }

    @Test("> with trailing space is AI prompt")
    @MainActor func aiPromptGreaterThanSpace() {
        let (vm, _, _) = makeViewModel()
        #expect(vm.isAIPromptLine("> "))
    }

    @Test("U+276F is AI prompt")
    @MainActor func aiPromptHeavyAngle() {
        let (vm, _, _) = makeViewModel()
        #expect(vm.isAIPromptLine("\u{276F}"))
    }

    @Test("U+203A is AI prompt")
    @MainActor func aiPromptSingleAngle() {
        let (vm, _, _) = makeViewModel()
        #expect(vm.isAIPromptLine("\u{203A}"))
    }

    @Test("U+276F with trailing whitespace is AI prompt")
    @MainActor func aiPromptHeavyAngleSpace() {
        let (vm, _, _) = makeViewModel()
        #expect(vm.isAIPromptLine("\u{276F} "))
    }

    @Test("Empty string is not AI prompt")
    @MainActor func aiPromptEmpty() {
        let (vm, _, _) = makeViewModel()
        #expect(!vm.isAIPromptLine(""))
    }

    @Test(">> with text is not AI prompt")
    @MainActor func aiPromptDoubleGreater() {
        let (vm, _, _) = makeViewModel()
        #expect(!vm.isAIPromptLine(">> nested"))
    }

    @Test("> not at start is not AI prompt")
    @MainActor func aiPromptGreaterNotFirst() {
        let (vm, _, _) = makeViewModel()
        #expect(!vm.isAIPromptLine("text > redirect"))
    }

    // MARK: - detectPromptFromScreenBuffer

    @Test("AI prompt in buffer sets isInteractivePrompt true without switching mode")
    @MainActor func detectAIPromptSetsFlag() {
        let (vm, _, modeCtrl) = makeViewModel(lines: ["> "])
        modeCtrl.switchToPassthrough()
        vm.detectPromptFromScreenBuffer()
        #expect(vm.isInteractivePrompt == true)
        #expect(modeCtrl.mode == .passthrough)
    }

    @Test("Shell prompt on cursor line sets isInteractivePrompt false without switching mode")
    @MainActor func detectShellPromptSetsFlag() {
        let (vm, _, modeCtrl) = makeViewModel(lines: ["user@host ~ $"])
        modeCtrl.switchToPassthrough()
        vm.detectPromptFromScreenBuffer()
        #expect(vm.isInteractivePrompt == false)
        #expect(modeCtrl.mode == .passthrough)
    }

    @Test("Empty buffer does not switch mode")
    @MainActor func detectEmptyBufferNoSwitch() {
        let (vm, _, modeCtrl) = makeViewModel(lines: [])
        modeCtrl.switchToPassthrough()
        vm.detectPromptFromScreenBuffer()
        #expect(modeCtrl.mode == .passthrough)
    }

    @Test("Non-prompt lines do not switch mode")
    @MainActor func detectNonPromptNoSwitch() {
        let (vm, _, modeCtrl) = makeViewModel(lines: ["compiling...", "Build succeeded"])
        modeCtrl.switchToPassthrough()
        vm.detectPromptFromScreenBuffer()
        #expect(modeCtrl.mode == .passthrough)
    }
}
