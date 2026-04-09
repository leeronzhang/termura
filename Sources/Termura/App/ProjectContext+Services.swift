import Foundation

extension ProjectContext {
    struct ProjectServices {
        let engineStore: TerminalEngineStore
        let sessionStore: SessionStore
        let agentState: AgentStateStore
        let search: any SearchServiceProtocol
        let archive: SessionArchiveService
        let handoff: any SessionHandoffServiceProtocol
        let injection: any ContextInjectionServiceProtocol
        let codifier: ExperienceCodifier
        let git: any GitServiceProtocol
        let router: CommandRouter
    }

    static func makeServices(
        repos: ProjectRepositories, projectURL: URL,
        engineFactory: any TerminalEngineFactory,
        metricsCollector: any MetricsCollectorProtocol
    ) -> ProjectServices {
        let eng = TerminalEngineStore(factory: engineFactory)
        let hoff = SessionHandoffService(
            messageRepo: repos.message, harnessEventRepo: repos.harness
        )
        return ProjectServices(
            engineStore: eng,
            sessionStore: SessionStore(
                engineStore: eng, projectRoot: projectURL.path,
                repository: repos.session, metricsCollector: metricsCollector
            ),
            agentState: AgentStateStore(),
            search: SearchService(
                sessionRepository: repos.session, noteRepository: repos.note,
                metrics: metricsCollector
            ),
            archive: SessionArchiveService(repository: repos.session),
            handoff: hoff,
            injection: ContextInjectionService(handoffService: hoff),
            codifier: ExperienceCodifier(harnessEventRepo: repos.harness),
            git: GitService(), router: CommandRouter()
        )
    }
}
