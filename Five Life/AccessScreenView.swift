//NEW DOC  AccessScreenView.swift
import AuthenticationServices
import StoreKit
import SwiftUI
import SwiftData

struct AccessScreenView: View {
    @ObservedObject var settings: SettingsStore
    @Binding var hasSeenAccessScreen: Bool
    @Environment(\.modelContext) private var modelContext
    @State private var currentCardIndex: Int = 0
    @StateObject private var appleSignInCoordinator = AppleSignInCoordinator()
    @State private var isSigningInWithApple: Bool = false
    @State private var isProcessingPayment: Bool = false
    @State private var paymentErrorMessage: String?
    private let maxContentWidth: CGFloat = 320
    private let cardHeight: CGFloat = 234
    private let cardFontSize: CGFloat = 18
    private let inAppPaymentProductID = "five_things_tip_1_euro"

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

    var body: some View {
        GeometryReader { geometry in
            ScrollView(showsIndicators: false) {
                VStack {
                    Spacer(minLength: 0)
                    VStack(spacing: 20) {
                        Image(accessIconName)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 96)
                            .accessibilityHidden(true)

                        TabView(selection: $currentCardIndex) {
                            ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                                cardView(text: card, index: index, width: geometry.size.width)
                                    .tag(index)
                            }
                        }
                        .frame(height: cardHeight, alignment: .top)
                        .tabViewStyle(.page(indexDisplayMode: .never))

                        pageIndicators

                        VStack(spacing: 12) {
                            Button {
                                Task {
                                    await handleAppleSignIn()
                                }
                            } label: {
                                Text(connectButtonTitle)
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .fill(Color.brandAccent)
                                    )
                                    .foregroundStyle(.white)
                            }
                            .disabled(isSigningInWithApple)

                            Button {
                                settings.appleIdConnected = false
                                hasSeenAccessScreen = true
                            } label: {
                                Text(continueButtonTitle)
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .fill(.white.opacity(0.85))
                                    )
                                    .foregroundStyle(Color.brandAccent)
                            }
                        }
                        .frame(maxWidth: maxContentWidth)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
                .padding(.horizontal, 30)
            }
            .background(Color.brandBackground.ignoresSafeArea())
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
        let cardWidth = min(width * 0.86, maxContentWidth)
        return Text(formattedCardText(text))
            .font(.system(size: cardFontSize))
            .foregroundStyle(.black)
            .multilineTextAlignment(.leading)
            .padding(24)
            .frame(width: cardWidth, height: cardHeight, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.white.opacity(0.92))
                    .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
            )
            .overlay(alignment: .bottomTrailing) {
                if index == 4 {
                    paymentButton
                        .padding(12)
                }
            }
            .padding(.horizontal, 8)
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
        return "Access_\(maxIndex)"
    }

    private var paymentButton: some View {
        Button {
            Task {
                await requestInAppPayment()
            }
        } label: {
            Image(systemName: "creditcard.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
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
        HStack(spacing: 8) {
            ForEach(0..<cards.count, id: \.self) { index in
                Circle()
                    .fill(index == currentCardIndex ? Color.brandAccent : Color.brandAccent.opacity(0.3))
                    .frame(width: 8, height: 8)
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
                _ = try verification.payloadValue
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            paymentErrorMessage = L10n.string("access.payment.failed", language: settings.language)
        }
    }
}
