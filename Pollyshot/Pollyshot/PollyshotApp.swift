//
//  PollyshotApp.swift
//  Pollyshot
//
//  Refactor: stable 10 shortcut slots (Cmd+Option+Shift+1..0) and settings UI to assign apps to slots.
//  Menu bar dropdown is driven by slot assignments.
//  Hotkeys are applied from SlotStore on startup and whenever assignments change.
//

import SwiftUI
import AppKit

// MARK: - Slots

/// The fixed shortcut slots. These are stable: deleting/clearing a slot does not shift others.
enum ShortcutSlot: Int, CaseIterable, Identifiable, Codable, Equatable {
    case one = 1
    case two = 2
    case three = 3
    case four = 4
    case five = 5
    case six = 6
    case seven = 7
    case eight = 8
    case nine = 9
    case zero = 0

    var id: Int { rawValue }

    /// Display number users expect.
    var displayNumber: String {
        switch self {
        case .zero: return "0"
        default: return String(rawValue)
        }
    }

    /// Display label for UI.
    var displayName: String {
        "Slot \(displayNumber)"
    }

    /// The digit used for SwiftUI `.keyboardShortcut`.
    var keyboardShortcutKeyEquivalent: KeyEquivalent {
        switch self {
        case .one: return "1"
        case .two: return "2"
        case .three: return "3"
        case .four: return "4"
        case .five: return "5"
        case .six: return "6"
        case .seven: return "7"
        case .eight: return "8"
        case .nine: return "9"
        case .zero: return "0"
        }
    }

    static let allInHotkeyOrder: [ShortcutSlot] = [.one, .two, .three, .four, .five, .six, .seven, .eight, .nine, .zero]
}

/// A slot assignment: which app to activate and paste into.
struct SlotAssignment: Identifiable, Codable, Equatable {
    var id: ShortcutSlot { slot }
    var slot: ShortcutSlot
    var name: String
    var bundleID: String
    var isEnabled: Bool = true

    /// When true, the bundleID doesn't resolve to an installed app (best-effort check).
    var isMissing: Bool = false
}

// MARK: - Persistence

@MainActor
final class SlotStore: ObservableObject {
    @Published var assignments: [ShortcutSlot: SlotAssignment] = [:] {
        didSet { persist() }
    }

    private let defaultsKey = "pollyshot.slotAssignments.v1"

    init() {
        load()
        if assignments.isEmpty {
            seedDefaultsIfEmpty()
        }
        refreshMissingFlags()
    }

    func assignment(for slot: ShortcutSlot) -> SlotAssignment? {
        assignments[slot]
    }

    func set(_ assignment: SlotAssignment?) {
        guard let assignment else { return }
        assignments[assignment.slot] = assignment
        refreshMissingFlags()
    }

    func clear(slot: ShortcutSlot) {
        assignments.removeValue(forKey: slot)
    }

    func toggleEnabled(slot: ShortcutSlot, isEnabled: Bool) {
        guard var a = assignments[slot] else { return }
        a.isEnabled = isEnabled
        assignments[slot] = a
    }

    /// Returns slots with an assignment, in stable hotkey order.
    func orderedAssignedSlots() -> [SlotAssignment] {
        ShortcutSlot.allInHotkeyOrder.compactMap { assignments[$0] }
    }

    func refreshMissingFlags() {
        // Best-effort check: can we find an app for bundle ID?
        // This avoids silently deleting user config; we just mark missing.
        var changed = false
        for slot in ShortcutSlot.allInHotkeyOrder {
            guard var a = assignments[slot] else { continue }
            let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: a.bundleID)
            let missing = (appURL == nil)
            if a.isMissing != missing {
                a.isMissing = missing
                assignments[slot] = a
                changed = true
            }
        }
        if changed {
            // already persisted via didSet
        }
    }

    private func seedDefaultsIfEmpty() {
        let defaults: [SlotAssignment] = [
            SlotAssignment(slot: .one, name: "Slack", bundleID: "com.tinyspeck.slackmacgap", isEnabled: true),
            SlotAssignment(slot: .two, name: "ChatGPT", bundleID: "com.openai.chat", isEnabled: true),
            SlotAssignment(slot: .three, name: "TextEdit", bundleID: "com.apple.TextEdit", isEnabled: true),
            SlotAssignment(slot: .four, name: "Notes", bundleID: "com.apple.Notes", isEnabled: true)
        ]
        for a in defaults {
            assignments[a.slot] = a
        }
    }

    // Codable wrapper since Dictionary keys are enums.
    private struct Persisted: Codable {
        var items: [SlotAssignment]
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else {
            assignments = [:]
            return
        }
        do {
            let decoded = try JSONDecoder().decode(Persisted.self, from: data)
            assignments = Dictionary(uniqueKeysWithValues: decoded.items.map { ($0.slot, $0) })
        } catch {
            NSLog("Pollyshot: failed to decode slot assignments: \(error)")
            assignments = [:]
        }
    }

    private func persist() {
        do {
            let items = ShortcutSlot.allInHotkeyOrder.compactMap { assignments[$0] }
            let data = try JSONEncoder().encode(Persisted(items: items))
            UserDefaults.standard.set(data, forKey: defaultsKey)
        } catch {
            NSLog("Pollyshot: failed to encode slot assignments: \(error)")
        }
    }
}

