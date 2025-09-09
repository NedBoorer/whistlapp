//
//  AppController.swift
//  whistl
//
//  Created by Ned Boorer on 8/9/2025.
//

import Observation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

enum AuthState {
    case undefined, authenticated, notAuthenticated
}

enum PairingLoadState {
    case unknown       // before any attempt
    case loading       // fetching user profile
    case unpaired      // confirmed no pair
    case paired        // confirmed has pairId
}

@Observable
class AppController {
    var name = ""
    var email = ""
    var password = ""
    var authState: AuthState = .undefined

    // Cached display name from FirebaseAuth / Firestore
    var currentDisplayName: String = ""

    // Pairing state
    var pairId: String? = nil
    var inviteCode: String? = nil
    var pairingLoadState: PairingLoadState = .unknown

    var isPaired: Bool { pairingLoadState == .paired }

    private var db: Firestore { Firestore.firestore() }

    @MainActor
    func listenToAuthChanges() {
        Auth.auth().addStateDidChangeListener { _, user in
            self.authState = user != nil ? .authenticated : .notAuthenticated
            self.currentDisplayName = user?.displayName ?? ""

            guard let user else {
                self.currentDisplayName = ""
                self.pairId = nil
                self.inviteCode = nil
                self.pairingLoadState = .unknown
                return
            }

            // Reset pairing state while we fetch fresh data for this user
            self.pairId = nil
            self.inviteCode = nil
            self.pairingLoadState = .loading

            Task {
                let ok = await self.loadUserProfile(uid: user.uid)
                if ok {
                    self.observePairMembership(uid: user.uid)
                } else {
                    // If we cannot read user profile (e.g., transient), default to unpaired
                    // so UI routes to pairing gate rather than profile.
                    await MainActor.run {
                        self.pairingLoadState = .unpaired
                    }
                }
            }
        }
    }

    func signUp() async throws {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        let provisionalName = self.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !provisionalName.isEmpty {
            try? await updateDisplayName(provisionalName)
        }
        try await saveUserProfile(uid: result.user.uid, name: Auth.auth().currentUser?.displayName ?? provisionalName, email: email)
    }

    func signIn() async throws {
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        self.currentDisplayName = result.user.displayName ?? ""
        // listener will proceed to load profile and set pairingLoadState
    }

    func updateDisplayName(_ newName: String) async throws {
        guard let user = Auth.auth().currentUser else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let change = user.createProfileChangeRequest()
        change.displayName = trimmed
        try await change.commitChanges()
        try await user.reload()
        let display = Auth.auth().currentUser?.displayName ?? trimmed
        self.currentDisplayName = display
        try await saveUserProfile(uid: user.uid, name: display, email: user.email ?? self.email)
    }

    func signOut() throws {
        try Auth.auth().signOut()
        Task { @MainActor in
            self.currentDisplayName = ""
            self.authState = .notAuthenticated
            self.pairId = nil
            self.inviteCode = nil
            self.pairingLoadState = .unknown
        }
    }

    // MARK: - Firestore User Profile

    private func userDoc(uid: String) -> DocumentReference {
        db.collection("users").document(uid)
    }

    private func saveUserProfile(uid: String, name: String, email: String) async throws {
        var data: [String: Any] = [
            "name": name,
            "email": email
        ]
        let docRef = userDoc(uid: uid)
        let snapshot = try await docRef.getDocument()
        if !snapshot.exists {
            data["createdAt"] = FieldValue.serverTimestamp()
            try await docRef.setData(data)
        } else {
            try await docRef.setData(data, merge: true)
        }
    }

    @MainActor
    private func loadUserProfile(uid: String) async -> Bool {
        do {
            let snapshot = try await userDoc(uid: uid).getDocument()
            if let name = snapshot.data()?["name"] as? String, !name.isEmpty {
                self.currentDisplayName = name
            }
            if let pid = snapshot.data()?["pairId"] as? String, !pid.isEmpty {
                self.pairId = pid
                self.pairingLoadState = .paired
            } else {
                self.pairId = nil
                self.pairingLoadState = .unpaired
            }
            return true
        } catch {
            // Default to unpaired to avoid accidental routing to profile
            self.pairId = nil
            self.pairingLoadState = .unpaired
            return false
        }
    }

    // MARK: - Pairing

    private var pairsCollection: CollectionReference { db.collection("pairs") }
    private var pairSpacesCollection: CollectionReference { db.collection("pairSpaces") }

