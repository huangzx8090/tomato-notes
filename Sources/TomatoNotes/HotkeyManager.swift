import Carbon
import Foundation
import TomatoCore

@MainActor
final class HotkeyManager {
    var onPress: ((Int) -> Void)?
    private var refs: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private var activeSettings: AppSettings?

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr else { return status }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { manager.onPress?(Int(id.id)) }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }

    deinit {
        for ref in refs { UnregisterEventHotKey(ref) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    func apply(_ settings: AppSettings) -> String? {
        let previous = activeSettings
        unregisterAll()
        if let message = register(settings) {
            unregisterAll()
            if let previous { _ = register(previous) }
            return message
        }
        activeSettings = settings
        return nil
    }

    private func unregisterAll() {
        for ref in refs { UnregisterEventHotKey(ref) }
        refs.removeAll()
    }

    private func register(_ settings: AppSettings) -> String? {
        let items: [(Int, String, Hotkey)] = [
            (1, "计时", settings.timerHotkey),
            (2, "快速待办", settings.todoHotkey),
            (3, "便签", settings.noteHotkey)
        ]
        var seen = Set<String>()
        for (id, name, key) in items where key.enabled {
            let letter = key.letter.uppercased()
            guard letter.count == 1, let code = Self.keyCodes[letter] else {
                return "\(name)快捷键需要一个 A–Z 字母"
            }
            let identity = "\(key.modifier):\(letter)"
            guard seen.insert(identity).inserted else { return "快捷键重复，请为\(name)换一个组合" }
            let modifiers: UInt32
            switch key.modifier {
            case "commandShift": modifiers = UInt32(cmdKey | shiftKey)
            case "controlCommand": modifiers = UInt32(controlKey | cmdKey)
            default: modifiers = UInt32(controlKey | optionKey)
            }
            let hotkeyID = EventHotKeyID(signature: 0x544D544E, id: UInt32(id))
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(code, modifiers, hotkeyID,
                                             GetApplicationEventTarget(), 0, &ref)
            guard status == noErr, let ref else {
                return "\(name)快捷键被系统或其他应用占用（错误 \(status)），请换一个组合"
            }
            refs.append(ref)
        }
        return nil
    }

    private static let keyCodes: [String: UInt32] = [
        "A": 0, "B": 11, "C": 8, "D": 2, "E": 14, "F": 3, "G": 5,
        "H": 4, "I": 34, "J": 38, "K": 40, "L": 37, "M": 46, "N": 45,
        "O": 31, "P": 35, "Q": 12, "R": 15, "S": 1, "T": 17, "U": 32,
        "V": 9, "W": 13, "X": 7, "Y": 16, "Z": 6
    ]
}
