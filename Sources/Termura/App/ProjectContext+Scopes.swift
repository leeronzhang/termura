import Foundation

extension ProjectContext {
    struct ScopeSupplements {
        let tokenCountingService: any TokenCountingServiceProtocol
        let metricsCollector: any MetricsCollectorProtocol
        let notificationService: (any NotificationServiceProtocol)?
        let projectVM: ProjectViewModel
    }

    struct ProjectScopes {
        let session: SessionScope
        let data: DataScope
        let project: ProjectScope
        let viewState: SessionViewStateManager
    }

    static func makeScopes(
        repos: ProjectRepositories,
        services: ProjectServices,
        supplements: ScopeSupplements
    ) -> ProjectScopes {
        let session = SessionScope(
            store: services.sessionStore, engines: services.engineStore, agentStates: services.agentState
        )
        let data = DataScope(
            searchService: services.search, vectorSearchService: nil,
            ruleFileRepository: repos.rule, sessionMessageRepository: repos.message
        )
        let viewState = SessionViewStateManager(SessionViewStateManager.Components(
            commandRouter: services.router,
            sessionStore: services.sessionStore,
            tokenCountingService: supplements.tokenCountingService,
            agentStateStore: services.agentState,
            contextInjectionService: services.injection,
            sessionHandoffService: services.handoff,
            metricsCollector: supplements.metricsCollector,
            notificationService: supplements.notificationService
        ))
        return ProjectScopes(
            session: session, data: data,
            project: ProjectScope(
                gitService: services.git,
                viewModel: supplements.projectVM,
                diagnosticsStore: DiagnosticsStore(
                    commandRouter: services.router,
                    projectRoot: supplements.projectVM.projectRootPath
                )
            ),
            viewState: viewState
        )
    }
}
