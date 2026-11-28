import SwiftUI
import AppKit
import UserNotifications

// MARK: - Dane

struct TaskItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var text = ""
    var done = false { didSet { if done { doing = false } } }
    var doneAt: Date? = nil
    /// „W trakcie” (pół kółka): trzeci stan między niezrobionym a zrobionym.
    var doing = false
}

extension TaskItem {
    enum K: String, CodingKey { case id, text, done, doneAt, doing }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
        doneAt = try c.decodeIfPresent(Date.self, forKey: .doneAt)
        doing = try c.decodeIfPresent(Bool.self, forKey: .doing) ?? false
    }
    func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: K.self)
        try c.encode(id, forKey: .id); try c.encode(text, forKey: .text); try c.encode(done, forKey: .done)
        try c.encodeIfPresent(doneAt, forKey: .doneAt)
        if doing { try c.encode(true, forKey: .doing) }   // stary zapis bez pola zostaje taki sam
    }
}

/// Plik dołączony do karteczki. Kopia leży w zalaczniki/<id karteczki>/<id pliku>/<nazwa>.
struct Attachment: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = ""
    var size: Int64 = 0
}

struct Note: Codable, Identifiable, Equatable {
    var id = UUID()
    var title = ""
    var body = ""
    var color = 0
    var priority = 0          // 0 brak, 1 niska, 2 średnia, 3 pilne
    var deadline: Date? = nil
    var hasTime = false
    var tasks: [TaskItem] = []
    var created = Date()
    var archived = false
    var archivedAt: Date? = nil
    var tags: [String] = []
    var client = ""
    var project = ""
    /// Przypomnienia: ile minut przed terminem (0 = w chwili terminu). Termin bez godziny liczy się od 9:00.
    var alerts: [Int] = []
    /// Kiedy wyrzucona do kosza (kosz trzyma 30 dni).
    var deletedAt: Date? = nil
    /// Drzemka podskakiwania (jak w budziku) i wyciszenie dla danego terminu.
    var hopSnoozeUntil: Date? = nil
    var hopMutedFor: Date? = nil
    var files: [Attachment] = []
    /// Pod Touch ID: w stosie zasłonięta, otwiera się po odblokowaniu.
    var locked = false

    var remind: Bool { !alerts.isEmpty && deadline != nil }
    /// Tytuł poza samą karteczką (kalendarz, menu, Na dziś): zablokowana się nie zdradza.
    var shownTitle: String { locked ? L("Zablokowana") : (title.isEmpty ? L("Bez tytułu") : title) }
    var hopMuted: Bool { hopMutedFor != nil && hopMutedFor == deadline }
    var hopSnoozed: Bool { (hopSnoozeUntil ?? .distantPast) > Date() }
    /// Czy karteczka ma teraz podskakiwać (przypomnienie, bez drzemki i wyciszenia).
    var hops: Bool { remind && !hopMuted && !hopSnoozed }
    /// Chwila, od której liczą się przypomnienia (termin bez godziny: 9:00 tego dnia).
    var alertBase: Date? {
        guard let d = deadline else { return nil }
        return hasTime ? d : Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: d)
    }

    var doneCount: Int { tasks.filter(\.done).count }
    var allDone: Bool { !tasks.isEmpty && doneCount == tasks.count }
}

