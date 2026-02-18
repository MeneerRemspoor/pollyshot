//  PollyshotApp.swift
//  Pollyshot
//
//  Fixes Scene/ViewBuilder issues by:
//  - Removing illegal `return` inside the MenuBarExtra builder
//  - Wiring hotkey sync via a hidden view that can use .onAppear/.onChange
//

import SwiftUI
import AppKit

private struct SettingsTitleView: View {
    var body: some View {
        HStack(spacing: 6) {
            Text("Pollyshot")
                .font(.headline)
                .fontWeight(.semibold)

            Text("(Beta)")
                .font(.headline)
                .fontWeight(.regular)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    private init() {}

    func show<Content: View>(rootView: Content, title: String = "Settings") {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hosting)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // 10 fixed slots: reduce vertical size to avoid dead space
        window.setContentSize(NSSize(width: 680, height: 320))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()

        // Avoid duplicate title text in the titlebar (left title + custom title view).
        // We'll draw our own title view, so clear the window title string.
        window.title = ""

        // Custom title view: "Pollyshot" + lighter "(Beta)".
        let titleView = NSHostingView(rootView: SettingsTitleView())
        titleView.translatesAutoresizingMaskIntoConstraints = false

        if let titlebarView = window.standardWindowButton(.closeButton)?.superview {
            titlebarView.addSubview(titleView)

            // Left-align in the titlebar, but leave enough space so it never overlaps
            // the traffic-light window controls (and their active/inactive layout changes).
            if let closeButton = window.standardWindowButton(.closeButton),
               let minimizeButton = window.standardWindowButton(.miniaturizeButton),
               let zoomButton = window.standardWindowButton(.zoomButton) {

                // Use the right-most control (zoom) as the anchor and add padding.
                NSLayoutConstraint.activate([
                    titleView.leadingAnchor.constraint(equalTo: zoomButton.trailingAnchor, constant: 12),
                    titleView.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
                ])

                // Ensure the title doesn't intrude back into the controls area.
                titleView.setContentHuggingPriority(.defaultHigh, for: .horizontal)
                titleView.setContentCompressionResistancePriority(.required, for: .horizontal)

                // Keep the standard buttons on top visually.
                closeButton.superview?.addSubview(closeButton)
                minimizeButton.superview?.addSubview(minimizeButton)
                zoomButton.superview?.addSubview(zoomButton)
            } else {
                NSLayoutConstraint.activate([
                    titleView.leadingAnchor.constraint(equalTo: titlebarView.leadingAnchor, constant: 84),
                    titleView.centerYAnchor.constraint(equalTo: titlebarView.centerYAnchor),
                ])
            }
        }

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct PollyshotApp: App {
    @StateObject private var slotStore = SlotStore()

    init() {
        DispatchQueue.main.async {
            HotKeyManager.shared.register()
        }
    }

    var body: some Scene {
        MenuBarExtra("Pollyshot", image: "MenuBarIcon") {
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

        // Keep the Settings scene so Cmd+, and the standard app menu can still work when it does.
        // We also provide an explicit NSWindow-based Settings window for reliability from MenuBarExtra.
        Settings {
            SettingsView()
                .environmentObject(slotStore)
                .frame(minWidth: 680, minHeight: 420)
        }
    }

    private func openSettingsReliably() {
        // Use an explicit NSWindow so Settings always opens from a menu bar app.
        SettingsWindowController.shared.show(
            rootView: SettingsView().environmentObject(slotStore),
            title: "Pollyshot Settings"
        )
    }

    private func settingsButton() -> some View {
        Button("Settings…") {
            openSettingsReliably()
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
