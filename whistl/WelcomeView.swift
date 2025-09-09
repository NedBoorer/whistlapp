//
//  WelcomeView.swift
//  whistl
//
//  Created by Ned Boorer on 8/9/2025.
//

import SwiftUI

struct WelcomeView: View {
    private let brand = BrandPalette()

    var body: some View {
        ZStack {
            brand.background()

            VStack(spacing: 24) {
                Spacer(minLength: 12)

                // Logo
                Text("whistl")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .kerning(1.0)
                    .foregroundStyle(brand.primaryGradient())
                    .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
                    .accessibilityLabel("whistl")
                    .accessibilityAddTraits(.isHeader)

                Text("Welcome to whistl")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(brand.primaryText)

                Text("Private, shared space for two. Let’s get you set up.")
                    .font(.callout)
                    .foregroundStyle(brand.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                NavigationLink {
                    // Route to Authview so users can choose Sign in or Create account
                    Authview()
                } label: {
                    Text("Get started")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(brand.accent)
                .padding(.horizontal, 24)
                .padding(.top, 8)

                Spacer()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { }
    }
}

#Preview {
    NavigationStack { WelcomeView() }
}
