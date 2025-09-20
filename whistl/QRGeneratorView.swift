import SwiftUI

struct QRGeneratorView: View {
    let code: String
    private let brand = BrandPalette()

    var body: some View {
        VStack(spacing: 16) {
            if let image = QRGenerator.image(for: WhistlQR.pairingURLString(code: code), scale: 8) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 240, height: 240)
                    .cornerRadius(16)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(brand.cardStroke, lineWidth: 1))
            } else {
                Label("Couldn’t generate QR", systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
            }
            Text("Ask your mate to scan this QR to join.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(brand.fieldBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(brand.cardStroke, lineWidth: 1)
        )
        .navigationTitle("Pair via QR")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { QRGeneratorView(code: "ABCDE1") }
}
