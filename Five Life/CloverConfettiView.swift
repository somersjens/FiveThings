//NEW DOC  CloverConfettiView.swift
import SwiftUI

struct CloverConfettiView: View {
    private struct Piece: Identifiable {
        let id = UUID()
        let xPosition: CGFloat
        let size: CGFloat
        let startRotation: Angle
        let endRotation: Angle
        let duration: Double
        let delay: Double
        let startOffset: CGFloat
        let endOffset: CGFloat
        let opacity: Double
    }

    private let pieces: [Piece]
    @State private var animate = false

    init(pieceCount: Int = 26) {
        pieces = (0..<pieceCount).map { _ in
            Piece(
                xPosition: .random(in: 0.05...0.95),
                size: .random(in: 18...36),
                startRotation: .degrees(.random(in: -30...30)),
                endRotation: .degrees(.random(in: 180...540)),
                duration: .random(in: 2.6...4.2),
                delay: .random(in: 0...0.4),
                startOffset: .random(in: 20...120),
                endOffset: .random(in: 40...160),
                opacity: .random(in: 0.75...1)
            )
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(pieces) { piece in
                    Image("NoBackground")
                        .resizable()
                        .scaledToFit()
                        .frame(width: piece.size, height: piece.size)
                        .opacity(piece.opacity)
                        .position(
                            x: piece.xPosition * geometry.size.width,
                            y: animate ? geometry.size.height + piece.endOffset : -piece.startOffset
                        )
                        .rotationEffect(animate ? piece.endRotation : piece.startRotation)
                        .animation(
                            .linear(duration: piece.duration).delay(piece.delay),
                            value: animate
                        )
                }
            }
            .onAppear {
                animate = true
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
