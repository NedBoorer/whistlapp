//
//  Brand.swift
//  whistl
//
//  Created by Ned Boorer on 8/9/2025.
//

import SwiftUI

struct BrandPalette {
    // Dynamic brand colors for light/dark
    let accent = Color("BrandAccent", bundle: .main, default: Color(red: 0.12, green: 0.49, blue: 0.98))
    let accentSecondary = Color("BrandAccentSecondary", bundle: .main, default: Color(red: 0.10, green: 0.43, blue: 0.90))

    let bgTop = Color("BrandBackgroundTop", bundle: .main, default: Color(.systemBackground)).opacity(0.98)
    let bgBottom = Color("BrandBackgroundBottom", bundle: .main, default: Color(.secondarySystemBackground))

    let primaryText = Color.primary
    let secondaryText = Color.secondary
    let cardStroke = Color.black.opacity(0.08)
    let fieldBackground = Color(.secondarySystemBackground)
    let error = Color.red

    // Metrics
    let cornerRadius: CGFloat = 16
    let fieldCornerRadius: CGFloat = 12

    // Background gradient
    @ViewBuilder
    func background() -> some View {
        LinearGradient(
            colors: [
                bgTop,
                bgBottom
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    // Primary gradient fill
    func primaryGradient() -> LinearGradient {
        LinearGradient(
            colors: [
                accent,
                accentSecondary
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension Color {
    // Convenience to fall back to defaults when asset not present
    init(_ name: String, bundle: Bundle, default fallback: Color) {
        if let uiColor = UIColor(named: name, in: bundle, compatibleWith: nil) {
            self = Color(uiColor)
        } else {
            self = fallback
        }
    }
}
