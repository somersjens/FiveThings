//NEW DOC  AccessScreenView.swift
import AuthenticationServices
import StoreKit
import SwiftUI
import SwiftData

struct AccessScreenView: View {
    @ObservedObject var settings: SettingsStore
    @Binding var hasSeenAccessScreen: Bool
    @Binding var showsReturnToMainMenuOnly: Bool
    @Environment(\.modelContext) private var modelContext
    @Environment(\.responsiveTypeScale) private var responsiveTypeScale
    @State private var currentCardIndex: Int = 0
    @StateObject private var appleSignInCoordinator = AppleSignInCoordinator()
    @State private var isSigningInWithApple: Bool = false
    @State private var isProcessingPayment: Bool = false
    @State private var showConfetti: Bool = false
    @State private var paymentErrorMessage: String?
    @State private var transactionUpdatesTask: Task<Void, Never>?
    @ScaledMetric(relativeTo: .body) private var maxContentWidth: CGFloat = 320
    @ScaledMetric(relativeTo: .body) private var cardHeight: CGFloat = 234
    @ScaledMetric(relativeTo: .body) private var cardFontSize: CGFloat = 18
    @ScaledMetric(relativeTo: .headline) private var paymentIconSize: CGFloat = 16
    @ScaledMetric(relativeTo: .headline) private var paymentButtonSize: CGFloat = 32
    private let accessScale: CGFloat = 1.1
    private let inAppPaymentProductID = "20012026"

    private var cards: [String] {
        [
            L10n.string("access.card.1", language: settings.language),
            L10n.string("access.card.2", language: settings.language),
            L10n.string("access.card.3", language: settings.language),
            L10n.string("access.card.4", language: settings.language),
            L10n.string("access.card.5", language: settings.language)
        ]
    }

    private var connectButtonTitle: String {
        L10n.string("access.connect.apple", language: settings.language)
    }

    private var continueButtonTitle: String {
        L10n.string("access.continue.without", language: settings.language)
    }

