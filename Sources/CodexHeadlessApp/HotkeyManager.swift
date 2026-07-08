import Carbon
import CodexHeadlessCore
import Foundation

enum HotkeyAction: UInt32, CaseIterable {
    case enable = 1
    case confirm = 2
    case restore = 3

    var label: String {
        switch self {
        case .enable: return "enable"
        case .confirm: return "confirm"
        case .restore: return "restore"
        }
    }
}

struct HotkeyRegistrationStatus {
    var shortcut: HotkeyShortcutConfig
    var status: OSStatus?

    var text: String {
        guard let status else {
            return "Disabled"
        }
        return status == noErr ? "Registered" : "Failed (\(status))"
    }
}

final class HotkeyManager {
    private let logger: CHLogger
    private var hotKeyRefs: [HotkeyAction: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?
    private(set) var statuses: [HotkeyAction: HotkeyRegistrationStatus] = [:]
    var onAction: ((HotkeyAction) -> Void)?

    init(logger: CHLogger) {
        self.logger = logger
    }

    deinit {
        unregisterAll()
    }

    func configure(_ config: HotkeysConfig) {
        unregisterAll()
        statuses = [
            .enable: HotkeyRegistrationStatus(shortcut: config.enable, status: nil),
            .confirm: HotkeyRegistrationStatus(shortcut: config.confirm, status: nil),
            .restore: HotkeyRegistrationStatus(shortcut: config.restore, status: nil)
        ]

        guard config.enabled else {
            logger.info("[Hotkey] Global hotkeys disabled by config.")
            return
        }

        installEventHandlerIfNeeded()
        register(action: .enable, shortcut: config.enable)
        register(action: .confirm, shortcut: config.confirm)
        register(action: .restore, shortcut: config.restore)
    }

    func unregisterAll() {
        for (_, ref) in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else {
                    return OSStatus(eventNotHandledErr)
                }

                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                let result = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard result == noErr,
                      let action = HotkeyAction(rawValue: hotKeyID.id) else {
                    return OSStatus(eventNotHandledErr)
                }

                DispatchQueue.main.async {
                    manager.logger.info("[Hotkey] Trigger \(action.label)")
                    manager.onAction?(action)
                }
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &eventHandler
        )

        if status == noErr {
            logger.info("[Hotkey] Event handler installed.")
        } else {
            logger.error("[Hotkey] Event handler install failed: \(status)")
        }
    }

    private func register(action: HotkeyAction, shortcut: HotkeyShortcutConfig) {
        guard let keyCode = keyCode(for: shortcut.key) else {
            logger.error("[Hotkey] Register \(action.label) failed: unsupported key \(shortcut.key)")
            statuses[action] = HotkeyRegistrationStatus(shortcut: shortcut, status: OSStatus(paramErr))
            return
        }

        let modifiers = carbonModifiers(for: shortcut.modifiers)
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: action.rawValue)
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        statuses[action] = HotkeyRegistrationStatus(shortcut: shortcut, status: status)
        if status == noErr, let hotKeyRef {
            hotKeyRefs[action] = hotKeyRef
            logger.info("[Hotkey] Register \(action.label): \(shortcut.displayString) OK")
        } else {
            logger.error("[Hotkey] Register \(action.label): \(shortcut.displayString) failed: \(status)")
        }
    }

    private static let signature: OSType = {
        let scalars = Array("CDXH".unicodeScalars)
        return scalars.reduce(UInt32(0)) { result, scalar in
            (result << 8) + scalar.value
        }
    }()

    private func keyCode(for key: String) -> Int? {
        switch key.uppercased() {
        case "E": return kVK_ANSI_E
        case "C": return kVK_ANSI_C
        case "R": return kVK_ANSI_R
        default: return nil
        }
    }

    private func carbonModifiers(for modifiers: [String]) -> UInt32 {
        modifiers.reduce(UInt32(0)) { result, modifier in
            switch modifier.lowercased() {
            case "control": return result | UInt32(controlKey)
            case "option": return result | UInt32(optionKey)
            case "command": return result | UInt32(cmdKey)
            case "shift": return result | UInt32(shiftKey)
            default: return result
            }
        }
    }
}
