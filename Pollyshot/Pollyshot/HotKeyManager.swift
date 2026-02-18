import Foundation
import Carbon.HIToolbox
import AppKit

/// Represents a hotkey configuration.
struct HotKeyConfig {
    let keyCode: UInt32
    let modifiers: UInt32
    let bundleID: String?
    let id: UInt32
}

/// Registers a global hotkey and, when triggered:
/// 1) runs `screencapture -i -c` (interactive area screenshot to clipboard)
/// 2) activates Apple Notes or other target app
/// 3) pastes (Cmd+V)
///
/// Permissions:
/// - Screen Recording: may be required for `screencapture` on newer macOS versions.
/// - Accessibility: required to synthesize Cmd+V into target app (System Settings → Privacy & Security → Accessibility).
final class HotKeyManager {
    static let shared = HotKeyManager()

    private static let signature: OSType = OSType(0x504F4C59) // 'POLY'

    private var hotKeyRefMap: [UInt32: EventHotKeyRef] = [:]
    private var handlerRef: EventHandlerRef?

    /// Prevent re-entrancy if the user hits the hotkey repeatedly.
    private let actionQueue = DispatchQueue(label: "com.pollyshot.hotkey.action", qos: .userInitiated)
    private var isRunningAction = false

    /// Definitions of all hotkey configurations.
    /// Each config has a unique ID, keyCode, modifiers, and target bundleID (nil means legacy Notes).
    private let hotKeyConfigs: [HotKeyConfig] = [
        // Cmd+Option+Shift+1 → Slack
        HotKeyConfig(keyCode: UInt32(kVK_ANSI_1), modifiers: UInt32(cmdKey | optionKey | shiftKey), bundleID: "com.tinyspeck.slackmacgap", id: 1),
        // Cmd+Option+Shift+2 → ChatGPT (modified bundleID)
        HotKeyConfig(keyCode: UInt32(kVK_ANSI_2), modifiers: UInt32(cmdKey | optionKey | shiftKey), bundleID: "com.openai.chat", id: 2),
        // Cmd+Option+Shift+3 → TextEdit
        HotKeyConfig(keyCode: UInt32(kVK_ANSI_3), modifiers: UInt32(cmdKey | optionKey | shiftKey), bundleID: "com.apple.TextEdit", id: 3),
        // Cmd+Option+Shift+4 → Notes
        HotKeyConfig(keyCode: UInt32(kVK_ANSI_4), modifiers: UInt32(cmdKey | optionKey | shiftKey), bundleID: "com.apple.Notes", id: 4),
        
        // Legacy configs removed/commented out:
        // HotKeyConfig(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(cmdKey | optionKey), bundleID: nil, id: 1),
        // HotKeyConfig(keyCode: UInt32(kVK_ANSI_1), modifiers: UInt32(cmdKey | optionKey), bundleID: "com.apple.Notes", id: 2),
        // HotKeyConfig(keyCode: UInt32(kVK_ANSI_2), modifiers: UInt32(cmdKey | optionKey), bundleID: "com.apple.TextEdit", id: 3),
        // HotKeyConfig(keyCode: UInt32(kVK_ANSI_3), modifiers: UInt32(cmdKey | optionKey), bundleID: "com.tinyspeck.slackmacgap", id: 4),
        // HotKeyConfig(keyCode: UInt32(kVK_ANSI_4), modifiers: UInt32(cmdKey | optionKey), bundleID: "com.openai.ChatGPT", id: 5)
    ]

    private init() {}

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