    private var backToMainMenuButtonTitle: String {
        L10n.string("access.back.main.menu", language: settings.language)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ScrollView(showsIndicators: false) {
                    VStack {
                        Spacer(minLength: 0)
                        VStack(spacing: 20 * accessScale) {
                            Image(accessIconName)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 96 * accessScale)
                                .accessibilityHidden(true)

                            TabView(selection: $currentCardIndex) {
                                ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                                    cardView(text: card, index: index, width: geometry.size.width)
                                        .tag(index)
                                }
                            }
                            .frame(height: cardHeight * responsiveTypeScale * accessScale, alignment: .top)
                            .tabViewStyle(.page(indexDisplayMode: .never))

                            pageIndicators

                            VStack(spacing: 12 * accessScale) {
                                if showsReturnToMainMenuOnly {
                                    Button {
                                        hasSeenAccessScreen = true
                                        showsReturnToMainMenuOnly = false
                                    } label: {
                                        Text(backToMainMenuButtonTitle)
                                            .font(.headline)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12 * accessScale)
                                            .background(
                                                RoundedRectangle(cornerRadius: 16 * accessScale, style: .continuous)
                                                    .fill(Color.brandAccent)
                                            )
                                            .foregroundStyle(.white)
                                    }
                                } else {
                                    Button {
                                        Task {
                                            await handleAppleSignIn()
                                        }
                                    } label: {
                                        Text(connectButtonTitle)
                                            .font(.headline)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12 * accessScale)
                                            .background(
                                                RoundedRectangle(cornerRadius: 16 * accessScale, style: .continuous)
                                                    .fill(Color.brandAccent)
                                            )
                                            .foregroundStyle(.white)
                                    }
                                    .disabled(isSigningInWithApple)

                                    Button {
                                        settings.appleIdConnected = false
                                        hasSeenAccessScreen = true
                                        showsReturnToMainMenuOnly = false
                                    } label: {
                                        Text(continueButtonTitle)
                                            .font(.headline)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12 * accessScale)
                                            .background(
                                                RoundedRectangle(cornerRadius: 16 * accessScale, style: .continuous)
                                                    .fill(Color.brandSecondarySurface)
                                            )
                                            .foregroundStyle(Color.brandAccent)
                                    }
                                }
                            }
                            .frame(maxWidth: maxContentWidth * accessScale)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geometry.size.height)
                    .padding(.horizontal, 30 * accessScale)
                }
                if showConfetti {
                    CloverConfettiView()
                        .transition(.opacity)
                }
            }
            .background(Color.brandBackground.ignoresSafeArea())
            .task {
                await refreshPurchaseStatus()
                startTransactionUpdates()
            }
            .onDisappear {
                transactionUpdatesTask?.cancel()
                transactionUpdatesTask = nil
            }
            .alert(L10n.string("access.payment.title", language: settings.language), isPresented: Binding(
                get: { paymentErrorMessage != nil },
                set: { if !$0 { paymentErrorMessage = nil } }
            )) {
                Button(L10n.string("common.ok", language: settings.language), role: .cancel) {}
            } message: {
                Text(paymentErrorMessage ?? "")
            }
        }
    }

    private func cardView(text: String, index: Int, width: CGFloat) -> some View {
        let cardWidth = min(width * 0.86 * accessScale, maxContentWidth * responsiveTypeScale * accessScale)
        return Text(formattedCardText(text))
            .font(.system(size: cardFontSize * responsiveTypeScale))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .padding(24 * accessScale)
            .frame(width: cardWidth,
                   height: cardHeight * responsiveTypeScale * accessScale,
                   alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 20 * accessScale, style: .continuous)
                    .fill(Color.brandSurface)
                    .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
            )
            .overlay(alignment: .bottomTrailing) {
                if index == 4 {
                    paymentButton
                        .padding(12 * accessScale)
                }
            }
            .padding(.horizontal, 8 * accessScale)
    }

    private func formattedCardText(_ text: String) -> AttributedString {
        let paragraphs = text.components(separatedBy: "\n\n")
        var result = AttributedString()

        for (index, paragraph) in paragraphs.enumerated() {
            let markdown = paragraph
                .replacingOccurrences(of: "\n", with: "  \n")
                .replacingOccurrences(of: "|", with: "_")
                .replacingOccurrences(of: "*", with: "**")
            var attributed = (try? AttributedString(markdown: markdown)) ?? AttributedString(paragraph)
            for run in attributed.runs {
                if run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
                    attributed[run.range].foregroundColor = Color.brandAccent
                }
            }

            if index > 0 {
                result.append(AttributedString("\n\n"))
            }

            result.append(attributed)
        }

        return result
    }

    private var accessIconName: String {
        let maxIndex = min(currentCardIndex + 1, 5)
        if maxIndex == 5, settings.donationPaid {
            return "heart_clover"
        }
        return "Access_\(maxIndex)"
    }

    private var paymentButton: some View {
        Button {
            Task {
                await requestInAppPayment()
            }
        } label: {
            Image(systemName: "creditcard.fill")
                .font(.system(size: paymentIconSize * responsiveTypeScale * accessScale, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: paymentButtonSize * responsiveTypeScale * accessScale,
                       height: paymentButtonSize * responsiveTypeScale * accessScale)
                .background(
                    Circle()
                        .fill(Color.brandAccent)
                )
                .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)
        }
        .disabled(isProcessingPayment)
        .accessibilityLabel(L10n.string("access.payment.contribute", language: settings.language))
    }

    private var pageIndicators: some View {
        HStack(spacing: 8 * accessScale) {
            ForEach(0..<cards.count, id: \.self) { index in
                Circle()
                    .fill(index == currentCardIndex ? Color.brandAccent : Color.brandAccent.opacity(0.3))
                    .frame(width: 8 * accessScale, height: 8 * accessScale)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.string("access.page.indicator",
                                         language: settings.language,
                                         currentCardIndex + 1,
                                         cards.count))
    }

    @MainActor
    private func handleAppleSignIn() async {
        guard !isSigningInWithApple else { return }
        isSigningInWithApple = true
        defer { isSigningInWithApple = false }

        do {
            let credential = try await appleSignInCoordinator.signIn()
            settings.appleUserIdentifier = credential.user
            settings.appleIdConnected = true
            await AppleSyncManager.shared.reconcileAfterSignIn(modelContext: modelContext,
                                                               settings: settings,
                                                               context: .initialConnect)
            hasSeenAccessScreen = true
            showsReturnToMainMenuOnly = false
        } catch {
            settings.appleIdConnected = false
        }
    }

    @MainActor
    private func requestInAppPayment() async {
        guard !isProcessingPayment else { return }
        isProcessingPayment = true
        defer { isProcessingPayment = false }

        do {
            let products = try await Product.products(for: [inAppPaymentProductID])
            guard let product = products.first else {
                paymentErrorMessage = L10n.string("access.payment.unavailable", language: settings.language)
                return
            }

            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try verification.payloadValue
                await transaction.finish()
                handlePaymentSuccess()
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            paymentErrorMessage = L10n.string("access.payment.failed", language: settings.language)
        }
    }

    private func handlePaymentSuccess() {
        settings.donationPaid = true
        withAnimation(.easeInOut(duration: 0.25)) {
            showConfetti = true
        }

        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showConfetti = false
                }
            }
        }
    }

    @MainActor
    private func refreshPurchaseStatus() async {
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement else { continue }
            if transaction.productID == inAppPaymentProductID {
                settings.donationPaid = true
                break
            }
        }
    }

    private func startTransactionUpdates() {
        transactionUpdatesTask?.cancel()
        transactionUpdatesTask = Task {
            for await update in Transaction.updates {
                guard case .verified(let transaction) = update else { continue }
                if transaction.productID == inAppPaymentProductID {
                    await MainActor.run {
                        settings.donationPaid = true
                    }
                    await transaction.finish()
                }
            }
        }
    }
}
