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
