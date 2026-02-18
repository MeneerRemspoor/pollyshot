//
//  PollyshotApp.swift
//  Pollyshot
//
//  Created by Jeroen van der Poll on 18/02/2026.
//

import SwiftUI
import AppKit

@main
struct PollyshotApp: App {
    init() {
        DispatchQueue.main.async {
            HotKeyManager.shared.register()
        }
    }

    var body: some Scene {
        MenuBarExtra("Pollyshot", systemImage: "sparkles") {
            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
        .commands {
            CommandMenu("Quick Paste") {
                Button("Paste in Notes") {
                    HotKeyManager.shared.handleHotKeyPressed(targetBundleID: "com.apple.Notes")
                }
                .keyboardShortcut("1", modifiers: [.command, .option, .shift])

                Button("Paste in Text Editor") {
                    HotKeyManager.shared.handleHotKeyPressed(targetBundleID: "com.apple.TextEdit")
                }
                .keyboardShortcut("2", modifiers: [.command, .option, .shift])
            }
        }
    }
}