extension Note {
    enum K: String, CodingKey { case id, title, body, color, priority, deadline, hasTime, tasks, created, archived, archivedAt, tags, client, project, remind, alerts, deletedAt, hopSnoozeUntil, hopMutedFor, files, locked }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        color = try c.decodeIfPresent(Int.self, forKey: .color) ?? 0
        priority = try c.decodeIfPresent(Int.self, forKey: .priority) ?? 0
        deadline = try c.decodeIfPresent(Date.self, forKey: .deadline)
        hasTime = try c.decodeIfPresent(Bool.self, forKey: .hasTime) ?? false
        tasks = try c.decodeIfPresent([TaskItem].self, forKey: .tasks) ?? []
        created = try c.decodeIfPresent(Date.self, forKey: .created) ?? Date()
        archived = try c.decodeIfPresent(Bool.self, forKey: .archived) ?? false
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        archivedAt = try c.decodeIfPresent(Date.self, forKey: .archivedAt)
        client = try c.decodeIfPresent(String.self, forKey: .client) ?? ""
        project = try c.decodeIfPresent(String.self, forKey: .project) ?? ""
        deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
        hopSnoozeUntil = try c.decodeIfPresent(Date.self, forKey: .hopSnoozeUntil)
        hopMutedFor = try c.decodeIfPresent(Date.self, forKey: .hopMutedFor)
        files = try c.decodeIfPresent([Attachment].self, forKey: .files) ?? []
        locked = try c.decodeIfPresent(Bool.self, forKey: .locked) ?? false
        alerts = try c.decodeIfPresent([Int].self, forKey: .alerts)
            ?? ((try c.decodeIfPresent(Bool.self, forKey: .remind)) == true ? [1440, 0] : [])
    }

    func matches(tag: String?, client c: String? = nil, project p: String? = nil, query: String) -> Bool {
        if let tag, !tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) { return false }
        if let c, client.caseInsensitiveCompare(c) != .orderedSame { return false }
        if let p, project.caseInsensitiveCompare(p) != .orderedSame { return false }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        let hay = ([title, body, client, project] + tags + tasks.map(\.text) + files.map(\.name)).joined(separator: "\n")
        return hay.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}

/// Tag bez # i spacji na brzegach.
func cleanTag(_ s: String) -> String {
    var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    while t.hasPrefix("#") { t.removeFirst() }
    return t.trimmingCharacters(in: .whitespaces)
}

enum CalMode: String { case client, project, tag }
struct Seg: Hashable { let key: String; let color: Color; let label: String }

struct NoteColor {
    let name: String; let bg: Color; let dark: Bool
    /// Ciemny wygląd: kolor karteczki jako akcent (pasek, kółka, kreska u góry); w jasnym nil.
    var tint: Color? = nil
}

/// Wygląd: systemowy, jasny albo ciemny (ciemne karteczki w kolorze, jasny tekst).
enum Theme {
    /// 0 systemowy, 1 jasny, 2 ciemny
    static var mode: Int {
        get {
            if let t = ProcessInfo.processInfo.environment["STOSIK_THEME"] { return t == "dark" ? 2 : 1 }
            // domyślnie jasny (kolorowe karteczki); ciemny albo systemowy wybiera się w ustawieniach
            return UserDefaults.standard.object(forKey: "theme") == nil ? 1 : UserDefaults.standard.integer(forKey: "theme")
        }
        set { UserDefaults.standard.set(newValue, forKey: "theme"); refresh() }
    }
    /// Liczone raz na zmianę (czytane przy każdym rysowaniu karteczek).
    private(set) static var dark = false
    static func refresh() {
        dark = mode == 2 || (mode == 0 && UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark")
    }
    static var appearance: NSAppearance? { NSAppearance(named: dark ? .darkAqua : .aqua) }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255,
                  blue: Double(hex & 255) / 255, opacity: 1)
    }
    /// Tekst: ciemny w jasnym wyglądzie, jasny w ciemnym.
    static var ink: Color { Theme.dark ? Color(hex: 0xEDE8E1) : Color(hex: 0x26221F) }
    /// Zawsze ciemny (okienko powitalne ma własny, jasny wygląd).
    static let inkFixed = Color(hex: 0x26221F)
    /// Tekst na wypełnieniu w kolorze `ink` (np. czarny przycisk z białym napisem).
    static var onInk: Color { Theme.dark ? Color(hex: 0x1E1D22) : .white }
    /// Biała kartka „Na dziś” (w ciemnym wyglądzie grafitowa).
    static var paperWhite: Color { Theme.dark ? Color(hex: DARK_CARD) : .white }
}

let PALETTE: [NoteColor] = [
    NoteColor(name: "Krem", bg: Color(hex: 0xF7F1E7), dark: false),
    NoteColor(name: "Róż", bg: Color(hex: 0xEDBBD3), dark: false),
    NoteColor(name: "Pomarańcz", bg: Color(hex: 0xE6814F), dark: false),
    NoteColor(name: "Żółty", bg: Color(hex: 0xF4E383), dark: false),
    NoteColor(name: "Limonka", bg: Color(hex: 0xCBE46E), dark: false),
    NoteColor(name: "Mięta", bg: Color(hex: 0x7DD0A3), dark: false),
    NoteColor(name: "Błękit", bg: Color(hex: 0xAADDF3), dark: false),
    NoteColor(name: "Lawenda", bg: Color(hex: 0xA597F3), dark: false),
    NoteColor(name: "Czerwień", bg: Color(hex: 0xEC5B44), dark: false),
    NoteColor(name: "Grafit", bg: Color(hex: 0x2D2C31), dark: true),
]