        // Register all hotkeys from hotKeyConfigs
        for config in hotKeyConfigs {
            let id = EventHotKeyID(signature: HotKeyManager.signature, id: config.id)
            var ref: EventHotKeyRef?

            let status = RegisterEventHotKey(
                config.keyCode,
                config.modifiers,
                id,
                GetApplicationEventTarget(),
                0,
                &ref
            )
            if status == noErr, let ref = ref {
                hotKeyRefMap[config.id] = ref
            } else {
                NSLog("Pollyshot: Failed to register hotkey id \(config.id) keyCode \(config.keyCode) modifiers \(config.modifiers)")
            }
        }
    }

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

        if status == noErr, hk.signature == HotKeyManager.signature {
            DispatchQueue.main.async {
                HotKeyManager.shared.handleHotKeyID(hk.id)
            }
        }

        return noErr
    }

    private func handleHotKeyID(_ id: UInt32) {
        guard let config = hotKeyConfigs.first(where: { $0.id == id }) else {
            NSLog("Pollyshot: unknown hotkey id \(id) triggered")
            return
        }

        if let bundleID = config.bundleID {
            handleHotKeyPressed(targetBundleID: bundleID)
        } else {
            handleHotKeyPressed()
        }
    }

    public func handleHotKeyPressed() {
        actionQueue.async { [weak self] in
            guard let self else { return }
            guard !self.isRunningAction else {
                NSLog("Pollyshot: action already running; ignoring hotkey press")
                return
            }
            self.isRunningAction = true
            defer { self.isRunningAction = false }

            NSLog("Pollyshot: hotkey triggered — starting interactive screenshot")
            let screenshotOK = self.runInteractiveScreenshotToClipboard()
            if !screenshotOK {
                NSLog("Pollyshot: screenshot command failed or was cancelled")
                return
            }

            // Give the clipboard a brief moment to update before pasting.
            Thread.sleep(forTimeInterval: 0.25)

            self.activateNotes()

            // Wait longer for Notes to become frontmost and ready for Cmd+V. Increase if paste sometimes fails.
            Thread.sleep(forTimeInterval: 1.0)

            self.paste()
        }
    }

    public func handleHotKeyPressed(targetBundleID: String) {
        actionQueue.async { [weak self] in
            guard let self else { return }
            guard !self.isRunningAction else {
                NSLog("Pollyshot: action already running; ignoring hotkey press")
                return
            }
            self.isRunningAction = true
            defer { self.isRunningAction = false }

            NSLog("Pollyshot: hotkey triggered — starting interactive screenshot")
            let screenshotOK = self.runInteractiveScreenshotToClipboard()
            if !screenshotOK {
                NSLog("Pollyshot: screenshot command failed or was cancelled")
                return
            }

            // Give the clipboard a brief moment to update before pasting.
            Thread.sleep(forTimeInterval: 0.25)

            self.activateApp(bundleID: targetBundleID)

            // Wait longer for target app to become frontmost and ready for Cmd+V. Increase if paste sometimes fails.
            Thread.sleep(forTimeInterval: 1.0)

            self.paste()
        }
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
            if let msg = String(data: data, encoding: .utf8), !msg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                NSLog("Pollyshot: screencapture error: \(msg)")
            }
            return false
        }

        return true
    }

    private func activateNotes() {
        // First try: open/activate Notes directly.
        // (This avoids relying on scripting permissions just to bring the app forward.)
        let notesURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Notes")
        if let url = notesURL {
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: nil)
        }

        // Ensure it becomes frontmost.
        DispatchQueue.main.async {
            if let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Notes").first {
                _ = running.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            }
        }

        // Also set activation policy in case the menu bar app is background-y.
        DispatchQueue.main.async {
            // Note: activateIgnoringOtherApps is deprecated on macOS 14,
            // but still used here for compatibility.
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func activateApp(bundleID: String) {
        // First try: open/activate app directly.
        // (This avoids relying on scripting permissions just to bring the app forward.)
        let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        if let url = appURL {
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: nil)
        }

        // Ensure it becomes frontmost.
        DispatchQueue.main.async {
            if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                _ = running.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            }
        }

        // Also set activation policy in case the menu bar app is background-y.
        DispatchQueue.main.async {
            // Note: activateIgnoringOtherApps is deprecated on macOS 14,
            // but still used here for compatibility.
            NSApp.activate(ignoringOtherApps: true)
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

        NSLog("Pollyshot: pasted into frontmost app (expected: target app)")
    }
}

