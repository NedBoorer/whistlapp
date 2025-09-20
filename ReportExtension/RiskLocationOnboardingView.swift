import SwiftUI

struct RiskLocationOnboardingView: View {
    let onContinue: () -> Void
    let onCancel: () -> Void

    private let brand = BrandPalette()

    var body: some View {
        ZStack {
            brand.background()
            VStack(spacing: 16) {
                Image(systemName: "location.circle.fill")
                    .font(.system(size: 52, weight: .bold))
                    .foregroundStyle(brand.accent)
                Text("Risk place alerts")
                    .font(.title2.bold())
                Text("We can alert your mate if you stay at a bar or casino for 5+ minutes. This uses your location in the background and only sends an alert every 2 hours per venue.")
                    .multilineTextAlignment(.center)
                    .font(.callout)
                    .foregroundStyle(brand.secondaryText)
                    .padding(.horizontal)

                VStack(alignment: .leading, spacing: 8) {
                    Label("Uses background location", systemImage: "antenna.radiowaves.left.and.right")
                    Label("You control it in Settings", systemImage: "slider.horizontal.3")
                    Label("2‑hour cooldown per venue", systemImage: "clock")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

                HStack(spacing: 12) {
                    Button(role: .cancel) { onCancel() } label: {
                        Text("Not now")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button { onContinue() } label: {
                        Label("Turn on", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(brand.accent)
                }
                .padding(.horizontal)

                Spacer(minLength: 0)
            }
            .padding(.top, 40)
        }
    }
}

#Preview {
    RiskLocationOnboardingView(onContinue: {}, onCancel: {})
}
