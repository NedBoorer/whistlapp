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
                    ProgressView()
                        .tint(brand.accent)

                case .notAuthenticated:
                    NavigationStack {
                        Authview()
                            .toolbar { }
                    }
                    .tint(brand.accent)

                case .authenticated:
                    // Route based on pairing status:
                    // If not paired, go to pairing flow; if paired, show welcome/confirmation.
                    NavigationStack {
                        if appController.isPaired {
                            PairedWelcomeView()
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
