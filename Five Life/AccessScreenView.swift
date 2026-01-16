//NEW DOC  AccessScreenView.swift
import AuthenticationServices
import StoreKit
import SwiftUI

struct AccessScreenView: View {
    @ObservedObject var settings: SettingsStore
    @Binding var hasSeenAccessScreen: Bool
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
        if settings.language == .dutch {
            return [
                "Uit meerdere onderzoeken blijkt dat dagelijks *5 dingen* opschrijven je geluksgevoel kan versterken en een positievere mindset kan bevorderen.",
                "In *Emmons & McCullough (2003)* scoorden deelnemers die (|tot vijf|) dankbare dingen noteerden hoger op welbevinden dan controlegroepen (|in één meting ≈ +12% van de schaalbreedte|).",
                "Ook in Yale’s |The Science of Well-Being| (|Laurie Santos|) komt een *dankbaarheidsdagboek* terug als één van de “rewirements”: laagdrempelige oefeningen die kunnen bijdragen aan meer welzijn.",
                "*Per dag:* \n \n• 30 minuten (|lichte|) *beweging*\n• 10 minuten *mediteren*\n• 5 *positieve* dingen opschrijven\n• 1 (|kleine|) *vriendelijke daad*\n• 1 |nieuwe| *sociale interactie*\n• 1 minuut bewust genieten",
                "Deze app is gebouwd met respect voor je *privacy* en maakt het makkelijker om *waardevolle momenten* in je dag op te schrijven. Een bijdrage van €1,- aan de ontwikkeling is volledig *optioneel*."
            ]
        }

        return [
            "Multiple studies suggest that writing down *5 things* each day can boost your sense of happiness and encourage a more positive mindset.",
            "In *Emmons & McCullough (2003)*, participants who wrote down (|up to five|) gratitude items scored higher on well-being than control groups (|in one measure ≈ +12% of the scale range|).",
            "Yale’s |The Science of Well-Being| (|Laurie Santos|) also includes a *gratitude journal* as one of its “rewirements”: low-barrier exercises that can support well-being.",
            "*Daily:* \n \n• 30 minutes of (|light|) *movement*\n• 10 minutes of *meditation*\n• Write down 5 *positive* things\n• 1 (|small|) *act of kindness*\n• 1 |new| *social interaction*\n• 1 minute of mindful enjoyment",
            "This app is built with respect for your *privacy* and makes it easier to write down *valuable moments* from your day. A €1 contribution to support development is completely *optional*."
        ]
    }

    private var connectButtonTitle: String {
        settings.language == .dutch ? "Connect met je Apple ID" : "Connect with your Apple ID"
    }

    private var continueButtonTitle: String {
        settings.language == .dutch ? "Gebruik de app zonder…" : "Use the app without…"
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView(showsIndicators: false) {
                VStack {
                    Spacer(minLength: 0)
                    VStack(spacing: 20) {
                        Image("NoBackground")
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
                                    .foregroundStyle(.black)
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
            .alert("In-App Payment", isPresented: Binding(
                get: { paymentErrorMessage != nil },
                set: { if !$0 { paymentErrorMessage = nil } }
            )) {
                Button(settings.language == .dutch ? "Oké" : "OK", role: .cancel) {}
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
        let markdown = text
            .replacingOccurrences(of: "\n", with: "  \n")
            .replacingOccurrences(of: "|", with: "_")
            .replacingOccurrences(of: "*", with: "**")
        return (try? AttributedString(markdown: markdown)) ?? AttributedString(text)
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
        .accessibilityLabel(settings.language == .dutch
            ? "Doe een bijdrage van één euro"
            : "Make a one euro contribution")
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
        .accessibilityLabel(settings.language == .dutch
            ? "Pagina \(currentCardIndex + 1) van \(cards.count)"
            : "Page \(currentCardIndex + 1) of \(cards.count)")
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
                paymentErrorMessage = settings.language == .dutch
                    ? "Het product is nog niet beschikbaar."
                    : "The product is not available yet."
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
            paymentErrorMessage = settings.language == .dutch
                ? "Betaling mislukt. Probeer het later opnieuw."
                : "Payment failed. Please try again later."
        }
    }
}
