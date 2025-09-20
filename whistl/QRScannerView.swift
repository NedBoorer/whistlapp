import SwiftUI
import AVFoundation

struct QRScannerView: UIViewControllerRepresentable {
    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        var parent: QRScannerView
        init(parent: QRScannerView) { self.parent = parent }

        func metadataOutput(_ output: AVCaptureMetadataOutput,
                            didOutput metadataObjects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            guard parent.isActive else { return }
            if let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
               obj.type == .qr,
               let stringValue = obj.stringValue {
                parent.isActive = false
                parent.onFound(stringValue)
            }
        }
    }

    var onFound: (String) -> Void
    @State var isActive: Bool = true

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        let session = AVCaptureSession()
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            return vc
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return vc }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(context.coordinator, queue: .main)
        output.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = vc.view.bounds
        DispatchQueue.main.async {
            vc.view.layer.addSublayer(preview)
        }

        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        guard !isActive else { return }
        // Attempt to stop the capture session when not active
        if let layers = uiViewController.view.layer.sublayers {
            for layer in layers {
                if let previewLayer = layer as? AVCaptureVideoPreviewLayer {
                    let session = previewLayer.session
                    DispatchQueue.global(qos: .userInitiated).async {
                        session?.stopRunning()
                    }
                    break
                }
            }
        }
    }
}
