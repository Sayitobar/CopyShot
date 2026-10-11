import Carbon

enum HotkeyRegistrationError: LocalizedError {
    case modifierRequired
    case unavailable(OSStatus)
    var errorDescription: String? {
        switch self {
        case .modifierRequired: "Use Command, Control, or Option with a key. Escape cancels recording."
        case .unavailable: "This shortcut could not be registered. It may be in use by another app. Choose another combination; your working shortcut has been kept."
        }
    }
}

/// Registration is transactional: a failed candidate never releases the working hotkey.
final class HotkeyRegistration {
    private let register: (HotkeyConfig) throws -> EventHotKeyRef
    private let unregister: (EventHotKeyRef) -> Void
    private var handle: EventHotKeyRef?
    private(set) var activeConfig: HotkeyConfig?

    init(register: @escaping (HotkeyConfig) throws -> EventHotKeyRef,
         unregister: @escaping (EventHotKeyRef) -> Void) {
        self.register = register
        self.unregister = unregister
    }

    func replace(with config: HotkeyConfig) throws {
        guard config.modifierFlags & UInt32(cmdKey | controlKey | optionKey) != 0 else {
            throw HotkeyRegistrationError.modifierRequired
        }
        if let activeConfig, activeConfig.keyCode == config.keyCode,
           activeConfig.modifierFlags == config.modifierFlags { return }
        let replacement = try register(config)
        if let handle { unregister(handle) }
        handle = replacement
        activeConfig = config
    }

    deinit { if let handle { unregister(handle) } }
}
