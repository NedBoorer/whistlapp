//
//  SplashView.swift
//  whistl
//
//  Created by Ned Boorer on 12/9/2025.
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

            // Reuse the same stylized text logo look as Authview.LogoView
            Text("whistl")
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .kerning(1.0)
                .foregroundStyle(brand.primaryGradient())
                .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
                .scaleEffect(animate ? 1.06 : 0.94)
                .opacity(animate ? 1.0 : 0.92)
                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: animate)
                .accessibilityLabel("whistl")
                .accessibilityAddTraits(.isHeader)
        }
        .onAppear {
            animate = true
            // Keep the splash briefly to cover Firebase/auth init and provide a smooth feel.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                guard !hasFinished else { return }
                hasFinished = true
                onFinished()
            }
        }
        .onDisappear {
            animate = false
        }
    }
}

#Preview {
    SplashView(onFinished: {})
}

