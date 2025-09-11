//
//  ContentView.swift
//  whistl
//
//  Created by Ned Boorer on 8/9/2025.
//

import SwiftUI

struct ContentView: View {
    @Environment(AppController.self) private var appController

    private let brand = BrandPalette()

    var body: some View {
        ZStack {
            brand.background()

            Group {
                switch appController.authState {
                case .undefined:
                    // While Firebase restores session or we don't know yet, show a spinner.
                    ProgressView()
                        .tint(brand.accent)

                case .notAuthenticated:
                    // Entry: Welcome -> Authview (user chooses Sign in or Create account)
                    NavigationStack {
                        WelcomeView()
                            .toolbar { }
                    }
                    .tint(brand.accent)

                case .authenticated:
                    // For testing: skip pairing/setup and go straight to home (which links to the blocker UI).
                    NavigationStack {
                        WhisprHomeView()
                            .navigationBarTitleDisplayMode(.inline)
                    }
                    .tint(brand.accent)
                }
            }
        }
    }
}

#Preview {
    ContentView().environment(AppController())
}