/// Ciemny wygląd: wszystkie karteczki w jednym grafitowym kolorze, kolor karteczki tylko jako akcent.
let DARK_CARD: UInt32 = 0x202023

/// Jasny kolor karteczki do kropek, pasków i pierścieni (także w ciemnym wyglądzie, żeby było je widać).
func accent(_ i: Int) -> Color { PALETTE[max(0, min(PALETTE.count - 1, i))].bg }

func palette(_ i: Int) -> NoteColor {
    let k = max(0, min(PALETTE.count - 1, i))
    if Theme.dark {
        // grafitowa karteczka ma akcent w jasnej szarości (inaczej by zniknął)
        let tint = k == PALETTE.count - 1 ? Color(hex: 0xA3A3AB) : PALETTE[k].bg
        return NoteColor(name: PALETTE[k].name, bg: Color(hex: DARK_CARD), dark: true, tint: tint)
    }
    return PALETTE[k]
}

// MARK: - Terminy


func timeString(_ d: Date) -> String {
    let c = Calendar.current.dateComponents([.hour, .minute], from: d)
    return String(format: "%d:%02d", c.hour ?? 0, c.minute ?? 0)
}

func daysLabel(_ n: Int) -> String { n == 1 ? L("1 dzień") : LF("%d dni", n) }

/// Napis przy dacie i jego waga: 3 po terminie, 2 dziś/jutro, 1 do 3 dni, 0 do tygodnia.
func dueInfo(_ n: Note, now: Date = Date()) -> (text: String, level: Int)? {
    guard let d = n.deadline, !n.archived else { return nil }
    if n.allDone { return (L("zrobione"), -1) }
    let cal = Calendar.current
    let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: d)).day ?? 0
    if days < 0 || (n.hasTime && d < now) { return (L("po terminie"), 3) }
    if days == 0 { return (n.hasTime ? "\(L("dziś")) \(timeString(d))" : L("dziś"), 2) }
    if days == 1 { return (n.hasTime ? "\(L("jutro")) \(timeString(d))" : L("jutro"), 2) }
    if days <= 3 { return (LF("za %@", daysLabel(days)), 1) }
    if days <= 7 { return (LF("za %@", daysLabel(days)), 0) }
    return nil
}

// MARK: - Zapis

final class Store: ObservableObject {
    static let shared = Store()

    @Published var notes: [Note] = [] { didSet { scheduleSave() } }
    /// Kolor każdego tagu (indeks w PALETTE), nadawany automatycznie.
    @Published var tagColors: [String: Int] = [:]
    /// Kosz: usunięte karteczki, 30 dni (osobny plik kosz.json).
    @Published var trash: [Note] = []
    static let TRASH_DAYS = 30
    private var trashFile: URL { dir.appendingPathComponent("kosz.json") }
    private var tagFile: URL { dir.appendingPathComponent("tagi.json") }
    let dir: URL
    private var file: URL { dir.appendingPathComponent("karteczki.json") }
    private var saveWork: DispatchWorkItem?
    private var loading = true

    init() {
        Lang.resolve()
        if let p = ProcessInfo.processInfo.environment["STOSIK_DIR"] {
            dir = URL(fileURLWithPath: p)
        } else {
            dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Stosik")
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: file) {
            if let n = try? dec.decode([Note].self, from: data) {
                notes = n
            } else {
                // plik jest, ale nie da się go odczytać: najpierw kopia, żeby nic nie przepadło
                let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd-HHmmss"
                let backup = dir.appendingPathComponent("karteczki-kopia-\(f.string(from: Date())).json")
                try? FileManager.default.copyItem(at: file, to: backup)
                notes = []
            }
        } else {
            notes = Store.samples()
        }
        if let d = try? Data(contentsOf: trashFile), let t = try? dec.decode([Note].self, from: d) {
            let limit = Date().addingTimeInterval(-Double(Store.TRASH_DAYS) * 86400)
            trash = t.filter { ($0.deletedAt ?? Date()) > limit }
        }
        if let d = try? Data(contentsOf: tagFile), let m = try? JSONDecoder().decode([String: Int].self, from: d) { tagColors = m }
        loading = false
        save()
        cleanFiles()
    }

