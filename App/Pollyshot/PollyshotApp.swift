//
//  PollyshotApp.swift
//  Pollyshot
//
//  Fixes Scene/ViewBuilder issues by:
//  - Removing illegal `return` inside the MenuBarExtra builder
//  - Wiring hotkey sync via a hidden view that can use .onAppear/.onChange
//

import SwiftUI
import AppKit

@main
struct PollyshotApp: App {
    @StateObject private var slotStore = SlotStore()

    init() {
        DispatchQueue.main.async {
            HotKeyManager.shared.register()
        }
    }

    var body: some Scene {
        MenuBarExtra("Pollyshot", systemImage: "sparkles") {
            HotkeySyncView()
                .environmentObject(slotStore)

            let items = slotStore.orderedAssignedSlots()

            if items.isEmpty {
                Text("No destinations assigned")
                    .foregroundStyle(.secondary)

                Divider()

                settingsButton()

                Divider()

                Button("Quit") { NSApp.terminate(nil) }
            } else {
                ForEach(items) { assignment in
                    // Only show enabled items in the menu; disabled items remain configurable in Settings.
                    if assignment.isEnabled {
                        Button("Capture to \(assignment.name)") {
                            HotKeyManager.shared.handleHotKeyPressed(targetBundleID: assignment.bundleID)
                        }
                        .keyboardShortcut(
                            assignment.slot.keyboardShortcutKeyEquivalent,
                            modifiers: [.command, .option, .shift]
                        )
                    }
                }

                Divider()

                settingsButton()

                Divider()

                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                settingsButton()
                    .keyboardShortcut(",", modifiers: [.command])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(slotStore)
                .frame(minWidth: 680, minHeight: 420)
        }
    }

    private func settingsButton() -> some View {
        Button("Settings…") {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        .keyboardShortcut(",", modifiers: [.command])
    }
}

private struct HotkeySyncView: View {
    @EnvironmentObject private var slotStore: SlotStore

    var body: some View {
        // Hidden view purely for lifecycle hooks.
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                HotKeyManager.shared.applySlots(slotStore.assignments)
            }
            .onChange(of: slotStore.assignments) { newValue in
                HotKeyManager.shared.applySlots(newValue)
            }
    }
}
