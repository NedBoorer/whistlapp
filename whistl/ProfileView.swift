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
        VStack(spacing: 12) {
            Text("Hi\(greetingName)")
                .font(.largeTitle.bold())
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("Welcome! You are logged in.")
                .font(.headline)
                .padding(.bottom, 12)

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
        .padding()
    }

    private var greetingName: String {
        let name = appController.currentDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "" : " \(name)"
    }
}

#Preview {
    ProfileView().environment(AppController())
}
