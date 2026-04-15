import AppKit
import Carbon.HIToolbox
import Combine

/// Registers a single global hotkey (default ⌥⌘P) and forwards activations.
///
/// Uses the Carbon RegisterEventHotKey API directly — no third-party dependency
/// needed for a fixed shortcut. Users can edit the key combo below and rebuild.
final class HotkeyController: ObservableObject {
    static let popupActivated = Notification.Name("SmartPrompting.popupActivated")

    private var hotKeyRef: EventHotKeyRef?
    private var handler: EventHandlerRef?

    // ⌥⌘P
    private let keyCode: UInt32 = UInt32(kVK_ANSI_P)
    private let modifiers: UInt32 = UInt32(optionKey | cmdKey)

    init() {
        register()
    }

    deinit {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        if let h = handler { RemoveEventHandler(h) }
    }

    private func register() {
        let signature: OSType = 0x53505054 // 'SPPT'
        let id = EventHotKeyID(signature: signature, id: 1)

        let callback: EventHandlerUPP = { _, event, _ in
            guard let event = event else { return noErr }
            var hkID = EventHotKeyID()
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hkID
            )
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: HotkeyController.popupActivated, object: nil)
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "popup" }) {
                    window.makeKeyAndOrderFront(nil)
                }
            }
            return noErr
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType, nil, &handler)
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }
}
