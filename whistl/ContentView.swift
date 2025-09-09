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
                    // After sign-in:
                    // - If not paired: go to pairing flow.
                    // - If paired: go to shared rules setup.
                    NavigationStack {
                        if appController.isPaired {
                            SharedSetupFlowView()
                                .navigationBarTitleDisplayMode(.inline)
                        } else {
                            PairingGateView()
                                .navigationTitle("Link with a partner")
                                .navigationBarTitleDisplayMode(.inline)
                        }
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
