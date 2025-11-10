//
//  BreatheFreeApp.swift
//  BreatheFree
//
//  Native macOS breathing exercise application
//

import SwiftUI

@main
struct BreatheFreeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 800, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            // Remove default commands
            CommandGroup(replacing: .newItem) {}
        }
    }
}
