import SwiftUI

struct WhisprHomeView: View {
    @Environment(AppController.self) private var appController
    private let brand = BrandPalette()

    var body: some View {
        VStack(spacing: 16) {
            Text("Hi \(displayName)")
                .font(.largeTitle.bold())
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("Welcome to Whispr.")
                .font(.headline)
                .foregroundStyle(brand.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Entry point to the Screen Time blocking menu
            NavigationLink {
                FocusMenuView()
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                Label("Open blocking menu", systemImage: "lock.shield")
                    .frame(maxWidth: .infinity)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .tint(brand.accent)
            .padding(.top, 8)

            Spacer()
        }
        .padding()
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var displayName: String {
        let name = appController.currentDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "there" : name
    }
}

#Preview {
    NavigationStack { WhisprHomeView() }.environment(AppController())
}
