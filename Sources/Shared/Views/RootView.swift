import SwiftUI

/// Login gate.
struct RootView: View {
    @EnvironmentObject private var auth: AuthStore

    var body: some View {
        ZStack {
            switch auth.state {
            case .restoring:
                ProgressView("Signing in…").frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loggedOut:
                LoginView().transition(.opacity)
            case .loggedIn:
                HomeView(auth: auth).transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: auth.state)
    }
}
