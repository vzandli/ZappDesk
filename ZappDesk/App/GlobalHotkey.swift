/*
 * GlobalHotkey.swift — ZappDesk
 *
 * Registers a global system-wide hotkey (Option + Command + Comma: ⌥⌘,)
 * to summon the ZappDesk Settings window even when both the Dock icon
 * and Menu Bar icon are hidden.
 */

import Carbon
import Cocoa

final class GlobalHotkeyManager {
    static let shared = GlobalHotkeyManager()

    static let statusDidChangeNotification = Notification.Name("ZappDeskHotkeyStatusDidChange")
    private(set) var registrationError: OSStatus?
    var isRegistered: Bool { eventHotKeyRef != nil && eventHandler != nil }
    var settingsHint: String {
        isRegistered ? "Press ⌥⌘, to open Settings." :
            "Settings hotkey unavailable. Reopen ZappDesk in Finder or run open zappdesk://settings."
    }

    private var eventHotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    func register() {
        guard !isRegistered else { return }
        unregister()
        defer { NotificationCenter.default.post(name: Self.statusDidChangeNotification, object: nil) }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )

        let handlerCallback: EventHandlerUPP = { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            if status == noErr && hotKeyID.signature == OSType(0x5A415050) && hotKeyID.id == 1 {
                DispatchQueue.main.async {
                    SettingsWindowController.shared.show()
                }
                return noErr
            }
            return OSStatus(eventNotHandledErr)
        }

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            handlerCallback,
            1,
            &eventType,
            nil,
            &eventHandler
        )

        guard handlerStatus == noErr else {
            registrationError = handlerStatus
            return
        }

        // Hotkey: Option (2048 / 0x0800) + Command (256 / 0x0100), keycode 43 (comma ',')
        let hotKeyID = EventHotKeyID(signature: OSType(0x5A415050), id: 1) // "ZAPP"
        let modifiers = UInt32(cmdKey | optionKey)
        let commaKeyCode: UInt32 = 43

        let keyStatus = RegisterEventHotKey(
            commaKeyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &eventHotKeyRef
        )
        registrationError = keyStatus == noErr ? nil : keyStatus
        if keyStatus != noErr {
            unregister()
            NSLog("[ZappDesk] Settings hotkey registration failed: %d", keyStatus)
        }
    }

    func unregister() {
        if let ref = eventHotKeyRef {
            UnregisterEventHotKey(ref)
            eventHotKeyRef = nil
        }
        if let h = eventHandler {
            RemoveEventHandler(h)
            eventHandler = nil
        }
    }
}