// MARK: - App

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
            let items = slotStore.orderedAssignedSlots()

            if items.isEmpty {
                Text("No destinations assigned")
                    .foregroundStyle(.secondary)

                Divider()

                Button("Settings…") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                .keyboardShortcut(",", modifiers: [.command])

                Divider()

                Button("Quit") { NSApp.terminate(nil) }
                return
            }

            ForEach(items) { assignment in
                // Only show enabled items in the menu; disabled items remain configurable in Settings.
                if assignment.isEnabled {
                    Button("Capture to \(assignment.name)") {
                        HotKeyManager.shared.handleHotKeyPressed(targetBundleID: assignment.bundleID)
                    }
                    .keyboardShortcut(assignment.slot.keyboardShortcutKeyEquivalent,
                                      modifiers: [.command, .option, .shift])
                }
            }

            Divider()

            Button("Settings…") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .keyboardShortcut(",", modifiers: [.command])

            Divider()

            Button("Quit") { NSApp.terminate(nil) }
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(slotStore)
                .frame(minWidth: 680, minHeight: 420)
        }
    }
    .onAppear {
        // Apply current slot assignments to global hotkey registration.
        HotKeyManager.shared.applySlots(slotStore.assignments)
    }
    .onChange(of: slotStore.assignments) { newValue in
        // Re-register hotkeys whenever the user changes slot assignments.
        HotKeyManager.shared.applySlots(newValue)
    }
}

// MARK: - Settings UI

private struct SettingsView: View {
    @EnvironmentObject private var store: SlotStore

    @State private var selection: ShortcutSlot? = .one

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $selection) {
                Section("Shortcut Slots") {
                    ForEach(ShortcutSlot.allInHotkeyOrder) { slot in
                        SlotRow(slot: slot, assignment: store.assignment(for: slot))
                            .tag(slot as ShortcutSlot?)
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 260)

            Divider()

            if let slot = selection {
                SlotEditor(slot: slot, assignment: store.assignment(for: slot)) { newAssignment in
                    if let a = newAssignment {
                        store.set(a)
                    } else {
                        store.clear(slot: slot)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                Text("Select a slot")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Refresh") {
                    store.refreshMissingFlags()
                }
            }
        }
    }
}

private struct SlotRow: View {
    let slot: ShortcutSlot
    let assignment: SlotAssignment?

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(slot.displayName)
                    .font(.headline)

                if let assignment {
                    HStack(spacing: 6) {
                        Text(assignment.name)
                        if assignment.isMissing {
                            Text("Missing")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        } else if !assignment.isEnabled {
                            Text("Disabled")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(assignment.bundleID)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Empty")
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Visual hint for the fixed shortcut.
            Text("⌘⌥⇧\(slot.displayNumber)")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
        .padding(.vertical, 2)
    }
}

private struct SlotEditor: View {
    let slot: ShortcutSlot
    let assignment: SlotAssignment?
    var onChange: (SlotAssignment?) -> Void

    @State private var name: String = ""
    @State private var bundleID: String = ""
    @State private var isEnabled: Bool = true

    @State private var validationMessage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(slot.displayName)
                    .font(.title2)
                Text("Fixed shortcut: ⌘⌥⇧\(slot.displayNumber)")
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 4)

            Form {
                Section("Destination") {
                    TextField("Name", text: $name)
                        .onChange(of: name) { _ in pushUpdate() }

                    TextField("Bundle ID", text: $bundleID)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .onChange(of: bundleID) { _ in pushUpdate() }

                    Toggle("Enabled", isOn: $isEnabled)
                        .onChange(of: isEnabled) { _ in pushUpdate() }

                    HStack {
                        Button("Test capture") {
                            guard !bundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                                validationMessage = "Bundle ID is required to test."
                                return
                            }
                            HotKeyManager.shared.handleHotKeyPressed(targetBundleID: bundleID)
                        }

                        Button("Clear slot") {
                            onChange(nil)
                            loadFromAssignment(nil)
                        }
                        .foregroundStyle(.red)

                        Spacer()
                    }

                    if let validationMessage {
                        Text(validationMessage)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Notes") {
                    Text("Bundle ID examples:\n• Notes: com.apple.Notes\n• TextEdit: com.apple.TextEdit\n• Slack: com.tinyspeck.slackmacgap")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    Text("If an app is uninstalled or moved, the slot will show as Missing. You can relink it later by editing the bundle ID.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Section("Permissions") {
                    Text("To paste into other apps, enable Accessibility permission:\nSystem Settings → Privacy & Security → Accessibility → enable Pollyshot")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    Text("If interactive area capture doesn’t work, enable Screen Recording permission:\nSystem Settings → Privacy & Security → Screen Recording → enable Pollyshot")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(.trailing, 8)

            Spacer()
        }
        .padding(16)
        .onAppear {
            loadFromAssignment(assignment)
        }
        .onChange(of: assignment) { newValue in
            loadFromAssignment(newValue)
        }
    }

    private func loadFromAssignment(_ a: SlotAssignment?) {
        validationMessage = nil
        if let a {
            name = a.name
            bundleID = a.bundleID
            isEnabled = a.isEnabled
        } else {
            name = ""
            bundleID = ""
            isEnabled = true
        }
    }

    private func pushUpdate() {
        validationMessage = nil
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBundle = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)

        // Allow partial editing without spamming store with invalid empty bundle IDs.
        // Only persist when both fields are non-empty.
        if trimmedName.isEmpty && trimmedBundle.isEmpty {
            // Treat as empty editor state; don't force clear automatically.
            return
        }

        if trimmedName.isEmpty || trimmedBundle.isEmpty {
            validationMessage = "Name and Bundle ID are required."
            return
        }

        onChange(
            SlotAssignment(
                slot: slot,
                name: trimmedName,
                bundleID: trimmedBundle,
                isEnabled: isEnabled,
                isMissing: false
            )
        )
    }
}
