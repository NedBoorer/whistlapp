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
    // Create a single shared AppController
    @State private var appController: AppController

    // Inject AppDelegate and pass the same controller into it so it can start listening after Firebase config
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        let controller = AppController()
        self._appController = State(initialValue: controller)
        // Pass reference into AppDelegate before application(_:didFinishLaunching...) runs
        AppDelegate.sharedAppController = controller
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    WhistlNotifier.requestAuthorizationIfNeeded()
                }
                .environment(appController) // inject controller once
                // No need to call listenToAuthChanges here anymore
        }
    }
}
