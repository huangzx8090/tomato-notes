import Carbon
import Foundation
import TomatoCore

@MainActor
public final class HotkeyManager {
    public var onPress: ((Int) -> Void)?
    private struct Combination: Hashable {
        let code: UInt32
        let modifiers: UInt32
    }
    private struct Registration {
        let ref: EventHotKeyRef
        let token: UInt32
    }
    private var registrations: [Combination: Registration] = [:]
    private var actions: [UInt32: Int] = [:]
    private var nextToken: UInt32 = 0
    private var eventHandler: EventHandlerRef?
    private var handlerStatus: OSStatus = noErr

    public init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr else { return status }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                if let action = manager.actions[id.id] { manager.onPress?(action) }
            }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }

    deinit {
        for item in registrations.values { UnregisterEventHotKey(item.ref) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    public func apply(_ settings: AppSettings) -> String? {
        guard handlerStatus == noErr else { return "快捷键事件监听失败（错误 \(handlerStatus)），请重启后重试" }
        let items = [(1, "计时", settings.timerHotkey), (2, "快速待办", settings.todoHotkey), (3, "便签", settings.noteHotkey)]
        var wanted: [(Int, String, Combination)] = []
        var seen = Set<Combination>()
        for (action, name, key) in items where key.enabled {
            guard key.letter.count == 1, let code = Self.keyCodes[key.letter.uppercased()] else {
                return "\(name)快捷键需要一个 A–Z 字母"
            }
            let modifiers: UInt32
            switch key.modifier {
            case "commandShift": modifiers = UInt32(cmdKey | shiftKey)
            case "controlCommand": modifiers = UInt32(controlKey | cmdKey)
            case "controlOption": modifiers = UInt32(controlKey | optionKey)
            default: return "\(name)快捷键的修饰键无效，请重新选择"
            }
            let combination = Combination(code: code, modifiers: modifiers)
            guard seen.insert(combination).inserted else { return "快捷键重复，请为\(name)换一个组合" }
            wanted.append((action, name, combination))
        }

        // 先注册新增组合，保留原有注册；任何一步失败都只撤销新增项，旧快捷键始终可用。
        var additions: [Combination: Registration] = [:]
        for (_, name, combination) in wanted where registrations[combination] == nil {
            nextToken &+= 1
            let hotkeyID = EventHotKeyID(signature: 0x544D544E, id: nextToken)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(combination.code, combination.modifiers, hotkeyID,
                                             GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &ref)
            guard status == noErr, let ref else {
                for item in additions.values { UnregisterEventHotKey(item.ref) }
                return "\(name)快捷键被系统或其他应用占用（错误 \(status)）。原快捷键已保留，请换一个组合"
            }
            additions[combination] = Registration(ref: ref, token: nextToken)
        }
        for (combination, item) in registrations where !seen.contains(combination) { UnregisterEventHotKey(item.ref) }
        registrations = registrations.filter { seen.contains($0.key) }.merging(additions) { _, new in new }
        actions = Dictionary(uniqueKeysWithValues: wanted.map { action, _, combination in
            (registrations[combination]!.token, action)
        })
        return nil
    }

    private static let keyCodes: [String: UInt32] = [
        "A": 0, "B": 11, "C": 8, "D": 2, "E": 14, "F": 3, "G": 5,
        "H": 4, "I": 34, "J": 38, "K": 40, "L": 37, "M": 46, "N": 45,
        "O": 31, "P": 35, "Q": 12, "R": 15, "S": 1, "T": 17, "U": 32,
        "V": 9, "W": 13, "X": 7, "Y": 16, "Z": 6
    ]
}
