import SwiftUI
import AuthenticationServices

struct SignInView: View {
    let viewModel: AuthenticationViewModel

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // App name
            Text("CashOut")
                .font(.largeTitle)
                .fontWeight(.bold)

            // Sign in with Apple button — Apple's official SwiftUI component
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                switch result {
                case .success(let authorization):
                    if let credential = authorization.credential
                        as? ASAuthorizationAppleIDCredential {
                        viewModel.completeSignIn(
                            userID: credential.user,
                            fullName: credential.fullName,
                            email: credential.email
                        )
                    } else {
                        viewModel.failSignIn(
                            cancelled: false,
                            message: "Unsupported credential type"
                        )
                    }
                case .failure(let error):
                    let cancelled = (error as? ASAuthorizationError)?.code == .canceled
                    viewModel.failSignIn(
                        cancelled: cancelled,
                        message: error.localizedDescription
                    )
                }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 50)
            .frame(maxWidth: 280)

            // Explanation / error text
            Text(viewModel.errorMessage ?? "Sign in to sync expenses with your partner")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .accessibilityLabel(
                    viewModel.errorMessage ?? "Sign in to sync expenses with your partner"
                )

            Spacer()
        }
    }
}

#Preview {
    SignInView(viewModel: AuthenticationViewModel())
}
