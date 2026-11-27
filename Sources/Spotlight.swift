import Foundation
import CoreSpotlight
import UniformTypeIdentifiers

/// Karteczki w Spotlight: tytuł, klient, projekt, tagi, zadania i notatka. Indeks jest tylko na tym Macu.
/// Wybranie wyniku otwiera karteczkę (AppDelegate.application(_:continue:)).
/// Zarchiwizowane też (szukasz starych rzeczy), kosz nie.
enum Spotlight {
    static let domain = "pl.stosik.notes"
    /// Testy na osobnym folderze danych nie mogą trafić do Spotlight użytkownika.
    static var enabled: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["STOSIK_DIR"] == nil && env["STOSIK_SNAP"] == nil
    }
    /// Co już jest w indeksie (id → podpis treści), żeby nie wysyłać niezmienionych karteczek.
    private static var indexed: [String: String]?

    static func update(_ notes: [Note]) {
        guard enabled else { return }
        let index = CSSearchableIndex.default()
        var now: [String: String] = [:]
        var items: [CSSearchableItem] = []
        for n in notes where !n.locked {   // zablokowanych nie pokazujemy w Spotlight
            let id = n.id.uuidString, sig = signature(n)
            now[id] = sig
            if indexed?[id] != sig { items.append(item(n)) }
        }
        if indexed == nil {
            // pierwszy raz po starcie: czyścimy stary indeks (karteczki skasowane, gdy apka była zamknięta)
            index.deleteSearchableItems(withDomainIdentifiers: [domain]) { _ in
                index.indexSearchableItems(notes.filter { !$0.locked }.map(item)) { _ in }
            }
        } else {
            let gone = indexed!.keys.filter { now[$0] == nil }
            if !gone.isEmpty { index.deleteSearchableItems(withIdentifiers: gone) { _ in } }
            if !items.isEmpty { index.indexSearchableItems(items) { _ in } }
        }
        indexed = now
    }

    /// Sprawdzenie (STOSIK_SPOTLIGHT_CHECK=1): ile karteczek jest w indeksie, z tytułami.
    static func check(done: @escaping () -> Void) {
        let q = CSSearchQuery(queryString: "domainIdentifier == '\(domain)'", queryContext: {
            let c = CSSearchQueryContext(); c.fetchAttributes = ["title", "contentDescription"]; return c }())
        var found: [String] = []
        q.foundItemsHandler = { items in found += items.map { ($0.attributeSet.title ?? "?") + " | " + ($0.attributeSet.contentDescription ?? "") } }
        q.completionHandler = { err in
            print("Spotlight: \(found.count) karteczek\(err.map { ", błąd: \($0)" } ?? "")")
            found.forEach { print("  " + $0) }
            done()
        }
        q.start()
    }

    private static func title(_ n: Note) -> String { n.title.isEmpty ? L("Bez tytułu") : n.title }

    private static func signature(_ n: Note) -> String {
        [title(n), n.client, n.project, n.tags.joined(separator: ","), n.body, n.archived ? "a" : "",
         n.tasks.map { ($0.done ? "+" : "-") + $0.text }.joined(separator: "\n")].joined(separator: "|")
    }

    private static func item(_ n: Note) -> CSSearchableItem {
        let a = CSSearchableItemAttributeSet(contentType: .text)
        a.title = title(n)
        let open = n.tasks.filter { !$0.done && !$0.text.isEmpty }.map(\.text)
        let meta = [n.client, n.project].filter { !$0.isEmpty }.joined(separator: " · ")
        // podpis pod tytułem: klient · projekt, potem pierwsze otwarte zadania
        let desc = [meta, open.prefix(3).joined(separator: ", ")].filter { !$0.isEmpty }.joined(separator: " — ")
        a.contentDescription = n.archived ? L("Archiwum") + (desc.isEmpty ? "" : " — " + desc) : desc
        a.textContent = ([n.body] + n.tasks.map(\.text)).filter { !$0.isEmpty }.joined(separator: "\n")
        a.keywords = ([n.client, n.project] + n.tags).filter { !$0.isEmpty }
        if let d = n.deadline { a.dueDate = d }
        a.contentCreationDate = n.created
        return CSSearchableItem(uniqueIdentifier: n.id.uuidString, domainIdentifier: domain, attributeSet: a)
    }
}
