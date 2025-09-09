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
    private let brand = BrandPalette()

    var body: some View {
        VStack(spacing: 20) {
            Text("To use whistl, link your account with exactly one partner. You’ll both share a private space.")
                .font(.callout)
                .foregroundStyle(brand.secondaryText)
                .multilineTextAlignment(.center)

            // Logout button
            HStack {
                Spacer()
                Button {
                    do {
                        try appController.signOut()
                    } catch {
                        // Optionally surface an error message
                    }
                } label: {
                    Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.plain)
                .tint(.red)
            }

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

            NavigationLink {
                JoinPairView()
            } label: {
                Label("Join with invite code", systemImage: "rectangle.and.pencil.and.ellipsis")
                    .frame(maxWidth: .infinity)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.bordered)
            .disabled(appController.authState != .authenticated)

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
    private let brand = BrandPalette()

    var body: some View {
        VStack(spacing: 16) {
            Text("Enter the invite code provided by your partner.")
                .font(.callout)
                .foregroundStyle(brand.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

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

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                Task { await join() }
            } label: {
                if isJoining {
                    ProgressView().tint(.white)
                } else {
                    Text("Join")
                        .frame(maxWidth: .infinity)
                        .fontWeight(.semibold)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isJoining || appController.authState != .authenticated)

            Spacer()
        }
        .padding()
        .navigationTitle("Join link")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func join() async {
        guard appController.authState == .authenticated else {
            errorMessage = AppController.PairingError.notAuthenticated.localizedDescription
            return
        }
        errorMessage = nil
        isJoining = true
        do {
            try await appController.joinPair(using: code)
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

struct WaitingForPartnerView: View {
    @Environment(AppController.self) private var appController
    @State private var partnerJoined = false
    private let brand = BrandPalette()

    var body: some View {
        Group {
            if partnerJoined {
                Label("Partner linked! You can start using whistl.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Waiting…")
                }
                .foregroundStyle(brand.secondaryText)
            }
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

// New view: Welcome users who are paired and invite to continue setup together.
struct PairedWelcomeView: View {
    @Environment(AppController.self) private var appController
    @State private var partnerName: String = ""
    private let brand = BrandPalette()

    var body: some View {
        VStack(spacing: 16) {
            if partnerName.isEmpty {
                ProgressView()
                    .tint(brand.accent)
            } else {
                Text("Welcome \(currentUserName)")
                    .font(.title2.weight(.semibold))

                Text("You and \(partnerName) are paired.")
                    .font(.headline)

                Text("Are you both ready to set up the rest of your account?")
                    .font(.callout)
                    .foregroundStyle(brand.secondaryText)
                    .multilineTextAlignment(.center)

                // Continue button — route to whatever setup you want next.
                // For now, send them to CreatePairView/JoinPairView parent gate (can be replaced with your setup flow).
                NavigationLink {
                    PairingGateView()
                        .navigationTitle("Continue setup")
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
            }
            Spacer()
        }
        .padding()
        .navigationTitle("Welcome")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await fetchPartnerName()
        }
    }

    private var currentUserName: String {
        let name = appController.currentDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "there" : name
    }

    private func fetchPartnerName() async {
        guard let pid = appController.pairId,
              let uid = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        do {
            let pairSnap = try await db.collection("pairs").document(pid).getDocument()
            guard let data = pairSnap.data() else { return }
            let memberA = data["memberA"] as? String
            let memberB = data["memberB"] as? String

            let partnerUid: String? = {
                if let a = memberA, a != uid { return a }
                if let b = memberB, b != uid { return b }
                return nil
            }()

            if let partnerUid {
                let partnerDoc = try await db.collection("users").document(partnerUid).getDocument()
                if let name = partnerDoc.data()?["name"] as? String, !name.isEmpty {
                    partnerName = name
                } else {
                    partnerName = "your partner"
                }
            } else {
                partnerName = "your partner"
            }
        } catch {
            partnerName = "your partner"
        }
    }
}

#Preview {
    NavigationStack { PairingGateView() }.environment(AppController())
}
