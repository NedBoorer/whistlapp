//
//  Brand.swift
//  whistl
//
//  Created by Ned Boorer on 8/9/2025.
//

import SwiftUI
import UIKit

struct BrandPalette {
    // Dynamic brand colors for light/dark
    let accent = Color("BrandAccent", bundle: .main, default: Color(red: 0.12, green: 0.49, blue: 0.98))
    let accentSecondary = Color("BrandAccentSecondary", bundle: .main, default: Color(red: 0.10, green: 0.43, blue: 0.90))

    // Mission tones
    let attention = Color("BrandAttention", bundle: .main, default: Color(red: 1.00, green: 0.73, blue: 0.20))  // warm amber for banners
    let success   = Color("BrandSuccess", bundle: .main, default: Color(red: 0.18, green: 0.67, blue: 0.36))  // supportive green

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

    // Compact mission banner view you can drop into screens
    @ViewBuilder
    func missionBanner(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "person.2.fill")
                .foregroundStyle(attention)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(fieldBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(cardStroke, lineWidth: 1)
        )
    }

    // UIColor bridges for the Managed Settings extension if you ever want brand colors there
    var uiAccent: UIColor { UIColor(accent) }
    var uiSecondaryText: UIColor { UIColor.secondaryLabel }
    var uiPrimaryText: UIColor { UIColor.label }
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

