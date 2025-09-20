import SwiftUI

struct CreatePairUnifiedSheet: View {
    let code: String
    private let brand = BrandPalette()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                VStack(spacing: 6) {
                    Text("Share this code with your partner")
                        .font(.headline)
                    Text(code)
                        .font(.system(size: 36, weight: .heavy, design: .rounded))
                        .padding(.vertical, 4)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(brand.fieldBackground)
                        )
                }

                if let image = QRGenerator.image(for: WhistlQR.pairingURLString(code: code), scale: 8) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 240, height: 240)
                        .cornerRadius(16)
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(brand.cardStroke, lineWidth: 1))
                }

                Text("Ask your mate to scan the QR or enter the code.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button {
                        UIPasteboard.general.string = code
                    } label: {
                        Label("Copy code", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.bordered)

                    ShareLink(item: WhistlQR.pairingURLString(code: code)) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()
            }
            .padding()
            .background(brand.background())
            .navigationTitle("Create link")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    CreatePairUnifiedSheet(code: "ABCDE1")
}
