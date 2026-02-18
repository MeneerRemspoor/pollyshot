//
//  SettingsView.swift
//  Pollyshot
//
//  Simplified Settings UI:
//  - Sidebar: shows app icon + app name when assigned; "Choose App…" placeholder is lighter
//  - Disabled: uses strikethrough styling (no "Disabled" label)
//  - Shortcuts: always secondary style
//  - Selecting an empty slot opens the app picker immediately
//  - Detail: if empty shows only "Choose App…"; if assigned shows actions row above fields
//  - Clear slot: destructive, right-aligned
//  - Enabled: switch toggle style

import SwiftUI
import AppKit
import UniformTypeIdentifiers

private enum UI {
    static let sidebarMinWidth: CGFloat = 240
    static let detailMaxWidth: CGFloat = 560
    static let sidebarSelectionFillOpacity: CGFloat = 0.22
    static let sidebarSelectionCornerRadius: CGFloat = 10
}

struct SettingsView: View {
    @EnvironmentObject private var store: SlotStore
    @State private var selection: ShortcutSlot? = .one

    var body: some View {
        NavigationSplitView {
            List(ShortcutSlot.allInHotkeyOrder, selection: $selection) { slot in
                Button {
                    selection = slot
                    if store.assignment(for: slot) == nil {
                        // Open the picker immediately for empty slots.
                        NotificationCenter.default.post(
                            name: .pollyshotOpenPickerForSlot,
                            object: nil,
                            userInfo: ["slotRawValue": slot.rawValue]
                        )
                    }
                } label: {
                    SlotSidebarRow(
                        slot: slot,
                        assignment: store.assignment(for: slot),
                        isSelected: selection == slot
                    )
                }
                .buttonStyle(.plain)
                .tag(slot as ShortcutSlot?)
            }
            .listStyle(.sidebar)
            .frame(minWidth: UI.sidebarMinWidth)
        } detail: {
            if let slot = selection {
                ScrollView {
                    SlotDetailEditor(
                        slot: slot,
                        assignment: store.assignment(for: slot),
                        onChange: { updated in
                            if let updated {
                                store.set(updated)
                            } else {
                                store.clear(slot: slot)
                            }
                        }
                    )
                    .frame(maxWidth: UI.detailMaxWidth, alignment: .topLeading)
                    .padding(16)
                }
            } else {
                Text("Select a slot")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(16)
            }
        }
    }
}

private struct SlotSidebarRow: View {
    let slot: ShortcutSlot
    let assignment: SlotAssignment?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            if let assignment {
                Image(nsImage: NSWorkspace.shared.icon(forFile: NSWorkspace.shared.urlForApplication(withBundleIdentifier: assignment.bundleID)?.path ?? ""))
                    .resizable()
                    .frame(width: 18, height: 18)
                    .cornerRadius(4)
                    .opacity(assignment.isEnabled ? 1.0 : 0.7)
            }

            VStack(alignment: .leading, spacing: 2) {
                if let assignment, !assignment.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(assignment.name)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .strikethrough(!assignment.isEnabled)
                } else {
                    Text("Choose App…")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .opacity(0.75)
                }

                if assignment?.isMissing == true {
                    Text("Missing")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Spacer(minLength: 8)

            Text(slot.shortcutHint)
                .foregroundStyle(.secondary)
                .font(.callout)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background {
            if isSelected, assignment != nil {
                RoundedRectangle(cornerRadius: UI.sidebarSelectionCornerRadius, style: .continuous)
                    .fill(Color.accentColor.opacity(UI.sidebarSelectionFillOpacity))
            }
        }
        .contentShape(Rectangle())
    }
}

private struct SlotDetailEditor: View {
    let slot: ShortcutSlot
    let assignment: SlotAssignment?
    let onChange: (SlotAssignment?) -> Void

    @State private var name: String = ""
    @State private var bundleID: String = ""
    @State private var isEnabled: Bool = true
    @State private var message: String? = nil

    private var isMissing: Bool { assignment?.isMissing == true }
    private var isEmpty: Bool { assignment == nil && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && bundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {

                    // If empty: only show Choose App… and let it span full width.
                    if assignment == nil && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && bundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button("Choose App…") {
                            pickAppAndAutofill()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        // Actions row first
                        HStack(spacing: 10) {
                            Button(isMissing ? "Relink App…" : "Choose App…") {
                                pickAppAndAutofill()
                            }

                            Button("Test") {
                                let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !trimmed.isEmpty else {
                                    message = "Bundle ID is required to test."
                                    return
                                }
                                HotKeyManager.shared.handleHotKeyPressed(targetBundleID: trimmed)
                            }
                            .disabled(bundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            Spacer()

                            Toggle("Enabled", isOn: $isEnabled)
                                .toggleStyle(.switch)
                        }

                        LabeledContent("Name") {
                            TextField("App name", text: $name)
                                .frame(maxWidth: .infinity)
                        }

                        LabeledContent("Bundle ID") {
                            TextField("com.example.App", text: $bundleID)
                                .disableAutocorrection(true)
                                .frame(maxWidth: .infinity)
                        }

                        if isMissing {
                            Text("This app can’t be found. Relink it, or clear the slot.")
                                .font(.callout)
                                .foregroundStyle(.orange)
                        }

                        if let message {
                            Text(message)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }

                        Divider()

                        HStack {
                            Spacer()
                            Button("Clear slot", role: .destructive) {
                                onChange(nil)
                                loadFromAssignment(nil)
                            }
                        }
                    }
                }
                .padding(12)
            }
        }
        .onAppear { loadFromAssignment(assignment) }
        .onChange(of: assignment) { newValue in
            loadFromAssignment(newValue)
        }
        .onChange(of: name) { _ in pushUpdate() }
        .onChange(of: bundleID) { _ in pushUpdate() }
        .onChange(of: isEnabled) { _ in pushUpdate() }
        .onReceive(NotificationCenter.default.publisher(for: .pollyshotOpenPickerForSlot)) { note in
            guard let raw = note.userInfo?["slotRawValue"] as? Int,
                  raw == slot.rawValue,
                  assignment == nil else { return }
            pickAppAndAutofill()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(slot.shortcutHint)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private func loadFromAssignment(_ a: SlotAssignment?) {
        message = nil
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
        message = nil

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBundle = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)

        // Allow an empty editor without forcing a clear.
        if trimmedName.isEmpty && trimmedBundle.isEmpty {
            return
        }

        guard !trimmedName.isEmpty, !trimmedBundle.isEmpty else {
            message = "Name and Bundle ID are required."
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

    private func pickAppAndAutofill() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Choose"

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return }

        guard let bundle = Bundle(url: url) else {
            message = "Could not read app bundle."
            return
        }

        guard let pickedBundleID = bundle.bundleIdentifier, !pickedBundleID.isEmpty else {
            message = "Selected app has no bundle identifier."
            return
        }

        let info = bundle.infoDictionary
        let displayName =
            (info?["CFBundleDisplayName"] as? String) ??
            (info?["CFBundleName"] as? String) ??
            url.deletingPathExtension().lastPathComponent

        name = displayName
        bundleID = pickedBundleID
        message = nil
        pushUpdate()
    }
}

private extension Notification.Name {
    static let pollyshotOpenPickerForSlot = Notification.Name("pollyshot.openPickerForSlot")
}
