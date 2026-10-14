import Carbon

/// Registers system-wide hotkeys with the Carbon hotkey API.
/// This API does not need the Accessibility permission.
final class HotKeyManager {
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var handlers: [UInt32: () -> Void] = [:]
    private var eventHandler: EventHandlerRef?

    /// Returns false when macOS rejects the hotkey (for example, another app owns it).
    @discardableResult
    func register(keyCode: Int, modifiers: Int, handler: @escaping () -> Void) -> Bool {
        installHandlerIfNeeded()
        let id = UInt32(handlers.count + 1)
        let hotKeyID = EventHotKeyID(signature: OSType(0x534E_4150), id: id) // 'SNAP'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        hotKeyRefs.append(ref)
        handlers[id] = handler
        return true
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let err = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                        EventParamType(typeEventHotKeyID), nil,
                                        MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard err == noErr else { return err }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            let handler = manager.handlers[hotKeyID.id]
            DispatchQueue.main.async { handler?() }
            return noErr
        }, 1, &spec, userData, &eventHandler)
    }
}
