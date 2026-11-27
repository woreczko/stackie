import AppKit
import UniformTypeIdentifiers

/// Coś upuszczone na stos: plik (dołączony), link (w notatce, tytuł z adresu) albo tekst (tytuł z pierwszej linijki).
enum DropToNote {
    static func make(_ items: [NSItemProvider], open: @escaping (UUID) -> Void) {
        let group = DispatchGroup()
        var files: [URL] = [], links: [URL] = [], texts: [String] = []
        let lock = NSLock()
        for it in items {
            group.enter()
            if it.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = it.loadObject(ofClass: URL.self) { u, _ in
                    if let u { lock.lock(); files.append(u); lock.unlock() }
                    group.leave()
                }
            } else if it.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                _ = it.loadObject(ofClass: URL.self) { u, _ in
                    if let u { lock.lock(); links.append(u); lock.unlock() }
                    group.leave()
                }
            } else {
                _ = it.loadObject(ofClass: String.self) { t, _ in
                    if let t { lock.lock(); texts.append(t); lock.unlock() }
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) {
            let text = texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !files.isEmpty || !links.isEmpty || !text.isEmpty else { return }
            let store = Store.shared
            let id = store.add()
            guard let i = store.notes.firstIndex(where: { $0.id == id }) else { return }
            var n = store.notes[i]
            n.tasks = []
            if !text.isEmpty {
                n.title = QuickNoteView.title(from: text)
                n.body = text
            } else if let l = links.first {
                n.title = l.host?.replacingOccurrences(of: "www.", with: "") ?? l.absoluteString
            } else if let f = files.first {
                n.title = f.deletingPathExtension().lastPathComponent
            }
            let linkText = links.map(\.absoluteString).joined(separator: "\n")
            if !linkText.isEmpty { n.body = n.body.isEmpty ? linkText : n.body + "\n" + linkText }
            store.notes[i] = n
            if !files.isEmpty { store.attach(id, files) }
            NSSound(named: "Pop")?.play()
            open(id)
        }
    }
}
