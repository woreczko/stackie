import AppKit
import Carbon

/// Skrót klawiszowy w całym systemie: szybka notatka z włączonym dyktowaniem.
/// Carbon RegisterEventHotKey nie wymaga zgody na dostępność (w przeciwieństwie do podsłuchu klawiatury).
enum Hotkey {
    /// (nazwa, kod klawisza, modyfikatory); 0 = wyłączony
    static let options: [(name: String, key: UInt32, mods: UInt32)] = [
        ("", 0, 0),
        ("⌃⌥Space", UInt32(kVK_Space), UInt32(controlKey | optionKey)),
        ("⌥⌘N", UInt32(kVK_ANSI_N), UInt32(optionKey | cmdKey)),
    ]
    static var choice: Int {
        get { UserDefaults.standard.object(forKey: "hotkey") == nil ? 1 : UserDefaults.standard.integer(forKey: "hotkey") }
        set { UserDefaults.standard.set(newValue, forKey: "hotkey"); register() }
    }
    private static var ref: EventHotKeyRef?
    private static var handler: EventHandlerRef?
    private static var action: (() -> Void)?

    static func install(_ a: @escaping () -> Void) {
        action = a
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetEventDispatcherTarget(), { _, _, _ in
                DispatchQueue.main.async { Hotkey.action?() }
                return noErr
            }, 1, &spec, nil, &handler)
        }
        register()
    }

    private static func register() {
        if let r = ref { UnregisterEventHotKey(r); ref = nil }
        let i = choice
        guard i > 0, i < options.count else { return }
        let o = options[i]
        let id = EventHotKeyID(signature: OSType(0x53544B59), id: 1)   // „STKY”
        RegisterEventHotKey(o.key, o.mods, id, GetEventDispatcherTarget(), 0, &ref)
    }
}
