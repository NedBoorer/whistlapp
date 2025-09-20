//
//  PairingViews.swift
//  whistl
//
//  Created by Ned Boorer on 8/9/2025.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct PairingGateView: View {
    @Environment(AppController.self) private var appController
    @State private var showScanner = false
    @State private var showUnifiedJoin = false
    private let brand = BrandPalette()

    var body: some View {
        VStack(spacing: 20) {
            // Logout button on this screen
            HStack {
                Spacer()
                Button {
                    do { try appController.signOut() } catch { }
                } label: {
                    Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.plain)
                .tint(.red)
            }

            Text("To use whistl, link your account with exactly one partner. You’ll both share a private space.")
                .font(.callout)
                .foregroundStyle(brand.secondaryText)
                .multilineTextAlignment(.center)

            // Defensive UI gating (Welcome/Authview handle entry, but keep a hint here)
            if appController.authState != .authenticated {
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.exclamationmark")
                    Text("Please sign in to continue.")
                }
                .foregroundStyle(brand.secondaryText)
            }

            NavigationLink {
                CreatePairView()
            } label: {
                Label("Create a new link", systemImage: "link.badge.plus")
                    .frame(maxWidth: .infinity)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .disabled(appController.authState != .authenticated)

            Button {
                showUnifiedJoin = true
            } label: {
                Label("Join", systemImage: "person.crop.circle.badge.plus")
                    .frame(maxWidth: .infinity)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.bordered)
            .disabled(appController.authState != .authenticated)
            .sheet(isPresented: $showUnifiedJoin) {
                JoinPairUnifiedSheet()
            }

            Spacer()
        }
        .padding()
        .navigationBarBackButtonHidden(true)
    }
}

struct CreatePairView: View {
    @Environment(AppController.self) private var appController
    @State private var errorMessage: String?
    @State private var isCreating = false
    private let brand = BrandPalette()

    var body: some View {
        VStack(spacing: 16) {
            // Logout button
            HStack {
                Spacer()
                Button {
                    do { try appController.signOut() } catch { }
                } label: {
                    Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.plain)
                .tint(.red)
            }

            if appController.authState != .authenticated {
                Label("Please sign in before creating a link.", systemImage: "person.crop.circle.badge.exclamationmark")
                    .foregroundStyle(.red)
                    .font(.footnote)
            } else if let code = appController.inviteCode {
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

                Button {
                    UIPasteboard.general.string = code
                } label: {
                    Label("Copy code", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)

                NavigationLink {
                    QRGeneratorView(code: code)
                } label: {
                    Label("Show QR", systemImage: "qrcode")
                }
                .buttonStyle(.bordered)

                Text("Waiting for your partner to join…")
                    .font(.callout)
                    .foregroundStyle(brand.secondaryText)
                    .padding(.top, 8)

                WaitingForPartnerView()
                    .padding(.top, 4)
            } else {
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
                Button {
                    Task {
                        await create()
                    }
                } label: {
                    if isCreating {
                        ProgressView().tint(.white)
                    } else {
                        Label("Generate invite code", systemImage: "link.badge.plus")
                            .fontWeight(.semibold)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isCreating || appController.authState != .authenticated)
            }

            Spacer()
        }
        .padding()
        .navigationTitle("Create link")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await appController.fetchInviteCodeIfNeeded()
        }
    }

    private func create() async {
        guard appController.authState == .authenticated else {
            errorMessage = AppController.PairingError.notAuthenticated.localizedDescription
            return
        }
        errorMessage = nil
        isCreating = true
        do {
            try await appController.createPair()
        } catch {
            errorMessage = (error as NSError).localizedDescription
        }
        isCreating = false
    }
}

struct JoinPairView: View {
    @Environment(AppController.self) private var appController
    @State private var code: String = ""
    @State private var errorMessage: String?
    @State private var isJoining = false
    @State private var showUnifiedJoin = false
    private let brand = BrandPalette()

    var body: some View {
        VStack(spacing: 16) {
            // Logout button
            HStack {
                Spacer()
                Button {
                    do { try appController.signOut() } catch { }
                } label: {
                    Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.plain)
                .tint(.red)
            }

            Text("Enter the invite code provided by your partner.")
                .font(.callout)
                .foregroundStyle(brand.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                showUnifiedJoin = true
            } label: {
                Label("Join", systemImage: "person.crop.circle.badge.plus")
                    .frame(maxWidth: .infinity)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .disabled(appController.authState != .authenticated)
            .sheet(isPresented: $showUnifiedJoin) {
                JoinPairUnifiedSheet()
            }

            Spacer()
        }
        .padding()
        .navigationTitle("Join link")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct WaitingForPartnerView: View {
    @Environment(AppController.self) private var appController
    @State private var partnerJoined = false
    private let brand = BrandPalette()

    var body: some View {
        Group {
            HStack(spacing: 8) {
                ProgressView()
                Text("Waiting…")
            }
            .foregroundStyle(brand.secondaryText)
        }
        .task(id: appController.pairId) {
            await monitorPair()
        }
    }

    private func monitorPair() async {
        guard let pid = appController.pairId else { return }
        let pairRef = Firestore.firestore().collection("pairs").document(pid)
        pairRef.addSnapshotListener { snapshot, _ in
            guard let data = snapshot?.data() else { return }
            let memberB = data["memberB"] as? String
            let finalizedAt = data["finalizedAt"]
            partnerJoined = (memberB != nil && !(memberB ?? "").isEmpty) || !(finalizedAt is NSNull)
        }
    }
}

#Preview {
    NavigationStack { PairingGateView() }.environment(AppController())
}
