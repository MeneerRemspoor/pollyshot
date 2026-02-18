//
//  SettingsView.swift
//  Pollyshot
//
//  Dedicated settings UI for editing stable shortcut slots (Cmd + Option + Shift + 1..9,0).
//  Slots are stable: clearing Slot 2 does not renumber Slot 3/4/etc.
//
//  This view expects a SlotStore to be injected via `.environmentObject(SlotStore())`.
//
//

import SwiftUI

struct SettingsView: View {
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

            Text(slot.shortcutHint)
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

                Text("Fixed shortcut: \(slot.shortcutHint)")
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 4)

            Form {
                Section("Destination") {
                    TextField("Name", text: $name)
                        .onChange(of: name) { _ in pushUpdate() }

                    TextField("Bundle ID", text: $bundleID)
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
                    Text(
                        """
                        Bundle ID examples:
                        • Notes: com.apple.Notes
                        • TextEdit: com.apple.TextEdit
                        • Slack: com.tinyspeck.slackmacgap
                        """
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                    Text("If an app is uninstalled or moved, the slot will show as Missing. You can relink it later by editing the bundle ID.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Section("Permissions") {
                    Text(
                        """
                        To paste into other apps, enable Accessibility permission:
                        System Settings → Privacy & Security → Accessibility → enable Pollyshot
                        """
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                    Text(
                        """
                        If interactive area capture doesn’t work, enable Screen Recording permission:
                        System Settings → Privacy & Security → Screen Recording → enable Pollyshot
                        """
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                }
            }
            .padding(.trailing, 8)

            Spacer()
        }
        .padding(16)
        .onAppear { loadFromAssignment(assignment) }
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

        // Allow partial editing without forcing clears.
        if trimmedName.isEmpty && trimmedBundle.isEmpty {
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
