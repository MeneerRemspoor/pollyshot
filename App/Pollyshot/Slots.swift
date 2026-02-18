//
//  Slots.swift
//  Pollyshot
//
//  Shared slot model types used by UI, persistence, and hotkey registration.
//
//  Slots are stable: clearing Slot 2 does not renumber Slot 3/4/etc.
//  Hotkeys are fixed (for now): Cmd + Option + Shift + 1..9,0
//

import SwiftUI

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

    /// Hotkey/UI order: 1..9,0
    static let allInHotkeyOrder: [ShortcutSlot] = [.one, .two, .three, .four, .five, .six, .seven, .eight, .nine, .zero]

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

    /// Convenience display of the fixed shortcut.
    var shortcutHint: String {
        "⌘⌥⇧\(displayNumber)"
    }
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

    init(
        slot: ShortcutSlot,
        name: String,
        bundleID: String,
        isEnabled: Bool = true,
        isMissing: Bool = false
    ) {
        self.slot = slot
        self.name = name
        self.bundleID = bundleID
        self.isEnabled = isEnabled
        self.isMissing = isMissing
    }
}
