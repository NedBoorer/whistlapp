//
//  SplashView.swift
//  whistl
//

import SwiftUI

struct SplashView: View {
    let brand = BrandPalette()
    let onFinished: () -> Void

    @State private var animate = false
    @State private var hasFinished = false

    var body: some View {
        ZStack {
            brand.background()

            Text("baura")
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .kerning(1.0)
                .foregroundStyle(brand.primaryGradient())
                .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
                .scaleEffect(animate ? 1.06 : 0.94)
                .opacity(animate ? 1.0 : 0.92)
                .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: animate)
                .accessibilityLabel("baura")
                .accessibilityAddTraits(.isHeader)
        }
        .onAppear {
            animate = true
            // Extend the splash display duration so the pulse runs longer
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                guard !hasFinished else { return }
                hasFinished = true
                onFinished()
            }
        }
        .onDisappear { animate = false }
    }
}

#Preview { SplashView(onFinished: {}) }
