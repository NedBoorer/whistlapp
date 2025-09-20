import SwiftUI
import AVFoundation

struct JoinPairUnifiedSheet: View {
    @Environment(AppController.self) private var appController
    @Environment(\.dismiss) private var dismiss
    private let brand = BrandPalette()

    enum Tab: Hashable { case scan, code }
    @State private var tab: Tab = .scan

    @State private var cameraAuthorized: Bool = false
    @State private var cameraDenied: Bool = false

    @State private var code: String = ""
    @State private var isJoining: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("Mode", selection: $tab) {
                    Text("Scan QR").tag(Tab.scan)
                    Text("Enter Code").tag(Tab.code)
                }
                .pickerStyle(.segmented)

                Group {
                    if tab == .scan {
                        scanTab
                    } else {
                        codeTab
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(brand.error)
                        .font(.footnote)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
                }

                HStack(spacing: 12) {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .buttonStyle(.bordered)

                    Button {
                        Task { await performJoin() }
                    } label: {
                        if isJoining { ProgressView().tint(.white) }
                        Text("Join")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(brand.accent)
                    .disabled(disabledJoin)
                }
            }
            .padding()
            .background(brand.background())
            .navigationTitle("Join link")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await preflightCamera() }
    }

    private var disabledJoin: Bool {
        switch tab {
        case .scan:
            // Join is triggered automatically on successful scan; keep enabled for parity
            return isJoining
        case .code:
            return isJoining || code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    @ViewBuilder
    private var scanTab: some View {
        VStack(spacing: 10) {
            if cameraDenied {
                Label("Camera access denied. Enter code instead.", systemImage: "camera.fill")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            } else if cameraAuthorized {
                QRScannerView { payload in
                    if let parsed = WhistlQR.parsePairingURL(payload) {
                        Task { await joinUsing(code: parsed) }
                    } else {
                        errorMessage = "Invalid QR code."
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: 300)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(brand.cardStroke, lineWidth: 1)
                )
                Text("Align the QR within the frame.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView("Requesting camera access…")
                    .tint(brand.accent)
                Spacer(minLength: 0)
            }
        }
    }

    private var codeTab: some View {
        VStack(spacing: 12) {
            TextField("Invite code", text: $code)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .textCase(.uppercase)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: brand.fieldCornerRadius, style: .continuous)
                        .fill(brand.fieldBackground)
                )
        }
    }

    private func preflightCamera() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraAuthorized = true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            await MainActor.run {
                cameraAuthorized = granted
                cameraDenied = !granted
            }
        case .denied, .restricted:
            cameraDenied = true
            cameraAuthorized = false
        @unknown default:
            cameraDenied = true
            cameraAuthorized = false
        }
    }

    private func performJoin() async {
        switch tab {
        case .scan:
            // No-op: scanning auto-joins; keep button for consistency
            return
        case .code:
            await joinUsing(code: code)
        }
    }

    private func joinUsing(code: String) async {
        guard appController.authState == .authenticated else {
            errorMessage = AppController.PairingError.notAuthenticated.localizedDescription
            return
        }
        errorMessage = nil
        isJoining = true
        do {
            try await appController.joinPair(using: code)
            dismiss()
        } catch {
            if let e = error as? AppController.PairingError {
                errorMessage = e.localizedDescription
            } else {
                errorMessage = (error as NSError).localizedDescription
            }
        }
        isJoining = false
    }
}

#Preview {
    JoinPairUnifiedSheet()
        .environment(AppController())
}
