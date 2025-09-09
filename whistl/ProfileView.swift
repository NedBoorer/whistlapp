//
//  ProfileView.swift
//  whistl
//
//  Created by Ned Boorer on 8/9/2025.
//

import SwiftUI

struct ProfileView: View {
    @Environment(AppController.self) private var appController
    private let brand = BrandPalette()

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Hi\(greetingName)")
                        .font(.largeTitle.bold())

                    Text("Welcome! You are logged in.")
                        .font(.headline)
                        .foregroundStyle(brand.secondaryText)
                }
                Spacer()
            }

            Spacer()

            Button {
                do {
                    try appController.signOut()
                } catch {
                    print("Logout error:", error.localizedDescription)
                }
            } label: {
                Text("Logout")
                    .frame(maxWidth: .infinity)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.bordered)
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
