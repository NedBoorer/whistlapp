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

@Observable
class AppController {
    var name = ""
    var email = ""
    var password = ""
    var authState: AuthState = .undefined

    // Cached display name from FirebaseAuth / Firestore
    var currentDisplayName: String = ""

    // Pairing state
    var pairId: String? = nil            // ID of the pair document this user belongs to
    var inviteCode: String? = nil        // If creator, the code for partner to join
    var isPaired: Bool { pairId != nil } // convenience

    // Firestore: obtain instance lazily to avoid touching it before FirebaseApp.configure()
    private var db: Firestore {
        Firestore.firestore()
    }

    @MainActor
    func listenToAuthChanges() {
        Auth.auth().addStateDidChangeListener { _, user in
            self.authState = user != nil ? .authenticated : .notAuthenticated
            self.currentDisplayName = user?.displayName ?? ""

            guard let user else {
                self.currentDisplayName = ""
                self.pairId = nil
                self.inviteCode = nil
                return
            }

            // After sign-in/up, try to ensure we can read the user profile.
            // Do a one-shot read first; only attach listeners if it succeeds.
            Task {
                let ok = await self.loadUserProfile(uid: user.uid)
                if ok {
                    self.observePairMembership(uid: user.uid)
                } else {
                    // Retry once after a short delay in case auth token propagation is slightly delayed
                    try? await Task.sleep(nanoseconds: 400_000_000) // 0.4s
                    let ok2 = await self.loadUserProfile(uid: user.uid)
                    if ok2 {
                        self.observePairMembership(uid: user.uid)
                    } else {
                        // Keep UI usable even if profile read is blocked; do not attach listener
                        // You could log or surface a non-fatal message here if desired
                    }
                }
            }
        }
    }

    func signUp() async throws {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)

        // Best-effort: set display name early if provided
        let provisionalName = self.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !provisionalName.isEmpty {
            try? await updateDisplayName(provisionalName)
        }

        // Ensure a profile document exists before listeners try to read it
        try await saveUserProfile(uid: result.user.uid, name: Auth.auth().currentUser?.displayName ?? provisionalName, email: email)
    }

    func signIn() async throws {
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        self.currentDisplayName = result.user.displayName ?? ""
        // No immediate listeners here; listenToAuthChanges will run and attach after a successful read
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
        // Persist to Firestore too
        try await saveUserProfile(uid: user.uid, name: display, email: user.email ?? self.email)
    }

    func signOut() throws {
        try Auth.auth().signOut()
        // Reset observable state on the main actor
        Task { @MainActor in
            self.currentDisplayName = ""
            self.authState = .notAuthenticated
            self.pairId = nil
            self.inviteCode = nil
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

    /// Attempts to load the user profile once.
    /// Returns true if the read succeeded (regardless of whether fields were present).
    @MainActor
    private func loadUserProfile(uid: String) async -> Bool {
        do {
            let snapshot = try await userDoc(uid: uid).getDocument()
            if let name = snapshot.data()?["name"] as? String, !name.isEmpty {
                self.currentDisplayName = name
            }
            if let pid = snapshot.data()?["pairId"] as? String, !pid.isEmpty {
                self.pairId = pid
            } else {
                self.pairId = nil
            }
            return true
        } catch {
            // Non-fatal: keep using auth displayName, indicate failure via return value
            return false
        }
    }

    // MARK: - Pairing

    private var pairsCollection: CollectionReference { db.collection("pairs") }
    private var pairSpacesCollection: CollectionReference { db.collection("pairSpaces") }

    /// Observe the user's document to react to pair membership changes.
    private func observePairMembership(uid: String) {
        userDoc(uid: uid).addSnapshotListener { snapshot, _ in
            guard let data = snapshot?.data() else { return }
            let pid = data["pairId"] as? String
            Task { @MainActor in
                self.pairId = pid
            }
        }
    }

    /// Create a pair as the first member, generating an invite code. Also creates the shared space doc.
    func createPair() async throws {
        guard let user = Auth.auth().currentUser else { throw PairingError.notAuthenticated }
        let uid = user.uid
        let code = Self.generateInviteCode()
        let pairRef = pairsCollection.document() // random id
        let spaceRef = pairSpacesCollection.document(pairRef.documentID)
        try await db.runTransaction { txn, errorPtr in
            do {
                // Check user not already paired
                let userSnap = try txn.getDocument(self.userDoc(uid: uid))
                if let existing = userSnap.data()?["pairId"] as? String, !existing.isEmpty {
                    errorPtr?.pointee = PairingError.alreadyPaired as NSError
                    return nil
                }
                // Create pair doc
                txn.setData([
                    "createdAt": FieldValue.serverTimestamp(),
                    "inviteCode": code,
                    "memberA": uid,
                    "memberB": NSNull(),
                    "finalizedAt": NSNull()
                ], forDocument: pairRef)

                // Create shared space (can be empty metadata)
                txn.setData([
                    "createdAt": FieldValue.serverTimestamp(),
                    "pairId": pairRef.documentID
                ], forDocument: spaceRef)

                // Update user with pairId
                txn.setData(["pairId": pairRef.documentID], forDocument: self.userDoc(uid: uid), merge: true)

                return nil
            } catch {
                errorPtr?.pointee = error as NSError
                return nil
            }
        }
        // Cache locally
        Task { @MainActor in
            self.pairId = pairRef.documentID
            self.inviteCode = code
        }
    }

    /// Join an existing pair by invite code. Finalizes the pair by setting memberB and removing inviteCode.
    func joinPair(using code: String) async throws {
        guard let user = Auth.auth().currentUser else { throw PairingError.notAuthenticated }
        let uid = user.uid
        let trimmed = code.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PairingError.invalidCode }

        // Query pair by inviteCode
        let query = try await pairsCollection.whereField("inviteCode", isEqualTo: trimmed).limit(to: 1).getDocuments()
        guard let doc = query.documents.first else { throw PairingError.codeNotFound }
        let pairRef = doc.reference

        try await db.runTransaction { txn, errorPtr in
            do {
                // Ensure user is not already paired
                let userSnap = try txn.getDocument(self.userDoc(uid: uid))
                if let existing = userSnap.data()?["pairId"] as? String, !existing.isEmpty {
                    errorPtr?.pointee = PairingError.alreadyPaired as NSError
                    return nil
                }

                // Load pair doc
                let pairSnap = try txn.getDocument(pairRef)
                guard var data = pairSnap.data() else {
                    errorPtr?.pointee = PairingError.codeNotFound as NSError
                    return nil
                }
                // Ensure there's a free slot
                if let memberB = data["memberB"] as? String, !memberB.isEmpty {
                    errorPtr?.pointee = PairingError.pairFull as NSError
                    return nil
                }
                // Set memberB and finalize
                data["memberB"] = uid
                data["finalizedAt"] = FieldValue.serverTimestamp()
                data["inviteCode"] = NSNull() // remove code so it can't be reused
                txn.setData(data, forDocument: pairRef, merge: true)

                // Update both users with pairId (creator already set, but merge again is fine)
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
        }
    }

    /// For creators waiting for partner, re-fetch invite code if needed
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
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789") // no confusing chars
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
