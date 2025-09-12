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
                    switch appController.pairingLoadState {
                    case .unknown:
                        // Unknown initial state; show a spinner briefly until listener updates.
                        ProgressView()
                            .tint(brand.accent)

                    case .loading:
                        // Explicit loading while fetching user profile/pair state.
                        ProgressView()
                            .tint(brand.accent)

                    case .unpaired:
                        // Require pairing to continue.
                        NavigationStack {
                            PairingGateView()
                        }
                        .tint(brand.accent)

                    case .paired:
                        // Route paired users into the shared setup flow until it completes.
                        NavigationStack {
                            SharedSetupFlowView()
                                .navigationBarTitleDisplayMode(.inline)
                        }
                        .tint(brand.accent)
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView().environment(AppController())
}
