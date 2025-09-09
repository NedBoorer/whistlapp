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
                    // Only show Profile when pairing is confirmed.
                    if appController.pairingLoadState == .paired {
                        NavigationStack {
                            ProfileView()
                                .navigationTitle("whistl")
                                .navigationBarTitleDisplayMode(.inline)
                                .toolbar {
                                    ToolbarItem(placement: .principal) {
                                        Text("whistl")
                                            .font(.system(size: 20, weight: .bold, design: .rounded))
                                            .foregroundStyle(brand.accent)
                                    }
                                }
                        }
                        .tint(brand.accent)
                    } else {
                        // While loading or unpaired, guide to pairing.
                        NavigationStack {
                            PairingGateView()
                                .navigationTitle("Link with a partner")
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
