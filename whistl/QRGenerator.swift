import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

enum QRGenerator {
    private static let context = CIContext()
    private static let filter = CIFilter.qrCodeGenerator()

    static func image(for string: String, scale: CGFloat = 10) -> UIImage? {
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let outputImage = filter.outputImage else { return nil }
        let transformed = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        if let cg = context.createCGImage(transformed, from: transformed.extent) {
            return UIImage(cgImage: cg)
        }
        return nil
    }
}
