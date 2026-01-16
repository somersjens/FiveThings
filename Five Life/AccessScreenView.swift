//NEW DOC  AccessScreenView.swift
import AuthenticationServices
import SwiftUI

struct AccessScreenView: View {
    @ObservedObject var settings: SettingsStore
    @Binding var hasSeenAccessScreen: Bool
    @State private var currentCardIndex: Int = 0
    @StateObject private var appleSignInCoordinator = AppleSignInCoordinator()
    @State private var isSigningInWithApple: Bool = false

    private var cards: [String] {
        if settings.language == .dutch {
            return [
                "Uit meerdere onderzoeken blijkt dat dagelijks 5 dingen opschrijven je geluksgevoel kan versterken en een positievere mindset kan bevorderen.",
                "In Emmons & McCullough (2003) scoorden deelnemers die (tot vijf) dankbare dingen noteerden hoger op welbevinden dan controlegroepen (in één meting ≈ +12% van de schaalbreedte).",
                "Ook in Yale’s The Science of Well-Being (Laurie Santos) komt een dankbaarheidsdagboek terug als één van de “rewirements”: laagdrempelige oefeningen die kunnen bijdragen aan meer welzijn.",
                """
                Per dag:
                • 30 minuten (lichte) beweging
                • 10 minuten mediteren
                • 5 dingen opschrijven waar je dankbaar voor bent
                • 1 (kleine) vriendelijke daad voor iemand
                • 1 sociale interactie met een nieuw persoon
                • 1 minuut bewust genieten van één moment
                """,
                "Deze app is gebouwd met respect voor je privacy en maakt het makkelijker om waardevolle momenten in je dag op te schrijven. Een bijdrage van €1,- aan de ontwikkeling is volledig optioneel."
            ]
        }

        return [
            "Multiple studies suggest that writing down 5 things each day can boost your sense of happiness and encourage a more positive mindset.",
            "In Emmons & McCullough (2003), participants who wrote down (up to five) gratitude items scored higher on well-being than control groups (in one measure ≈ +12% of the scale range).",
            "Yale’s The Science of Well-Being (Laurie Santos) also includes a gratitude journal as one of its “rewirements”: low-barrier exercises that can support well-being.",
            """
            Daily:
            • 30 minutes of (light) movement
            • 10 minutes of meditation
            • Write down 5 things you’re grateful for
            • 1 (small) random act of kindness
            • 1 social interaction with a new person
            • 1 minute of mindful enjoyment of one moment
            """,
            "This app is built with respect for your privacy and makes it easier to write down valuable moments from your day. A €1 contribution to support development is completely optional."
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
                VStack(spacing: 20) {
                    Image("NoBackground")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 96)
                        .padding(.top, 24)
                        .accessibilityHidden(true)

                    TabView(selection: $currentCardIndex) {
                        ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                            cardView(text: card, width: geometry.size.width)
                                .tag(index)
                        }
                    }
                    .frame(height: 300)
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
                    .frame(maxWidth: 320)
                    .padding(.bottom, 24)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
            }
            .background(Color.brandBackground.ignoresSafeArea())
        }
    }

    private func cardView(text: String, width: CGFloat) -> some View {
        let cardWidth = min(width * 0.86, 360)
        return Text(text)
            .font(.body)
            .foregroundStyle(.black)
            .multilineTextAlignment(.leading)
            .frame(width: cardWidth, height: 260)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.white.opacity(0.92))
                    .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
            )
            .padding(.horizontal, 8)
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
}
