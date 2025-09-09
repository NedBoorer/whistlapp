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

    // Firestore: obtain instance lazily to avoid touching it before FirebaseApp.configure()
    private var db: Firestore {
        Firestore.firestore()
    }

    @MainActor
    func listenToAuthChanges() {
        Auth.auth().addStateDidChangeListener { _, user in
            self.authState = user != nil ? .authenticated : .notAuthenticated
            self.currentDisplayName = user?.displayName ?? ""
            if let user {
                self.loadUserProfile(uid: user.uid)
            } else {
                self.currentDisplayName = ""
            }
        }
    }

    func signUp() async throws {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)

        // current user should now exist
        // Do not write Firestore yet — wait until caller sets displayName so both stay in sync
        // Authview calls updateDisplayName(name) immediately after signUp()
        // After updateDisplayName completes, we persist to Firestore too
        // But in case caller forgets, we still attempt a write here with whatever we have
        let provisionalName = self.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !provisionalName.isEmpty {
            // Best effort: set display name if caller didn’t yet (Authview will also set it)
            try? await updateDisplayName(provisionalName)
        }
        try await saveUserProfile(uid: result.user.uid, name: Auth.auth().currentUser?.displayName ?? provisionalName, email: email)
    }

    func signIn() async throws {
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        self.currentDisplayName = result.user.displayName ?? ""
        // Refresh from Firestore for canonical profile
        await loadUserProfile(uid: result.user.uid)
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
        // Only set createdAt if the document doesn't exist yet
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
    private func loadUserProfile(uid: String) {
        Task {
            do {
                let snapshot = try await userDoc(uid: uid).getDocument()
                if let name = snapshot.data()?["name"] as? String, !name.isEmpty {
                    self.currentDisplayName = name
                }
            } catch {
                // Non-fatal: keep using auth displayName
                // print("Failed to load user profile:", error)
            }
        }
    }
}
