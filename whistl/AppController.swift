//
//  AppController.swift
//  whistl
//
//  Created by Ned Boorer on 8/9/2025.
//

import Observation
import SwiftUI
import FirebaseAuth

enum AuthState {
    case undefined, authenticated, notAuthenticated
}

@Observable
class AppController {
    var email = ""
    var password = ""
    var authState: AuthState = .undefined



    func listenToAuthChanges() {
        Auth.auth().addStateDidChangeListener { _, user in
                self.authState = user != nil ? .authenticated : .notAuthenticated
            }
        }
    

    func signUp() async throws {
        _ = try await Auth.auth().createUser(withEmail: email, password: password)
    }

    func signIn() async throws {
        _ = try await Auth.auth().signIn(withEmail: email, password: password)
    }

    func signOut() throws {
        try Auth.auth().signOut()
    }
}
