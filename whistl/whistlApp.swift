//
//  whistlApp.swift
//  whistl
//

import SwiftUI
import FirebaseCore

@main
struct whistlApp: App {
    @State private var appController: AppController
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @State private var showSplash: Bool = true

    init() {
        let controller = AppController()
        self._appController = State(initialValue: controller)
        AppDelegate.sharedAppController = controller
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if showSplash {
                    SplashView {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            showSplash = false
                        }
                    }
                } else {
                    ContentView()
                        .task {
                            WhistlNotifier.requestAuthorizationIfNeeded()
                        }
                }
            }
            .environment(appController)
        }
    }
}