    private func observePairMembership(uid: String) {
        userDoc(uid: uid).addSnapshotListener { snapshot, _ in
            guard let data = snapshot?.data() else { return }
            let pid = data["pairId"] as? String
            Task { @MainActor in
                if let pid, !pid.isEmpty {
                    self.pairId = pid
                    self.pairingLoadState = .paired
                } else {
                    self.pairId = nil
                    self.pairingLoadState = .unpaired
                }
            }
        }
        // Also fetch invite code if creator
        Task { await self.fetchInviteCodeIfNeeded() }
    }

    func createPair() async throws {
        guard let user = Auth.auth().currentUser else { throw PairingError.notAuthenticated }
        let uid = user.uid
        let code = Self.generateInviteCode()
        let pairRef = pairsCollection.document()
        let spaceRef = pairSpacesCollection.document(pairRef.documentID)
        try await db.runTransaction { txn, errorPtr in
            do {
                let userSnap = try txn.getDocument(self.userDoc(uid: uid))
                if let existing = userSnap.data()?["pairId"] as? String, !existing.isEmpty {
                    errorPtr?.pointee = PairingError.alreadyPaired as NSError
                    return nil
                }
                txn.setData([
                    "createdAt": FieldValue.serverTimestamp(),
                    "inviteCode": code,
                    "memberA": uid,
                    "memberB": NSNull(),
                    "finalizedAt": NSNull()
                ], forDocument: pairRef)
                txn.setData([
                    "createdAt": FieldValue.serverTimestamp(),
                    "pairId": pairRef.documentID
                ], forDocument: spaceRef)
                txn.setData(["pairId": pairRef.documentID], forDocument: self.userDoc(uid: uid), merge: true)
                return nil
            } catch {
                errorPtr?.pointee = error as NSError
                return nil
            }
        }
        Task { @MainActor in
            self.pairId = pairRef.documentID
            self.inviteCode = code
            self.pairingLoadState = .paired
        }
    }

    func joinPair(using code: String) async throws {
        guard let user = Auth.auth().currentUser else { throw PairingError.notAuthenticated }
        let uid = user.uid
        let trimmed = code.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PairingError.invalidCode }

        let query = try await pairsCollection.whereField("inviteCode", isEqualTo: trimmed).limit(to: 1).getDocuments()
        guard let doc = query.documents.first else { throw PairingError.codeNotFound }
        let pairRef = doc.reference

        try await db.runTransaction { txn, errorPtr in
            do {
                let userSnap = try txn.getDocument(self.userDoc(uid: uid))
                if let existing = userSnap.data()?["pairId"] as? String, !existing.isEmpty {
                    errorPtr?.pointee = PairingError.alreadyPaired as NSError
                    return nil
                }
                let pairSnap = try txn.getDocument(pairRef)
                guard var data = pairSnap.data() else {
                    errorPtr?.pointee = PairingError.codeNotFound as NSError
                    return nil
                }
                if let memberB = data["memberB"] as? String, !memberB.isEmpty {
                    errorPtr?.pointee = PairingError.pairFull as NSError
                    return nil
                }
                data["memberB"] = uid
                data["finalizedAt"] = FieldValue.serverTimestamp()
                data["inviteCode"] = NSNull()
                txn.setData(data, forDocument: pairRef, merge: true)

                let pairId = pairRef.documentID
                txn.setData(["pairId": pairId], forDocument: self.userDoc(uid: uid), merge: true)
                return nil
            } catch {
                errorPtr?.pointee = error as NSError
                return nil
            }
        }

        Task { @MainActor in
            self.pairId = pairRef.documentID
            self.inviteCode = nil
            self.pairingLoadState = .paired
        }
    }

    func fetchInviteCodeIfNeeded() async {
        guard let pid = pairId, inviteCode == nil else { return }
        do {
            let snap = try await pairsCollection.document(pid).getDocument()
            if let code = snap.data()?["inviteCode"] as? String {
                Task { @MainActor in
                    self.inviteCode = code
                }
            }
        } catch {
            // ignore
        }
    }

    static func generateInviteCode(length: Int = 6) -> String {
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<length).compactMap { _ in chars.randomElement() })
    }

    enum PairingError: LocalizedError {
        case notAuthenticated
        case alreadyPaired
        case invalidCode
        case codeNotFound
        case pairFull

        var errorDescription: String? {
            switch self {
            case .notAuthenticated: return "You must be signed in."
            case .alreadyPaired: return "You are already linked to a partner."
            case .invalidCode: return "Enter a valid invite code."
            case .codeNotFound: return "Invite code not found."
            case .pairFull: return "This invite has already been used."
            }
        }
    }
}
