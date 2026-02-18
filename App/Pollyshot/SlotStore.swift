//
//  SlotStore.swift
//  Pollyshot
//
//  Persists stable shortcut slot assignments (Cmd+Option+Shift+1..0) in UserDefaults.
//
//  Notes:
//  - Slots are stable. Clearing Slot 2 does not renumber others.
//  - We never auto-delete entries when an app disappears; we mark them as `isMissing`.
//  - This store is designed to be used by both the Settings UI and hotkey registration.
//

import Foundation
import AppKit
import Combine

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

    func set(_ assignment: SlotAssignment) {
        assignments[assignment.slot] = assignment
        refreshMissingFlags()
    }

    func clear(slot: ShortcutSlot) {
        assignments.removeValue(forKey: slot)
    }

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
            // Persisted via didSet.
        }
    }

    // MARK: - Persistence

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

    // MARK: - Defaults

    private func seedDefaultsIfEmpty() {
        let defaults: [SlotAssignment] = [
            SlotAssignment(slot: .one, name: "Slack", bundleID: "com.tinyspeck.slackmacgap", isEnabled: true),
            SlotAssignment(slot: .two, name: "ChatGPT", bundleID: "com.openai.chat", isEnabled: true),
            SlotAssignment(slot: .three, name: "TextEdit", bundleID: "com.apple.TextEdit", isEnabled: true),
            SlotAssignment(slot: .four, name: "Notes", bundleID: "com.apple.Notes", isEnabled: true),
        ]

        for a in defaults {
            assignments[a.slot] = a
        }
    }
}
