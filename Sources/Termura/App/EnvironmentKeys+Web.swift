import SwiftUI

// MARK: - WebViewPool

private struct WebViewPoolKey: EnvironmentKey {
    #if DEBUG
    static let defaultValue: any WebViewPoolProtocol = MainActor.assumeIsolated { DebugWebViewPool() }
    #else
    static let defaultValue: any WebViewPoolProtocol = MainActor.assumeIsolated { WebViewPool() }
    #endif
}

extension EnvironmentValues {
    var webViewPool: any WebViewPoolProtocol {
        get { self[WebViewPoolKey.self] }
        set { self[WebViewPoolKey.self] = newValue }
    }
}

// MARK: - WebRendererBridge

private struct WebRendererBridgeKey: EnvironmentKey {
    #if DEBUG
    static let defaultValue: any WebRendererBridgeProtocol = MainActor.assumeIsolated {
        DebugWebRendererBridge()
    }
    #else
    static let defaultValue: any WebRendererBridgeProtocol = MainActor.assumeIsolated {
        WebRendererBridge()
    }
    #endif
}

extension EnvironmentValues {
    var webRendererBridge: any WebRendererBridgeProtocol {
        get { self[WebRendererBridgeKey.self] }
        set { self[WebRendererBridgeKey.self] = newValue }
    }
}
