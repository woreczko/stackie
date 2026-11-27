import AppKit
import Security
import UserNotifications

/// Aktualizacje z GitHuba: przy starcie oraz o 10:37 i 21:37 sprawdza najnowsze wydanie, pobiera je w tle,
/// sprawdza podpis (Developer ID tego samego zespołu, co działająca apka) i podmienia apkę,
/// gdy nikt jej nie używa albo przy zamykaniu. Karteczki leżą osobno i nic się z nimi nie dzieje.
final class Updater: ObservableObject {
    static let shared = Updater()

    /// Stan widoczny w ustawieniach (sprawdzanie z palca).
    enum Status: Equatable { case idle, checking, upToDate, downloading(String), ready(String), failed, unsigned }
    @Published private(set) var status: Status = .idle
    /// Sprawdzenie z palca: po pobraniu od razu podmiana i ponowne uruchomienie (menu w pasku).
    private var installWhenReady = false
    private func set(_ s: Status) { DispatchQueue.main.async { self.status = s } }
    static let repo = "woreczko/stackie"

    /// Włączone w menu (domyślnie tak).
    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "autoUpdate") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "autoUpdate"); if newValue { check() } }
    }
    /// Pobrana i sprawdzona nowa wersja, czeka na podmianę.
    private(set) var ready: (version: String, app: URL)?
    private var busy = false
    private var timer: Timer?
    private var idleNeeded: Double = 600

    private var dir: URL { Store.shared.dir.appendingPathComponent("aktualizacja") }
    private var lastCheck: Date {
        get { UserDefaults.standard.object(forKey: "updateChecked") as? Date ?? .distantPast }
        set { UserDefaults.standard.set(newValue, forKey: "updateChecked") }
    }

    /// Zespół, którym podpisana jest działająca apka. Wersje z `zbuduj.sh` (podpis ad hoc) go nie mają
    /// i wtedy aktualizacje są wyłączone: apka zbudowana na miejscu nie podmieni się sama.
    lazy var teamID: String? = {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var stat: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &stat) == errSecSuccess, let stat else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(stat, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let d = info as? [String: Any] else { return nil }
        return d[kSecCodeInfoTeamIdentifier as String] as? String
    }()

    func start() {
        guard ProcessInfo.processInfo.environment["STOSIK_SNAP"] == nil,
              ProcessInfo.processInfo.environment["STOSIK_DIR"] == nil, teamID != nil else { return }
        try? FileManager.default.removeItem(at: dir)          // resztki po poprzedniej aktualizacji
        let now = ProcessInfo.processInfo.environment["STOSIK_UPDATE_NOW"] != nil   // test: od razu, bez czekania na bezczynność
        if now { idleNeeded = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + (now ? 2 : 60)) { self.check() }
        // co minutę: sprawdzenie o 10:37 i 21:37 (gdy Mac wtedy spał, zaraz po wybudzeniu), podmiana, gdy nikt nie używa apki
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            if let due = Updater.lastSlot(before: Date()), self.lastCheck < due { self.check() }
            self.installIfIdle()
        }
    }

    /// Stałe godziny sprawdzania.
    static let slots = [(10, 37), (21, 37)]
    /// Ostatnia minięta godzina sprawdzania (dziś albo wczoraj wieczorem).
    static func lastSlot(before now: Date) -> Date? {
        let cal = Calendar.current
        let days = [now, cal.date(byAdding: .day, value: -1, to: now)!]
        return days.flatMap { d in slots.compactMap { cal.date(bySettingHour: $0.0, minute: $0.1, second: 0, of: d) } }
            .filter { $0 <= now }.max()
    }

    // MARK: sprawdzenie i pobranie

    /// Z palca: sprawdza od razu, także gdy samoczynne aktualizacje są wyłączone.
    /// `install`: gdy nowa wersja jest gotowa, od razu ją instaluje i uruchamia ponownie.
    func checkNow(install: Bool = false) {
        guard teamID != nil else { status = .unsigned; return }
        if install { installWhenReady = true }
        if let r = ready {
            status = .ready(r.version)
            if installWhenReady { self.install(relaunch: true) }
            return
        }
        check(force: true)
    }

    func check(force: Bool = false) {
        guard enabled || force, !busy, ready == nil, teamID != nil else { return }
        busy = true
        if force { set(.checking) }
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Updater.repo)/releases/latest")!)
        req.setValue("Stackie-updater", forHTTPHeaderField: "User-Agent")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            DispatchQueue.main.async { self.lastCheck = Date() }
            guard let data, let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = j["tag_name"] as? String,
                  let assets = j["assets"] as? [[String: Any]],
                  let zip = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".zip") == true }),
                  let link = (zip["browser_download_url"] as? String).flatMap(URL.init(string:)) else { return self.done(.failed) }
            let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            guard Updater.newer(version, than: APP_VERSION) else { return self.done(.upToDate) }
            self.set(.downloading(version))
            self.download(link, version)
        }.resume()
    }

    private func download(_ link: URL, _ version: String) {
        URLSession.shared.downloadTask(with: link) { file, _, _ in
            guard let file else { return self.done(.failed) }
            let fm = FileManager.default
            let out = self.dir.appendingPathComponent(version)
            try? fm.removeItem(at: self.dir)
            try? fm.createDirectory(at: out, withIntermediateDirectories: true)
            guard Updater.run("/usr/bin/ditto", ["-x", "-k", file.path, out.path]),
                  let app = (try? fm.contentsOfDirectory(at: out, includingPropertiesForKeys: nil))?.first(where: { $0.pathExtension == "app" }),
                  self.trusted(app) else {
                try? fm.removeItem(at: self.dir); return self.done(.failed)
            }
            DispatchQueue.main.async {
                self.ready = (version, app); self.busy = false
                self.status = .ready(version)
                if self.installWhenReady { self.install(relaunch: true) } else { self.installIfIdle() }
            }
        }.resume()
    }

    /// Koniec sprawdzania bez nowej wersji. Stan pokazujemy tylko, gdy ktoś sprawdzał z palca.
    private func done(_ s: Status = .idle) {
        DispatchQueue.main.async {
            self.busy = false
            if self.status != .idle { self.status = s }
            if self.installWhenReady && s != .idle {
                self.installWhenReady = false
                AppDelegate.shared?.updateResult(s)
            }
        }
    }

    /// Podpis Developer ID od Apple, ten sam zespół co działająca apka, nic nie zmienione po podpisaniu.
    private func trusted(_ app: URL) -> Bool {
        guard let team = teamID else { return false }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { return false }
        let text = "anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists"
            + " and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = \"\(team)\""
        var req: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &req) == errSecSuccess, let req else { return false }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        return SecStaticCodeCheckValidity(code, flags, req) == errSecSuccess
    }

    // MARK: podmiana

    /// Nikt nie dotykał klawiatury ani myszy od 10 minut i żadna karteczka nie jest otwarta.
    func installIfIdle() {
        guard ready != nil else { return }
        let any = CGEventType(rawValue: UInt32.max)!
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: any)
        guard idle >= idleNeeded, AppDelegate.shared?.editor?.isVisible != true else { return }
        install(relaunch: true)
    }

    /// Podmienia apkę po zamknięciu tej kopii (osobny proces czeka, aż ta się zamknie).
    func install(relaunch: Bool) {
        guard let (_, app) = ready else { return }
        let target = Bundle.main.bundleURL
        guard FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path) else { return }
        ready = nil
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        rm -rf "$2.old" && mv "$2" "$2.old" && /usr/bin/ditto "$1" "$2" && rm -rf "$2.old" || { rm -rf "$2"; mv "$2.old" "$2"; }
        rm -rf "$3"
        \(relaunch ? "/usr/bin/open \"$2\"" : "")
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script, "sh", app.path, target.path, dir.path]
        try? p.run()
        if relaunch {
            Store.shared.save()
            NSApp.terminate(nil)
        }
    }

    // MARK: po aktualizacji

    /// Wywoływane przy starcie: z jakiej wersji przyszła aktualizacja (nil, gdy to nie aktualizacja).
    static func updatedFrom() -> String? {
        let d = UserDefaults.standard
        let last = d.string(forKey: "lastRunVersion")
        d.set(APP_VERSION, forKey: "lastRunVersion")
        guard let last, newer(APP_VERSION, than: last) else { return nil }
        return last
    }

    /// Krótkie powiadomienie o aktualizacji (gdy nie ma nowych funkcji do pokazania).
    static func announceUpdate() {
        let c = UNMutableNotificationContent()
        c.title = LF("Zaktualizowano do %@", APP_VERSION)
        c.body = L("Kliknij, żeby zobaczyć, co nowego.")
        c.userInfo = ["whatsNew": true]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "update-\(APP_VERSION)", content: c, trigger: nil))
    }

    // MARK: pomocnicze

    static func newer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    @discardableResult
    static func run(_ tool: String, _ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool); p.arguments = args
        do { try p.run(); p.waitUntilExit(); return p.terminationStatus == 0 } catch { return false }
    }
}
