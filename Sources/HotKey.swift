import AppKit
import Carbon

final class HotKey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private static var nextID: UInt32 = 0
    private let id: UInt32
    private(set) var registeredShortcut: CaptureShortcut?
    let action: () -> Void
    init(action: @escaping () -> Void) {
        self.action = action
        Self.nextID += 1; id = Self.nextID
    }
    func register(_ shortcut: CaptureShortcut = .defaultValue) -> Bool {
        guard shortcut.isValid else { return false }
        if reference != nil, registeredShortcut == shortcut { return true }
        if handler == nil, !installHandler() { return false }
        var replacement: EventHotKeyRef?
        let result = RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers,
                                        EventHotKeyID(signature: 0x4D4D4152, id: id),
                                        GetApplicationEventTarget(), 0, &replacement)
        guard result == noErr else { return false }
        unregister()
        reference = replacement
        registeredShortcut = shortcut
        return true
    }
    private func installHandler() -> Bool {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        return InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData, let event else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            var eventID = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                    nil, MemoryLayout<EventHotKeyID>.size, nil, &eventID) == noErr,
                  eventID.signature == 0x4D4D4152, eventID.id == hotKey.id else { return OSStatus(eventNotHandledErr) }
            hotKey.action()
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler) == noErr
    }
    func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
        registeredShortcut = nil
    }
    deinit {
        unregister()
        if let handler { RemoveEventHandler(handler) }
    }
}
