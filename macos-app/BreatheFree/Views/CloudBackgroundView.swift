//
//  CloudBackgroundView.swift
//  BreatheFree
//
//  Animated cloud background decoration
//

import SwiftUI

struct CloudBackgroundView: View {
    var body: some View {
        ZStack {
            ForEach(0..<6) { index in
                CloudShape()
                    .fill(Color.white.opacity(cloudOpacity(for: index)))
                    .frame(width: cloudWidth(for: index), height: cloudHeight(for: index))
                    .modifier(CloudAnimationModifier(
                        duration: cloudDuration(for: index),
                        delay: cloudDelay(for: index),
                        yOffset: cloudYOffset(for: index)
                    ))
            }
        }
        .allowsHitTesting(false) // Non-interactive
    }

    private func cloudOpacity(for index: Int) -> Double {
        let opacities: [Double] = [0.45, 0.55, 0.65, 0.5, 0.75, 0.6]
        return opacities[index]
    }

    private func cloudWidth(for index: Int) -> CGFloat {
        let widths: [CGFloat] = [120, 160, 100, 140, 180, 130]
        return widths[index]
    }

    private func cloudHeight(for index: Int) -> CGFloat {
        let heights: [CGFloat] = [60, 80, 50, 70, 90, 65]
        return heights[index]
    }

    private func cloudDuration(for index: Int) -> Double {
        let durations: [Double] = [22, 28, 25, 30, 35, 26]
        return durations[index]
    }

    private func cloudDelay(for index: Int) -> Double {
        let delays: [Double] = [0, 5, 10, 15, 8, 12]
        return delays[index]
    }

    private func cloudYOffset(for index: Int) -> CGFloat {
        let offsets: [CGFloat] = [-100, 50, -150, 100, -50, 0]
        return offsets[index]
    }
}

struct CloudShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        // Simple cloud shape using circles
        let width = rect.width
        let height = rect.height

        // Left circle
        path.addEllipse(in: CGRect(x: 0, y: height * 0.3, width: width * 0.4, height: height * 0.7))

        // Center circle (largest)
        path.addEllipse(in: CGRect(x: width * 0.25, y: 0, width: width * 0.5, height: height))

        // Right circle
        path.addEllipse(in: CGRect(x: width * 0.6, y: height * 0.3, width: width * 0.4, height: height * 0.7))

        return path
    }
}

struct CloudAnimationModifier: ViewModifier {
    let duration: Double
    let delay: Double
    let yOffset: CGFloat

    @State private var offset: CGFloat = -200

    func body(content: Content) -> some View {
        content
            .offset(x: offset, y: yOffset)
            .onAppear {
                withAnimation(
                    .linear(duration: duration)
                    .repeatForever(autoreverses: false)
                    .delay(delay)
                ) {
                    offset = 1200 // Move across screen
                }
            }
    }
}

#Preview {
    ZStack {
        LinearGradient(
            colors: [
                Color(red: 0.941, green: 0.976, blue: 1.0),
                Color(red: 0.902, green: 0.949, blue: 1.0),
                Color(red: 0.8, green: 0.902, blue: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()

        CloudBackgroundView()
    }
    .frame(width: 800, height: 600)
}
