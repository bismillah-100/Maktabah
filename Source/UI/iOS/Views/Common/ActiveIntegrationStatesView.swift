import SwiftUI

struct ActiveIntegrationStatesView: View {
    @Environment(iOSNavigationManager.self) private var navigationManager: iOSNavigationManager

    var body: some View {
        ForEach(navigationManager.activeIntegrationStates) { state in
            iOSBookDownloadProgressView(
                state: state,
                onConfirm: { navigationManager.confirmPendingBookIntegration(state: state) },
                onCancel: { navigationManager.cancelPendingBookIntegration(state: state) }
            )
            .background(.ultraThinMaterial)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

struct ActiveIntegrationStatesModifier: ViewModifier {
    @Environment(iOSNavigationManager.self) private var navigationManager: iOSNavigationManager

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !navigationManager.activeIntegrationStates.isEmpty {
                    VStack(spacing: 0) {
                        ActiveIntegrationStatesView()
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.interpolatingSpring(stiffness: 300, damping: 20), value: navigationManager.activeIntegrationStates.count)
    }
}

extension View {
    func withActiveIntegrationStates() -> some View {
        modifier(ActiveIntegrationStatesModifier())
    }
}
