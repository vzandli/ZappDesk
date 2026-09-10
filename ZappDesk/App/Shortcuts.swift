/*
 * Shortcuts.swift — ZappDesk
 *
 * Reads user-configured system space switching shortcuts from
 * com.apple.symbolichotkeys.
 */

import CoreGraphics
import CoreFoundation
import Foundation

typealias KeyBinding = (keycode: Int64, mods: CGEventFlags)

private let kHotkeyMoveLeftSpace  = "79"
private let kHotkeyMoveRightSpace = "81"

// Carbon modifiers
private enum CarbonModifier {
    static let shift:   Int64 = 0x020000
    static let control: Int64 = 0x040000
    static let option:  Int64 = 0x080000
    static let command: Int64 = 0x100000
}

private func carbonToCGFlags(_ carbon: Int64) -> CGEventFlags {
    var flags = CGEventFlags()
    if carbon & CarbonModifier.control != 0 { flags.insert(.maskControl)   }
    if carbon & CarbonModifier.shift   != 0 { flags.insert(.maskShift)     }
    if carbon & CarbonModifier.option  != 0 { flags.insert(.maskAlternate) }
    if carbon & CarbonModifier.command != 0 { flags.insert(.maskCommand)   }
    return flags
}

private let kDefaultBindingLeft:  KeyBinding = (keycode: 123, mods: .maskControl)
private let kDefaultBindingRight: KeyBinding = (keycode: 124, mods: .maskControl)

private enum HotkeyState {
    case systemDefault
    case disabled
    case bound(KeyBinding)
}

private func readHotkey(from hotkeys: NSDictionary, key: String) -> HotkeyState {
    guard let entry = hotkeys[key] as? NSDictionary else { return .systemDefault }

    if let enabled = entry["enabled"] {
        if let flag   = enabled as? Bool, !flag { return .disabled }
        if let number = (enabled as? NSNumber)?.intValue, number == 0 { return .disabled }
    }

    guard let value   = entry["value"]      as? NSDictionary,
          let params  = value["parameters"] as? NSArray,
          params.count >= 3,
          let keycode = (params[1] as? NSNumber)?.int64Value,
          let carbon  = (params[2] as? NSNumber)?.int64Value
    else { return .systemDefault }

    if keycode == 65535 { return .disabled }
    return .bound((keycode: keycode, mods: carbonToCGFlags(carbon)))
}

var gBindingLeft:  KeyBinding? = kDefaultBindingLeft
var gBindingRight: KeyBinding? = kDefaultBindingRight
var gSpaceKeys:   [KeyBinding?] = []

func reloadSystemShortcuts() {
    CFPreferencesAppSynchronize("com.apple.symbolichotkeys" as CFString)
    let dict = CFPreferencesCopyAppValue(
        "AppleSymbolicHotKeys" as CFString,
        "com.apple.symbolichotkeys" as CFString
    ) as? NSDictionary ?? [:]
    applySystemShortcuts(dict)
}

func applySystemShortcuts(_ dict: NSDictionary) {
    switch readHotkey(from: dict, key: kHotkeyMoveLeftSpace) {
    case .bound(let b):     gBindingLeft = b
    case .disabled:         gBindingLeft = nil
    case .systemDefault:    gBindingLeft = kDefaultBindingLeft
    }

    switch readHotkey(from: dict, key: kHotkeyMoveRightSpace) {
    case .bound(let b):     gBindingRight = b
    case .disabled:         gBindingRight = nil
    case .systemDefault:    gBindingRight = kDefaultBindingRight
    }

    // Direct desktop shortcuts: 118..133 correspond to Desktops 1..16
    var directBindings = [KeyBinding?]()
    for id in 118...133 {
        switch readHotkey(from: dict, key: String(id)) {
        case .bound(let b):  directBindings.append(b)
        case .disabled:      directBindings.append(nil)
        case .systemDefault: directBindings.append(nil)
        }
    }
    gSpaceKeys = directBindings
}