    // MARK: załączniki (kopie plików, żeby nie zginęły, gdy oryginał się przesunie)
    var filesDir: URL { dir.appendingPathComponent("zalaczniki") }
    func fileURL(_ note: UUID, _ a: Attachment) -> URL {
        filesDir.appendingPathComponent(note.uuidString).appendingPathComponent(a.id.uuidString).appendingPathComponent(a.name)
    }
    /// Kopiuje pliki do karteczki. Foldery i pliki, których nie da się skopiować, pomija.
    func attach(_ id: UUID, _ urls: [URL]) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        let fm = FileManager.default
        var added: [Attachment] = []
        for u in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: u.path, isDirectory: &isDir), !isDir.boolValue else { continue }
            let a = Attachment(name: u.lastPathComponent,
                               size: Int64((try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0))
            let dest = fileURL(id, a)
            do {
                try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: u, to: dest)
                added.append(a)
            } catch { continue }
        }
        if !added.isEmpty { notes[i].files += added }
    }
    func detach(_ id: UUID, _ a: Attachment) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[i].files.removeAll { $0.id == a.id }
        try? FileManager.default.removeItem(at: fileURL(id, a).deletingLastPathComponent())
    }
    /// Usuwa kopie plików karteczek, których nie ma już ani na stosie, ani w koszu.
    func cleanFiles() {
        let keep = Set((notes + trash).map(\.id.uuidString))
        let fm = FileManager.default
        for d in (try? fm.contentsOfDirectory(atPath: filesDir.path)) ?? [] where !keep.contains(d) && !d.hasPrefix(".") {
            try? fm.removeItem(at: filesDir.appendingPathComponent(d))
        }
    }

    var active: [Note] { notes.filter { !$0.archived } }
    var archived: [Note] { notes.filter(\.archived) }

    /// Wszyscy klienci albo projekty (z liczbą karteczek), najczęstsze pierwsze.
    func names(_ get: (Note) -> String, in list: [Note]? = nil) -> [(tag: String, count: Int)] {
        var count: [String: Int] = [:], spelled: [String: String] = [:]
        for n in list ?? active {
            let t = get(n).trimmingCharacters(in: .whitespaces); guard !t.isEmpty else { continue }
            let k = t.lowercased(); count[k, default: 0] += 1; if spelled[k] == nil { spelled[k] = t }
        }
        return count.map { (spelled[$0.key]!, $0.value) }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    }
    var allClients: [(tag: String, count: Int)] { names { $0.client } }
    func allProjects(client: String? = nil) -> [(tag: String, count: Int)] {
        guard let client, !client.isEmpty else { return names { $0.project } }
        return names({ $0.project }, in: active.filter { $0.client.caseInsensitiveCompare(client) == .orderedSame })
    }

    /// Wszystkie tagi, najczęstsze pierwsze (jedna pisownia na tag).
    var allTags: [(tag: String, count: Int)] {
        var count: [String: Int] = [:], spelled: [String: String] = [:]
        for n in notes where !n.archived {
            for t in n.tags { let k = t.lowercased(); count[k, default: 0] += 1; if spelled[k] == nil { spelled[k] = t } }
        }
        return count.map { (spelled[$0.key]!, $0.value) }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    }

    /// Przestawia w obrębie widocznych (np. po filtrze): staje przed karteczką, która była na miejscu docelowym.
    func move(_ id: UUID, toVisible index: Int, in visible: [Note]) {
        guard visible.count == active.count else {
            var v = visible.map(\.id); guard let from = v.firstIndex(of: id) else { return }
            v.remove(at: from); let to = max(0, min(v.count, index))
            var act = active; let n = act.first { $0.id == id }!; act.removeAll { $0.id == id }
            let pos = to < v.count ? (act.firstIndex { $0.id == v[to] } ?? act.count) : (v.last.flatMap { l in act.firstIndex { $0.id == l }.map { $0 + 1 } } ?? act.count)
            act.insert(n, at: pos); notes = act + archived; return
        }
        move(id, to: index)
    }

    func binding(_ id: UUID) -> Binding<Note> {
        Binding(get: { self.notes.first { $0.id == id } ?? Note() },
                set: { v in
                    guard let i = self.notes.firstIndex(where: { $0.id == id }), self.notes[i] != v else { return }
                    var v = v
                    // kiedy odhaczono zadanie (do podsumowania miesiąca)
                    let old = Dictionary(self.notes[i].tasks.map { ($0.id, $0.done) }, uniquingKeysWith: { a, _ in a })
                    for k in v.tasks.indices {
                        if v.tasks[k].done, old[v.tasks[k].id] != true, v.tasks[k].doneAt == nil { v.tasks[k].doneAt = Date() }
                        if !v.tasks[k].done { v.tasks[k].doneAt = nil }
                    }
                    self.notes[i] = v
                })
    }

    @discardableResult
    func add() -> UUID {
        let used = Set(active.suffix(3).map(\.color))
        var n = Note()
        n.color = ([1, 2, 3, 4, 5, 6, 7, 0].first { !used.contains($0) }) ?? 0
        n.tasks = [TaskItem()]
        notes.insert(n, at: 0)
        return n.id
    }

    /// Do kosza (da się przywrócić przez 30 dni).
    func delete(_ id: UUID) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        var n = notes.remove(at: i); n.deletedAt = Date()
        trash.insert(n, at: 0); saveTrash()
    }
    func restore(_ id: UUID) {
        guard let i = trash.firstIndex(where: { $0.id == id }) else { return }
        var n = trash.remove(at: i); n.deletedAt = nil
        if n.archived { notes.append(n) } else { notes.insert(n, at: 0) }
        saveTrash()
    }
    func deleteForever(_ id: UUID) { trash.removeAll { $0.id == id }; saveTrash(); cleanFiles() }
    func emptyTrash() { trash.removeAll(); saveTrash(); cleanFiles() }
    func daysLeft(_ n: Note) -> Int {
        let gone = (n.deletedAt ?? Date()).addingTimeInterval(Double(Store.TRASH_DAYS) * 86400)
        return max(0, Int(ceil(gone.timeIntervalSinceNow / 86400)))
    }
    func saveTrash() {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        if let d = try? enc.encode(trash) { try? d.write(to: trashFile, options: .atomic) }
    }

    func setArchived(_ id: UUID, _ a: Bool) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        var n = notes.remove(at: i); n.archived = a; n.archivedAt = a ? Date() : nil
        if a { notes.append(n) } else { notes.insert(n, at: 0) }
    }

    /// Przestawia karteczkę na nowe miejsce w stosie (liczone wśród aktywnych).
    func move(_ id: UUID, to index: Int) {
        var act = active
        guard let from = act.firstIndex(where: { $0.id == id }) else { return }
        let n = act.remove(at: from)
        act.insert(n, at: max(0, min(act.count, index)))
        notes = act + archived
    }

    private func scheduleSave() {
        guard !loading else { return }
        saveWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.save() }
        saveWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: w)
    }

    func save() {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted]
        if let d = try? enc.encode(notes) { try? d.write(to: file, options: .atomic) }
        ensureTagColors()
        Reminders.reschedule(notes)
    }

    static let TAG_ORDER = [5, 2, 7, 1, 6, 3, 4, 8, 0, 9]

    func ensureTagColors() {
        var m = tagColors
        // osobne kolory dla tagów, klientów („c:”) i projektów („p:”)
        for kind in ["", "c:", "p:"] {
            var used = Set(m.filter { k, _ in kind.isEmpty ? !(k.hasPrefix("c:") || k.hasPrefix("p:")) : k.hasPrefix(kind) }.values)
            for n in notes {
                let names = kind.isEmpty ? n.tags : kind == "c:" ? [n.client] : [n.project]
                for t in names where !t.trimmingCharacters(in: .whitespaces).isEmpty && m[kind + t.lowercased()] == nil {
                    let i = Store.TAG_ORDER.first { !used.contains($0) } ?? Store.TAG_ORDER[used.count % 8]
                    m[kind + t.lowercased()] = i; used.insert(i)
                }
            }
        }
        guard m != tagColors else { return }
        tagColors = m
        if let d = try? JSONEncoder().encode(m) { try? d.write(to: tagFile, options: .atomic) }
    }

    func tagColor(_ t: String, kind: String = "") -> Color {
        if let i = tagColors[kind + t.lowercased()] { return accent(i) }
        return accent(Store.TAG_ORDER[abs(t.lowercased().hashValue) % 8])
    }
    func clientColor(_ c: String) -> Color { tagColor(c, kind: "c:") }

    /// Ręczny wybór koloru klienta („c:”), projektu („p:”) albo tagu („”).
    func setColor(_ name: String, kind: String, index: Int) {
        let n = name.trimmingCharacters(in: .whitespaces); guard !n.isEmpty else { return }
        tagColors[kind + n.lowercased()] = index
        if let d = try? JSONEncoder().encode(tagColors) { try? d.write(to: tagFile, options: .atomic) }
        objectWillChange.send()
    }

    // MARK: pierścienie dni

    /// Projekty, które tego dnia „żyły”: odhaczone zadanie, termin albo zamknięcie.
    func touched(on day: Date) -> [Note] {
        let cal = Calendar.current
        func same(_ d: Date?) -> Bool { d.map { cal.isDate($0, inSameDayAs: day) } ?? false }
        return notes.filter { n in
            n.tasks.contains { $0.done && same($0.doneAt) } || (!n.archived && same(n.deadline)) || (n.archived && same(n.archivedAt))
        }
    }

    func segments(on day: Date, mode: CalMode) -> [Seg] { segments(of: touched(on: day), mode: mode) }

    func segments(of list: [Note], mode: CalMode) -> [Seg] {
        var out: [Seg] = [], seen = Set<String>()
        for n in list {
            let s: Seg
            switch mode {
            case .client:
                if !n.client.isEmpty { s = Seg(key: "c:" + n.client.lowercased(), color: clientColor(n.client), label: n.client) }
                else { s = Seg(key: "", color: Color(hex: 0xB9B5AE), label: L("bez klienta")) }
            case .project:
                if !n.project.isEmpty { s = Seg(key: "p:" + n.project.lowercased(), color: tagColor(n.project, kind: "p:"), label: n.project) }
                else { s = Seg(key: n.id.uuidString, color: accent(n.color), label: n.shownTitle) }
            case .tag:
                if let t = n.tags.first { s = Seg(key: t.lowercased(), color: tagColor(t), label: t) }
                else { s = Seg(key: "", color: Color(hex: 0xB9B5AE), label: L("bez tagu")) }
            }
            if seen.insert(s.key).inserted { out.append(s) }
        }
        return out
    }

    func closedOn(_ day: Date) -> Bool {
        archived.contains { $0.archivedAt.map { Calendar.current.isDate($0, inSameDayAs: day) } ?? false }
    }
    func deadlineOn(_ day: Date) -> Bool {
        active.contains { !$0.allDone && ($0.deadline.map { Calendar.current.isDate($0, inSameDayAs: day) } ?? false) }
    }

    /// Projekty miesiąca: w bieżącym wszystko na stosie plus zamknięte; w innym to, co miało w nim termin, zamknięcie albo odhaczenie.
    func projects(in m: Date, _ g: Calendar.Component = .month) -> [Note] {
        let now = Calendar.current.isDate(m, equalTo: Date(), toGranularity: g)
        return notes.filter { n in
            if n.archived { return Store.same(n.archivedAt, month: m, g) }
            if now { return true }
            return Store.same(n.deadline, month: m, g) || n.tasks.contains { $0.done && Store.same($0.doneAt, month: m, g) }
        }
    }
    func progress(in m: Date, _ g: Calendar.Component = .month) -> (done: Int, total: Int) {
        let ps = projects(in: m, g)
        return (ps.reduce(0) { $0 + $1.doneCount }, ps.reduce(0) { $0 + $1.tasks.count })
    }

    // MARK: podsumowanie miesiąca

    static func same(_ a: Date?, month m: Date, _ g: Calendar.Component = .month) -> Bool {
        guard let a else { return false }
        return Calendar.current.isDate(a, equalTo: m, toGranularity: g)
    }
    func closed(in m: Date, _ g: Calendar.Component = .month) -> [Note] {
        archived.filter { Store.same($0.archivedAt, month: m, g) }.sorted { ($0.archivedAt ?? .distantPast) > ($1.archivedAt ?? .distantPast) }
    }
    func tasksDone(in m: Date, _ g: Calendar.Component = .month) -> Int {
        notes.reduce(0) { $0 + $1.tasks.filter { $0.done && Store.same($0.doneAt, month: m, g) }.count }
    }
    func due(in m: Date, _ g: Calendar.Component = .month) -> [Note] {
        active.filter { Store.same($0.deadline, month: m, g) }.sorted { $0.deadline! < $1.deadline! }
    }
    /// Aktywne z terminem od dziś w górę (i zaległe), najbliższe pierwsze.
    var upcoming: [Note] {
        active.filter { $0.deadline != nil && !$0.allDone }.sorted { $0.deadline! < $1.deadline! }
    }
    static func samples() -> [Note] {
        let cal = Calendar.current
        var a = Note(); a.title = L("Witaj w Stosiku"); a.color = 0; a.priority = 1
        a.tasks = [L("Najedź myszką na stos"), L("Kliknij karteczkę, żeby ją edytować"), L("Przeciągnij kartkę w bok"),
                   L("Kliknij kółeczko, gdy zrobione")].map { TaskItem(text: $0) }
        var b = Note(); b.title = L("Prezentacja dla klienta"); b.color = 2; b.priority = 3
        b.deadline = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))
        b.tags = ["design"]; b.client = "Studio Nova"; b.project = "Branding"; b.alerts = [1440, 0]
        a.tags = [L("Stosik")]
        b.tasks = [TaskItem(text: L("Poprawić slajdy"), done: true, doneAt: cal.date(byAdding: .day, value: -1, to: Date())),
                   TaskItem(text: L("Dorobić obrazki")), TaskItem(text: L("Umówić spotkanie")), TaskItem(text: L("Wysłać do klienta"))]
        var c = Note(); c.title = L("Zakupy"); c.color = 3; c.priority = 0
        c.tasks = [L("Chleb"), L("Kawa"), L("Baterie AA")].map { TaskItem(text: $0) }
        if ProcessInfo.processInfo.environment["STOSIK_SNAP"] != nil {
            // do zrzutów: jeden dzień z trzema projektami
            let y = cal.date(byAdding: .day, value: -1, to: Date())
            c.tasks[0].done = true; c.tasks[0].doneAt = y
            a.tasks[0].done = true; a.tasks[0].doneAt = y
        }
        var d = Note(); d.title = L("Pomysły na weekend"); d.color = 1; d.priority = 2
        d.tags = [L("pomysły")]
        c.tags = [L("dom")]
        d.body = L("Wycieczka rowerowa, kino, nowa kawiarnia.")
        d.deadline = cal.date(byAdding: .day, value: 6, to: Date())
        var e = Note(); e.title = L("Nowe logo"); e.color = 7; e.priority = 2; e.tags = ["logo"]; e.client = "Studio Nova"; e.project = "Branding"
        e.tasks = [L("Szkice"), L("Poprawki"), L("Eksport")].map { TaskItem(text: $0, done: true, doneAt: cal.date(byAdding: .day, value: -4, to: Date())) }
        e.archived = true; e.archivedAt = cal.date(byAdding: .day, value: -3, to: Date())
        var extra: [Note] = []
        if ProcessInfo.processInfo.environment["STOSIK_SNAP"] != nil {
            for (i, t) in [L("Klient: kawiarnia"), L("Faktury"), L("Prezent dla mamy")].enumerated() {
                var x = Note(); x.title = t; x.color = [6, 5, 4][i]; x.tasks = [TaskItem(text: L("Pierwszy krok"))]
                if i == 0 { x.client = "Kawiarnia Róża"; x.project = "Menu" }
                extra.append(x)
            }
        }
        return [b, a, d, c] + extra + [e]
    }
}

