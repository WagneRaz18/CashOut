import SwiftUI
import AuthenticationServices

struct SignInView: View {
    let viewModel: AuthenticationViewModel

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // App icon
            Image(systemName: "creditcard.fill")
                .font(.system(size: 48))
                .foregroundStyle(SemanticColor.primary)

            // App name
            Text("CashOut")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(SemanticColor.onSurface)

            Text("The Silent Steward")
                .font(.subheadline)
                .foregroundStyle(SemanticColor.onSurfaceVariant)

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
            .signInWithAppleButtonStyle(.white)
            .frame(height: 50)
            .frame(maxWidth: 280)

            // Explanation / error text
            Text(viewModel.errorMessage ?? "Sign in to sync expenses with your partner")
                .font(.subheadline)
                .foregroundStyle(viewModel.errorMessage != nil ? SemanticColor.error : SemanticColor.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .accessibilityLabel(
                    viewModel.errorMessage ?? "Sign in to sync expenses with your partner"
                )

            Spacer()

            Text("created by WagneRaz")
                .font(.caption2)
                .foregroundStyle(SemanticColor.onSurfaceVariant.opacity(0.6))
                .padding(.bottom, Spacing.md)
        }
        .background(Surface.base)
    }
}

#Preview {
    SignInView(viewModel: AuthenticationViewModel())
}
