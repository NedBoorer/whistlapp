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

            NavigationStack {
                WelcomeView()
                    .toolbar { }
            }
            .tint(brand.accent)
        }
    }
}

#Preview {
    ContentView().environment(AppController())
}
