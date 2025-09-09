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
    // Ensure AppDelegate runs first and configures Firebase
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @State private var appController: AppController

    init() {
        // AppDelegate will call FirebaseApp.configure() in didFinishLaunching
        // Create AppController AFTER Firebase is configured at launch time.
        // SwiftUI creates the App type before application(_:didFinishLaunchingWithOptions:),
        // but this stored property is initialized here in init(), not at declaration,
        // so we defer its creation until after App is constructed.
        self._appController = State(initialValue: AppController())
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
