//
//  whistlApp.swift
//  whistl
//
//  Created by Ned Boorer on 8/9/2025.
//

import SwiftUI
import FirebaseCore

@main
struct whistlApp: App {
    @State private var appController = AppController()

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appController) // inject controller once
                .onAppear {
                        appController.listenToAuthChanges()
                    }
                }
        }
    
}
