//
//  ContentView.swift
//  whistl
//
//  Created by Ned Boorer on 8/9/2025.
//

import SwiftUI

struct ContentView: View {
    @Environment(AppController.self) private var appController

    // Keep brand tint consistent
    private let accent = Color(red: 0.12, green: 0.49, blue: 0.98)

    var body: some View {
        Group {
            switch appController.authState {
            case .undefined:
                ProgressView()
            case .notAuthenticated:
                NavigationStack {
                    Authview()
                }
                .tint(accent)
            case .authenticated:
                NavigationStack {
                    ProfileView()
                        .navigationTitle("whistl")
                        .toolbar {
                            ToolbarItem(placement: .principal) {
                                Text("whistl")
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundStyle(accent)
                            }
                        }
                }
                .tint(accent)
            }
        }
    }
}

#Preview {
    ContentView().environment(AppController())
}
