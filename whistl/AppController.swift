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
    case unpaired      // confirmed no pair OR not finalized
    case paired        // confirmed pair is finalized
}

// Setup workflow phases enforced by Firestore Rules/transactions
enum SetupPhase: String {
    case awaitingASubmission = "awaitingASubmission"
    case awaitingBApproval   = "awaitingBApproval"
    case awaitingBSubmission = "awaitingBSubmission"
    case awaitingAApproval   = "awaitingAApproval"
    case complete            = "complete"
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

    // Cached role resolution
    var isMemberA: Bool = false
    var isMemberB: Bool = false

    // Partner UID cached (derived from pair doc)
    var partnerUID: String? = nil

    // Setup workflow observation
    var currentSetupPhaseRaw: String? = nil
    var currentSetupPhase: SetupPhase? {
        guard let raw = currentSetupPhaseRaw else { return nil }
        return SetupPhase(rawValue: raw)
    }
    private var setupListener: ListenerRegistration?
    private var userListener: ListenerRegistration?

    private var db: Firestore { Firestore.firestore() }

    @MainActor
    func listenToAuthChanges() {
        Auth.auth().addStateDidChangeListener { _, user in
            Task { @MainActor in
                self.authState = user != nil ? .authenticated : .notAuthenticated
                self.currentDisplayName = user?.displayName ?? ""

                guard let user else {
                    self.resetUserScopedState()
                    return
                }

                // Reset pairing state while we fetch fresh data for this user
                self.resetPairScopedState()

                Task {
                    let ok = await self.loadUserProfile(uid: user.uid)
                    if ok {
                        self.observePairMembership(uid: user.uid)
                    } else {
                        await MainActor.run {
                            self.pairingLoadState = .unpaired
                        }
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
        await MainActor.run {
            self.currentDisplayName = result.user.displayName ?? ""
        }
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
        await MainActor.run {
            self.currentDisplayName = display
        }
        try await saveUserProfile(uid: user.uid, name: display, email: user.email ?? self.email)
    }

    func signOut() throws {
        try Auth.auth().signOut()
        Task { @MainActor in
            self.resetUserScopedState()
        }
    }

    // MARK: - State reset helpers

    @MainActor
    private func resetUserScopedState() {
        self.currentDisplayName = ""
        self.authState = .notAuthenticated
        self.resetPairScopedState()
    }

    @MainActor
    private func resetPairScopedState() {
        self.pairId = nil
        self.inviteCode = nil
        self.pairingLoadState = .unknown
        self.isMemberA = false
        self.isMemberB = false
        self.partnerUID = nil
        self.detachSetupListener()
        self.detachUserListener()
        self.currentSetupPhaseRaw = nil
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

    /// Pair is finalized when memberB is a non-empty string OR finalizedAt exists (not null).
    private func isPairFinalized(pairId: String) async -> Bool {
        do {
            let snap = try await db.collection("pairs").document(pairId).getDocument()
            guard let data = snap.data() else { return false }
            if let memberB = data["memberB"] as? String, !memberB.isEmpty { return true }
            if let finalizedAt = data["finalizedAt"], !(finalizedAt is NSNull) { return true }
            return false
        } catch {
            return false
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
                let finalized = await self.isPairFinalized(pairId: pid)
                self.pairingLoadState = finalized ? .paired : .unpaired
                // Resolve role if possible
                await self.resolveRoleForCurrentUser(pairId: pid, uid: uid)
                // Also resolve partner UID
                await self.resolvePartnerUID(pairId: pid, uid: uid)
                // If finalized, attach setup listener and ensure setup doc
                if finalized {
                    await self.ensureInitialSetupPhase(pairId: pid)
                    self.attachSetupListener(for: pid)
                } else {
                    self.detachSetupListener()
                    self.currentSetupPhaseRaw = nil
                }
            } else {
                self.pairId = nil
                self.pairingLoadState = .unpaired
                self.isMemberA = false
                self.isMemberB = false
                self.partnerUID = nil
                self.detachSetupListener()
                self.currentSetupPhaseRaw = nil
            }
            return true
        } catch {
            self.pairId = nil
            self.pairingLoadState = .unpaired
            self.isMemberA = false
            self.isMemberB = false
            self.partnerUID = nil
            self.detachSetupListener()
            self.currentSetupPhaseRaw = nil
            return false
        }
    }

    // MARK: - Pairing

    private var pairsCollection: CollectionReference { db.collection("pairs") }
    private var pairSpacesCollection: CollectionReference { db.collection("pairSpaces") }

    private func observePairMembership(uid: String) {
        detachUserListener()
        userListener = userDoc(uid: uid).addSnapshotListener { [weak self] snapshot, _ in
            guard let self else { return }
            guard let data = snapshot?.data() else { return }
            let pid = data["pairId"] as? String
            Task { @MainActor in
                if let pid, !pid.isEmpty {
                    self.pairId = pid
                    let finalized = await self.isPairFinalized(pairId: pid)
                    self.pairingLoadState = finalized ? .paired : .unpaired
                    await self.resolveRoleForCurrentUser(pairId: pid, uid: uid)
                    await self.resolvePartnerUID(pairId: pid, uid: uid)
                    // Ensure setup doc exists when finalized
                    if finalized {
                        await self.ensureInitialSetupPhase(pairId: pid)
                        self.attachSetupListener(for: pid)
                    } else {
                        self.detachSetupListener()
                        self.currentSetupPhaseRaw = nil
                    }
                } else {
                    self.pairId = nil
                    self.pairingLoadState = .unpaired
                    self.isMemberA = false
                    self.isMemberB = false
                    self.partnerUID = nil
                    self.detachSetupListener()
                    self.currentSetupPhaseRaw = nil
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
                    errorPtr?.pointee = NSError(domain: "whistl", code: 1001, userInfo: [NSLocalizedDescriptionKey: PairingError.alreadyPaired.errorDescription ?? "Already paired"])
                    return nil
                }
                // Create pair doc (not finalized yet; memberB absent)
                txn.setData([
                    "createdAt": FieldValue.serverTimestamp(),
                    "inviteCode": code,
                    "memberA": uid,
                    "memberB": FieldValue.delete(),   // ensure absent if previously existed
                    "finalizedAt": FieldValue.delete()
                ], forDocument: pairRef, merge: true)

                // Create shared space doc
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
        // After creation, not finalized yet; keep state as unpaired
        Task { @MainActor in
            self.pairId = pairRef.documentID
            self.inviteCode = code
            self.pairingLoadState = .unpaired
            // Creator is memberA by definition
            self.isMemberA = true
            self.isMemberB = false
            self.partnerUID = nil
            self.detachSetupListener()
            self.currentSetupPhaseRaw = nil
        }
    }

    func joinPair(using code: String) async throws {
        guard let user = Auth.auth().currentUser else { throw PairingError.notAuthenticated }
        let uid = user.uid
        let trimmed = code.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PairingError.invalidCode }

        // Query pair by inviteCode
        let query = try await pairsCollection.whereField("inviteCode", isEqualTo: trimmed).limit(to: 1).getDocuments()
        guard let doc = query.documents.first else { throw PairingError.codeNotFound }
        let pairRef = doc.reference
        let spaceRef = pairSpacesCollection.document(pairRef.documentID)
        let setupRef = spaceRef.collection("setup").document("current")

        try await db.runTransaction { txn, errorPtr in
            do {
                // Ensure user is not already paired
                let userSnap = try txn.getDocument(self.userDoc(uid: uid))
                if let existing = userSnap.data()?["pairId"] as? String, !existing.isEmpty {
                    errorPtr?.pointee = NSError(domain: "whistl", code: 1002, userInfo: [NSLocalizedDescriptionKey: PairingError.alreadyPaired.errorDescription ?? "Already paired"])
                    return nil
                }

                // Load pair doc
                let pairSnap = try txn.getDocument(pairRef)
                guard var data = pairSnap.data() else {
                    errorPtr?.pointee = NSError(domain: "whistl", code: 1003, userInfo: [NSLocalizedDescriptionKey: PairingError.codeNotFound.errorDescription ?? "Invite code not found"])
                    return nil
                }
                // Ensure there's a free slot
                if let memberB = data["memberB"] as? String, !memberB.isEmpty {
                    errorPtr?.pointee = NSError(domain: "whistl", code: 1004, userInfo: [NSLocalizedDescriptionKey: PairingError.pairFull.errorDescription ?? "Pair is full"])
                    return nil
                }
                // Set memberB and finalize
                data["memberB"] = uid
                data["finalizedAt"] = FieldValue.serverTimestamp()
                // remove inviteCode so it can't be reused
                data["inviteCode"] = FieldValue.delete()
                txn.setData(data, forDocument: pairRef, merge: true)

                // Update user with pairId
                let pairId = pairRef.documentID
                txn.setData(["pairId": pairId], forDocument: self.userDoc(uid: uid), merge: true)

                // Initialize setup/current with server-controlled phase
                txn.setData([
                    "step": "appSelection",
                    "stepIndex": 0,
                    "answers": [:],
                    "approvals": [:],
                    "submitted": [:],
                    "approvedAnswers": [:],
                    "phase": SetupPhase.awaitingASubmission.rawValue,
                    "updatedAt": FieldValue.serverTimestamp()
                ], forDocument: setupRef, merge: true)

                return nil
            } catch {
                errorPtr?.pointee = error as NSError
                return nil
            }
        }

        // After join, the pair is finalized; mark paired
        Task { @MainActor in
            self.pairId = pairRef.documentID
            self.inviteCode = nil
            self.pairingLoadState = .paired
            self.isMemberA = false
            self.isMemberB = true
            await self.resolvePartnerUID(pairId: pairRef.documentID, uid: uid)
            await self.ensureInitialSetupPhase(pairId: pairRef.documentID)
            self.attachSetupListener(for: pairRef.documentID)
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

    // Ensure the setup doc exists with a valid phase when pair is finalized (idempotent)
    func ensureInitialSetupPhase(pairId: String) async {
        let setupRef = pairSpacesCollection.document(pairId).collection("setup").document("current")
        do {
            let snap = try await setupRef.getDocument()
            if let data = snap.data() {
                var writes: [String: Any] = [:]
                if data["phase"] == nil {
                    writes["phase"] = SetupPhase.awaitingASubmission.rawValue
                }
                if let step = data["step"] as? String,
                   !(step == "appSelection" || step == "weeklySchedule") {
                    writes["step"] = "appSelection"
                    writes["stepIndex"] = 0
                    writes["answers"] = [:]
                    writes["approvals"] = [:]
                    writes["submitted"] = [:]
                    writes["approvedAnswers"] = [:]
                }
                if !writes.isEmpty {
                    writes["updatedAt"] = FieldValue.serverTimestamp()
                    try await setupRef.setData(writes, merge: true)
                }
            } else {
                // Create minimal doc with correct step
                try await setupRef.setData([
                    "step": "appSelection",
                    "stepIndex": 0,
                    "answers": [:],
                    "approvals": [:],
                    "submitted": [:],
                    "approvedAnswers": [:],
                    "phase": SetupPhase.awaitingASubmission.rawValue,
                    "updatedAt": FieldValue.serverTimestamp()
                ])
            }
        } catch {
            // Best-effort; Security Rules should still protect transitions.
        }
    }

    // Resolve current user's role (A or B) by reading pairs/{pairId}
    func resolveRoleForCurrentUser(pairId: String, uid: String) async {
        do {
            let snap = try await pairsCollection.document(pairId).getDocument()
            guard let data = snap.data() else { return }
            let memberA = data["memberA"] as? String
            let memberB = data["memberB"] as? String
            await MainActor.run {
                self.isMemberA = (memberA == uid)
                self.isMemberB = (memberB == uid)
            }
        } catch {
            await MainActor.run {
                self.isMemberA = false
                self.isMemberB = false
            }
        }
    }

    // Resolve partner UID from pairs/{pairId}
    func resolvePartnerUID(pairId: String, uid: String) async {
        do {
            let snap = try await pairsCollection.document(pairId).getDocument()
            guard let data = snap.data() else { return }
            let memberA = data["memberA"] as? String
            let memberB = data["memberB"] as? String
            let partner = (memberA == uid) ? memberB : memberA
            await MainActor.run {
                self.partnerUID = partner
            }
        } catch {
            await MainActor.run { self.partnerUID = nil }
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

    // MARK: - Setup listener (pairSpaces/{pairId}/setup/current)

    private func attachSetupListener(for pairId: String) {
        detachSetupListener()
        let ref = pairSpacesCollection.document(pairId).collection("setup").document("current")
        setupListener = ref.addSnapshotListener { [weak self] snapshot, _ in
            guard let self else { return }
            guard let data = snapshot?.data() else { return }
            let phase = data["phase"] as? String
            Task { @MainActor in
                self.currentSetupPhaseRaw = phase
            }
        }
    }

    private func detachSetupListener() {
        setupListener?.remove()
        setupListener = nil
    }

    private func detachUserListener() {
        userListener?.remove()
        userListener = nil
    }
}

