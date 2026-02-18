/// HotKeyManager.swift
/// Pollyshot
///
/// Drives global hotkey registration from stable slot assignments (Cmd+Option+Shift+1..0).
/// - Slots are stable: removing one does not shift others.
/// - Only registers assigned + enabled + non-missing slots.
/// - When triggered: interactive area capture to clipboard, activate target app, paste (Cmd+V).
///
/// Permissions:
/// - Screen Recording: may be required for `screencapture` on newer macOS versions.
/// - Accessibility: required to synthesize Cmd+V into the target app.
///
import Foundation
import AppKit
import Carbon.HIToolbox

// Slot models are defined in `Models/Slots.swift` and shared with the UI/persistence.

final class HotKeyManager {
    static let shared = HotKeyManager()

    private static let signature: OSType = OSType(0x504F4C59) // 'POLY'

    private var handlerRef: EventHandlerRef?
    private var hotKeyRefMap: [UInt32: EventHotKeyRef] = [:]

    /// Prevent re-entrancy (screenshot UI + app activation + paste).
    private let actionQueue = DispatchQueue(label: "com.pollyshot.hotkey.action", qos: .userInitiated)
    private var isRunningAction = false

    /// Latest slot configuration used for routing hotkeys.
    /// Keyed by slot; used by the hotkey handler to resolve bundle IDs.
    private var assignmentsBySlot: [ShortcutSlot: SlotAssignment] = [:]

    private init() {}

    // MARK: Public API

