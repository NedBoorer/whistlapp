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

    private var isSetupComplete: Bool {
        appController.currentSetupPhase == .complete
    }

    var body: some View {
        ZStack {
            brand.background()

            Group {
                switch appController.authState {
                case .undefined:
                    ProgressView()
                        .tint(brand.accent)

                case .notAuthenticated:
                    NavigationStack {
                        WelcomeView()
                            .toolbar { }
                    }
                    .tint(brand.accent)

                case .authenticated:
                    switch appController.pairingLoadState {
                    case .unknown, .loading:
                        ProgressView()
                            .tint(brand.accent)

                    case .unpaired:
                        NavigationStack {
                            PairingGateView()
                        }
                        .tint(brand.accent)

                    case .paired:
                        // If setup complete -> show HomeTabs. Otherwise show setup flow.
                        if isSetupComplete {
                            HomeTabs()
                        } else {
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
}

#Preview {
    ContentView().environment(AppController())
}