// MARK: - Przypomnienia

enum Reminders {
    static var enabled: Bool { Bundle.main.bundleIdentifier != nil && ProcessInfo.processInfo.environment["STOSIK_SNAP"] == nil }

    static func setup() {
        guard enabled else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func reschedule(_ notes: [Note]) {
        guard enabled else { return }
        let c = UNUserNotificationCenter.current()
        c.removeAllPendingNotificationRequests()
        let cal = Calendar.current, now = Date()
        for n in notes where !n.archived && !n.allDone && n.remind {
            guard let d = n.deadline else { continue }
            let title = n.title.isEmpty ? L("Karteczka bez tytułu") : n.title
            let left = n.tasks.count - n.doneCount
            let body = n.tasks.isEmpty ? L("Kliknij, żeby otworzyć karteczkę.") : LF("Zostało zadań: %d z %d.", left, n.tasks.count)
            guard let base = n.alertBase else { continue }
            _ = (cal, now, d)
            for m in Set(n.alerts) {
                let head = m == 0 ? (n.hasTime ? LF("Teraz: %@", title) : LF("Dziś termin: %@", title))
                                  : LF("%@: %@", alertShort(m), title)
                add(c, "\(n.id)-\(m)", base.addingTimeInterval(-Double(m) * 60), head, body, n.id)
            }
        }
    }

    private static func add(_ c: UNUserNotificationCenter, _ id: String, _ at: Date, _ title: String, _ body: String, _ note: UUID) {
        guard at > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = title; content.body = body; content.sound = .default
        content.userInfo = ["note": note.uuidString]
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: at)
        c.add(UNNotificationRequest(identifier: id, content: content,
                                    trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
    }
}

// MARK: - Przypomnienia: gotowe odstępy jak w systemowym Kalendarzu

let ALERT_PRESETS = [0, 5, 15, 30, 60, 120, 1440, 2880, 10080]

/// „1 dzień przed”, „30 min przed”, „W chwili terminu”.
func alertLabel(_ m: Int) -> String {
    if m == 0 { return L("W chwili terminu") }
    if m < 0 { return LF("%@ po terminie", alertAmount(-m)) }
    return LF("%@ przed", alertAmount(m))
}
/// Do tytułu powiadomienia: „Za 1 dzień”.
func alertShort(_ m: Int) -> String { m < 0 ? L("Po terminie") : LF("Za %@", alertAmount(m)) }

func alertAmount(_ m: Int) -> String {
    if m % 10080 == 0 { let w = m / 10080; return w == 1 ? L("1 tydzień") : LF("%d tyg.", w) }
    if m % 1440 == 0 { let d = m / 1440; return d == 1 ? L("1 dzień") : LF("%d dni", d) }
    if m % 60 == 0 { return LF("%d godz.", m / 60) }
    return LF("%d min", m)
}

// MARK: - Na dziś

/// Jeden wiersz kartki „Na dziś”: klient (albo projekt, albo tytuł) i ile zostało zrobić.
struct TodayGroup: Identifiable {
    var id: String { key }
    var key: String
    var name: String
    var client: String
    var project: String
    var open = 0
    var total = 0
    var notes: [UUID] = []
    /// Coś z tej grupy jest po terminie (z poprzednich dni, nieskończone).
    var overdue = false
    /// Projekty klienta i ile w każdym zostało (pod nazwą klienta, gdy jest ich więcej niż jeden).
    var projects: [(name: String, open: Int)] = []
}

extension Store {
    /// Karteczki z terminem na dziś, zebrane po kliencie, w kolejności ze stosu.
    func todayGroups(_ notes: [Note], now: Date = Date()) -> [TodayGroup] {
        var out: [TodayGroup] = []
        for n in notes {
            guard let d = n.deadline else { continue }
            // dziś albo zaległe z poprzednich dni, dopóki nie są zrobione
            let late = d < Calendar.current.startOfDay(for: now)
            guard Calendar.current.isDate(d, inSameDayAs: now) || (late && !n.allDone) else { continue }
            let name = !n.client.isEmpty ? n.client : !n.project.isEmpty ? n.project : n.shownTitle
            let key = (!n.client.isEmpty ? "c:" : !n.project.isEmpty ? "p:" : "t:") + name.lowercased()
            // karteczka bez zadań liczy się jako jedna rzecz do zrobienia
            let total = max(1, n.tasks.count), open = n.tasks.isEmpty ? 1 : n.tasks.count - n.doneCount
            if out.firstIndex(where: { $0.key == key }) == nil {
                out.append(TodayGroup(key: key, name: name, client: n.client, project: n.client.isEmpty ? n.project : ""))
            }
            let i = out.firstIndex { $0.key == key }!
            out[i].open += open; out[i].total += total; out[i].notes.append(n.id)
            if late { out[i].overdue = true }
            if !n.client.isEmpty {
                // karteczka klienta bez projektu liczy się pod swoim tytułem
                let pname = !n.project.isEmpty ? n.project : n.shownTitle
                if let j = out[i].projects.firstIndex(where: { $0.name.lowercased() == pname.lowercased() }) {
                    out[i].projects[j].open += open
                } else {
                    out[i].projects.append((pname, open))
                }
            }
        }
        return out
    }
}
