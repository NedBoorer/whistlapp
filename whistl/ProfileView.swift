//
//  ProfileView.swift
//  whistl
//
//  Created by Ned Boorer on 8/9/2025.
//

import SwiftUI

struct ProfileView: View {
    @Environment(AppController.self) private var appController

    var body: some View {
        VStack {
            Text("Welcome! You are logged in.")
                .font(.headline)
                .padding()

            Button("Logout") {
                do {
                    try appController.signOut()
                } catch {
                    print("Logout error:", error.localizedDescription)
                }
            }
            .buttonStyle(.bordered)
            .padding()
        }
    }
}

#Preview {
    ProfileView().environment(AppController())
}