    /// Call once at startup to install the event handler.
    /// You still must call `applySlots(_:)` to actually register hotkeys.
    func register() {
        guard handlerRef == nil else { return }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            HotKeyManager.hotKeyHandler,
            1,
            &eventSpec,
            nil,
            &handlerRef
        )
    }

    /// Updates slot assignments and re-registers global hotkeys accordingly.
    /// Only registers slots that are assigned + enabled + non-missing.
    @MainActor
    func applySlots(_ assignments: [ShortcutSlot: SlotAssignment]) {
        assignmentsBySlot = assignments
        reregisterHotKeys()
    }

    /// Programmatic trigger for menu buttons / tests.
    func handleHotKeyPressed(targetBundleID: String) {
        actionQueue.async { [weak self] in
            guard let self else { return }
            self.captureActivatePaste(targetBundleID: targetBundleID)
        }
    }

    // MARK: HotKey event handler

    private static let hotKeyHandler: @convention(c) (EventHandlerCallRef?, EventRef?, UnsafeMutableRawPointer?) -> OSStatus = { _, event, _ in
        guard let event else { return noErr }

        var hk = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hk
        )

        guard status == noErr, hk.signature == HotKeyManager.signature else { return noErr }

        DispatchQueue.main.async {
            HotKeyManager.shared.handleHotKeyID(hk.id)
        }

        return noErr
    }

    private func handleHotKeyID(_ id: UInt32) {
        guard let slot = slotForHotKeyID(id) else {
            NSLog("Pollyshot: unknown hotkey id \(id) triggered")
            return
        }

        guard let assignment = assignmentsBySlot[slot] else {
            // Empty slot should not be registered, but guard anyway.
            NSLog("Pollyshot: hotkey \(slot.displayNumber) triggered but slot is empty")
            return
        }

        guard assignment.isEnabled, !assignment.isMissing else {
            NSLog("Pollyshot: hotkey \(slot.displayNumber) triggered but slot is disabled/missing")
            return
        }

        handleHotKeyPressed(targetBundleID: assignment.bundleID)
    }

    // MARK: Registration

    @MainActor
    private func reregisterHotKeys() {
        unregisterAllHotKeys()

        let modifiers: UInt32 = UInt32(cmdKey | optionKey | shiftKey)

        for slot in ShortcutSlot.allInHotkeyOrder {
            guard let assignment = assignmentsBySlot[slot] else { continue }
            guard assignment.isEnabled, !assignment.isMissing else { continue }

            let hotKeyID = hotKeyIDForSlot(slot)
            var ref: EventHotKeyRef?

            let status = RegisterEventHotKey(
                keyCodeForSlot(slot),
                modifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &ref
            )

            if status == noErr, let ref {
                hotKeyRefMap[hotKeyID.id] = ref
            } else {
                NSLog("Pollyshot: failed to register hotkey for slot \(slot.displayNumber) (status=\(status))")
            }
        }
    }

    @MainActor
    private func unregisterAllHotKeys() {
        for (_, ref) in hotKeyRefMap {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefMap.removeAll()
    }

    private func hotKeyIDForSlot(_ slot: ShortcutSlot) -> EventHotKeyID {
        EventHotKeyID(signature: Self.signature, id: hotKeyIDValueForSlot(slot))
    }

    private func slotForHotKeyID(_ id: UInt32) -> ShortcutSlot? {
        switch id {
        case 1: return .one
        case 2: return .two
        case 3: return .three
        case 4: return .four
        case 5: return .five
        case 6: return .six
        case 7: return .seven
        case 8: return .eight
        case 9: return .nine
        case 10: return .zero
        default: return nil
        }
    }

    /// Stable mapping: 1..9 map to ids 1..9, 0 maps to id 10.
    private func hotKeyIDValueForSlot(_ slot: ShortcutSlot) -> UInt32 {
        switch slot {
        case .zero: return 10
        default: return UInt32(slot.rawValue)
        }
    }

    private func keyCodeForSlot(_ slot: ShortcutSlot) -> UInt32 {
        switch slot {
        case .one: return UInt32(kVK_ANSI_1)
        case .two: return UInt32(kVK_ANSI_2)
        case .three: return UInt32(kVK_ANSI_3)
        case .four: return UInt32(kVK_ANSI_4)
        case .five: return UInt32(kVK_ANSI_5)
        case .six: return UInt32(kVK_ANSI_6)
        case .seven: return UInt32(kVK_ANSI_7)
        case .eight: return UInt32(kVK_ANSI_8)
        case .nine: return UInt32(kVK_ANSI_9)
        case .zero: return UInt32(kVK_ANSI_0)
        }
    }

    // MARK: Action pipeline

    private func captureActivatePaste(targetBundleID: String) {
        guard !isRunningAction else {
            NSLog("Pollyshot: action already running; ignoring trigger")
            return
        }
        isRunningAction = true
        defer { isRunningAction = false }

        NSLog("Pollyshot: hotkey/menu triggered — starting interactive screenshot")
        let screenshotOK = runInteractiveScreenshotToClipboard()
        if !screenshotOK {
            NSLog("Pollyshot: screenshot command failed or was cancelled")
            return
        }

        // Give the clipboard a brief moment to update before pasting.
        Thread.sleep(forTimeInterval: 0.25)

        activateApp(bundleID: targetBundleID)

        // Give the app time to become frontmost and accept Cmd+V.
        Thread.sleep(forTimeInterval: 0.8)

        paste()
    }

    /// Runs macOS built-in interactive selection screenshot and copies to clipboard.
    /// Returns true when the command finishes successfully (exit code 0).
    private func runInteractiveScreenshotToClipboard() -> Bool {
        let process = Process()
        process.launchPath = "/usr/sbin/screencapture"
        process.arguments = ["-i", "-c"]

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            NSLog("Pollyshot: failed to start screencapture: \(error)")
            return false
        }

        process.waitUntilExit()

        if process.terminationStatus != 0 {
            // If user cancels the interactive capture, macOS typically returns non-zero.
            let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            if let msg = String(data: data, encoding: .utf8),
               !msg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                NSLog("Pollyshot: screencapture error: \(msg)")
            }
            return false
        }

        return true
    }

    private func activateApp(bundleID: String) {
        // Open if needed
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: nil)
        } else {
            NSLog("Pollyshot: could not locate app for bundleID=\(bundleID)")
        }

        // Make frontmost if running
        DispatchQueue.main.async {
            if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                _ = running.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            }
        }
    }

    /// Synthesizes Cmd+V using CGEvent. Requires Accessibility permission.
    private func paste() {
        guard let src = CGEventSource(stateID: .hidSystemState) else {
            NSLog("Pollyshot: unable to create CGEventSource for paste")
            return
        }

        let vKeyCode: CGKeyCode = 9 // kVK_ANSI_V
        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: true)
        keyDown?.flags = .maskCommand

        let keyUp = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
