import AppKit
import SwiftUI
import Combine
import UserNotifications
import ServiceManagement

final class Panel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Okno stosu: dla systemu zawsze „aktywne”, żeby szkło paska nie przygasało.
final class StackPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override var isKeyWindow: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {
    let store = Store.shared
    let ui = UIState.shared
    var stack: StackPanel!
    var editor: Panel?
    var editorID: UUID?
    var calendar: Panel?
    var trashWin: Panel?
    var dictWin: Panel?
    var welcomeWin: Panel?
    var savedMode: String?
    var status: NSStatusItem!
    var timer: Timer?
    var bag = Set<AnyCancellable>()
    let defaults = UserDefaults.standard
    var snap: String? { ProcessInfo.processInfo.environment["STOSIK_SNAP"] }

    /// 0 na pulpicie (pod oknami), 1 zwykłe okno, 2 zawsze na wierzchu
    /// Róg ekranu z szybką notatką: 0 wyłączony, 1 lewy górny, 2 prawy górny, 3 lewy dolny, 4 prawy dolny.
    var hotCorner: Int {
        get { defaults.integer(forKey: "hotCorner") }
        set { defaults.set(newValue, forKey: "hotCorner") }
    }
    private var cornerSince: Date?
    private var cornerFired = false

    /// Kursor wjechał w wybrany róg i chwilę tam został: nowa karteczka. Następna dopiero po odjechaniu z rogu.
    func checkHotCorner(_ m: NSPoint) {
        guard hotCorner > 0, snap == nil,
              // ekran, na którym naprawdę jest kursor (na styku dwóch monitorów nie bierzemy sąsiada)
              let s = NSScreen.screens.first(where: { NSMouseInRect(m, $0.frame, false) })
                ?? NSScreen.screens.first(where: { $0.frame.insetBy(dx: -1, dy: -1).contains(m) }) else { return }
        let f = s.frame
        let left = hotCorner == 1 || hotCorner == 3, top = hotCorner <= 2
        let dx = abs(m.x - (left ? f.minX : f.maxX - 1)), dy = abs(m.y - (top ? f.maxY - 1 : f.minY))
        if dx <= 3 && dy <= 3 {
            if cornerSince == nil { cornerSince = Date() }
            if !cornerFired, let t = cornerSince, Date().timeIntervalSince(t) > 0.25 {
                cornerFired = true
                stack?.orderFrontRegardless()
                newNote(centered: true)
            }
        } else {
            cornerSince = nil
            if dx > 80 || dy > 80 { cornerFired = false }
        }
    }

    var levelMode: Int {
        get { defaults.object(forKey: "level") as? Int ?? 1 }
        set { defaults.set(newValue, forKey: "level"); applyLevel() }
    }

    static weak var shared: AppDelegate?

    func applicationDidFinishLaunching(_ n: Notification) {
        AppDelegate.shared = self
        Lang.resolve()
        if Reminders.enabled { UNUserNotificationCenter.current().delegate = self }
        Reminders.setup()
        buildStack()
        buildStatus()
        store.$notes.receive(on: RunLoop.main).sink { [weak self] _ in
            self?.resizeStack(); self?.updateStatusTitle()
        }.store(in: &bag)
        ui.$filterTag.combineLatest(ui.$query, ui.$filterClient, ui.$filterProject).receive(on: RunLoop.main).sink { [weak self] _ in
            DispatchQueue.main.async { self?.resizeStack() }
        }.store(in: &bag)
        let nc = NotificationCenter.default
        nc.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            self?.ui.menuOpen = true
        }
        nc.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            // chwila na to, żeby wybrana opcja zadziałała, potem zwykłe śledzenie myszy
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self?.ui.menuOpen = false }
        }
        timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.pollMouse() }
        RunLoop.main.add(timer!, forMode: .common)
        Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            guard let self, self.snap == nil, !self.ui.spread, self.stack.isVisible else { return }
            self.ui.bounceTick += 1
        }
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.store.objectWillChange.send(); self?.updateStatusTitle()
            self?.resizeStack()   // o północy kartka „Na dziś” może się pojawić albo zniknąć
        }
        // budowanie: zaszyfruj klucz hasłem (zbuduj.sh), wynik na standardowe wyjście
        if let kf = ProcessInfo.processInfo.environment["STOSIK_SEAL_KEY"], let pf = ProcessInfo.processInfo.environment["STOSIK_SEAL_PASS"] {
            let k = (try? String(contentsOfFile: kf, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let pw = (try? String(contentsOfFile: pf, encoding: .utf8))?.trimmingCharacters(in: .newlines) ?? ""
            if !k.isEmpty, !pw.isEmpty, let d = KeyBox.seal(k, password: pw), KeyBox.open(d, password: pw) == k {
                FileHandle.standardOutput.write(d)
                exit(0)
            }
            exit(1)
        }
        if let pw = ProcessInfo.processInfo.environment["STOSIK_OPEN_TEST"] {
            // test hasła bez zapisywania czegokolwiek
            let d = Bundle.main.url(forResource: "k", withExtension: "bin").flatMap { try? Data(contentsOf: $0) }
            print("OPEN", d.flatMap { KeyBox.open($0, password: pw) }.map { "ok …" + $0.suffix(4) } ?? "fail")
            exit(0)
        }
        // test zapytania do Claude (wypisuje wynik i kończy)
        if let t = ProcessInfo.processInfo.environment["STOSIK_SMART_TEST"] {
            Smart.propose(t) { r in
                switch r {
                case .success(let p): print("SMART ok ai=\(p.viaAI) title=\(p.title) client=\(p.result.client) tasks=\(p.result.tasks) due=\(String(describing: p.result.deadline))")
                case .failure(let e): print("SMART fail", e.localizedDescription)
                }
                NSApp.terminate(nil)
            }
        } else if let snap { runSnapshots(snap) }
        else if let from = Updater.updatedFrom() {
            // po aktualizacji: tylko nowe funkcje z pokazami (albo samo powiadomienie, gdy nic nowego do pokazania)
            UserDefaults.standard.set(APP_VERSION, forKey: "welcomeSeen")
            if WelcomeView.hasNew(since: from) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.showWelcome(newSince: from) }
            } else {
                Updater.announceUpdate()
            }
        } else if UserDefaults.standard.string(forKey: "welcomeSeen") != APP_VERSION {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.showWelcome() }
        }
        Updater.shared.start()
    }

    func applicationWillTerminate(_ n: Notification) {
        // pobrana nowa wersja wchodzi przy zamknięciu (następne uruchomienie to już ona)
        Updater.shared.install(relaunch: false)
    }

    // MARK: stos

    func buildStack() {
        let n = ui.slots(store.active)
        StackLayout.fit(count: n, screenWidth: NSScreen.main?.visibleFrame.width ?? 1600)
        let k = StackLayout.scale
        let size = NSSize(width: StackLayout.width(n) * k, height: StackLayout.height * k)
        var origin = NSPoint(x: 80, y: 120)
        if let s = defaults.string(forKey: "stackTopLeft") {
            let p = NSPointFromString(s); origin = NSPoint(x: p.x, y: p.y - size.height)
        } else if let scr = NSScreen.main?.visibleFrame {
            origin = NSPoint(x: scr.minX + 60, y: scr.maxY - size.height - 40)
        }
        stack = StackPanel(contentRect: NSRect(origin: origin, size: size), styleMask: [.borderless, .nonactivatingPanel],
                      backing: .buffered, defer: false)
        stack.isOpaque = false
        stack.backgroundColor = .clear
        stack.hasShadow = false
        stack.hidesOnDeactivate = false
        stack.isMovableByWindowBackground = false
        stack.delegate = self
        let root = StackRoot(openEditor: { [weak self] id in self?.toggleEditor(id) },
                             newNote: { [weak self] in self?.newNote() },
                             openCalendar: { [weak self] in self?.toggleCalendar() })
            .environmentObject(store).environmentObject(ui)
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        stack.contentView = host
        applyLevel()
        stack.orderFrontRegardless()
    }

    func applyLevel() {
        guard let stack else { return }
        switch levelMode {
        case 0:
            stack.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            stack.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        case 2:
            stack.level = .floating
            stack.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        default:
            stack.level = .normal
            stack.collectionBehavior = [.canJoinAllSpaces]
        }
        stack.orderFrontRegardless()
    }

    func resizeStack(force: Bool = false) {
        guard let stack else { return }
        let f = stack.frame
        let count = max(1, ui.slots(ui.visible(store.active)))
        StackLayout.fit(count: count, screenWidth: (stack.screen ?? NSScreen.main)?.visibleFrame.width ?? 1600)
        let k = StackLayout.scale
        let w = max(StackLayout.width(count), 420) * k, h = StackLayout.height * k
        guard force || abs(f.width - w) > 0.5 || abs(f.height - h) > 0.5 else { return }
        stack.setFrame(NSRect(x: f.minX, y: f.maxY - h, width: w, height: h), display: true)
    }

    func windowDidChangeScreen(_ n: Notification) {
        guard (n.object as? NSWindow) === stack else { return }
        resizeStack(force: true)
    }

    func windowDidMove(_ n: Notification) {
        guard (n.object as? NSWindow) === stack else { return }
        defaults.set(NSStringFromPoint(NSPoint(x: stack.frame.minX, y: stack.frame.maxY)), forKey: "stackTopLeft")
    }

    func pollMouse() {
        checkHotCorner(NSEvent.mouseLocation)
        guard let stack, stack.isVisible, snap == nil else { return }
        let m = NSEvent.mouseLocation
        let f = stack.frame
        // kursor daleko, stos spokojny: nic do zrobienia
        if !f.insetBy(dx: -20, dy: -20).contains(m), !ui.spread, ui.hovered == nil, !ui.toolbarHover,
           ui.toolIcon == nil, !ui.toolExpanded { return }
        var p: CGPoint? = nil
        if f.contains(m) {
            let top = NSWindow.windowNumber(at: m, belowWindowWithWindowNumber: 0)
            if top == stack.windowNumber {
                p = CGPoint(x: (m.x - f.minX) / StackLayout.scale, y: (f.maxY - m.y) / StackLayout.scale)
            }
        }
        ui.mouse(at: p, notes: ui.visible(store.active))
    }

    // MARK: edytor

    /// `centered`: karteczka na środku ekranu (z rogu ekranu), inaczej przy kursorze.
    func newNote(centered: Bool = false) {
        let id = store.add()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.openEditor(id, centered: centered) }
    }

    func toggleEditor(_ id: UUID) {
        if editorID == id, editor?.isVisible == true { closeEditor() } else { openEditor(id) }
    }

    func openEditor(_ id: UUID, at point: NSPoint? = nil, centered: Bool = false) {
        let size = NSSize(width: 400, height: 640)
        if editor == nil {
            let p = Panel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                          backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
            p.hidesOnDeactivate = false
            p.isMovableByWindowBackground = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.appearance = NSAppearance(named: .aqua)
            editor = p
        }
        guard let editor else { return }
        editor.level = levelMode == 0 ? .normal : .floating
        editorID = id
        let host = NSHostingView(rootView: EditorView(id: id, close: { [weak self] in self?.closeEditor() })
            .environmentObject(store))
        host.sizingOptions = []
        editor.contentView = host
        let m = point ?? NSEvent.mouseLocation
        let scr = (NSScreen.screens.first { $0.frame.insetBy(dx: -1, dy: -1).contains(m) } ?? NSScreen.main)?.visibleFrame ?? .zero
        var o = NSPoint(x: m.x + 30, y: m.y - size.height / 2)
        if o.x + size.width > scr.maxX - 10 { o.x = m.x - size.width - 30 }
        if centered { o = NSPoint(x: scr.midX - size.width / 2, y: scr.midY - size.height / 2) }
        o.x = max(scr.minX + 10, min(o.x, scr.maxX - size.width - 10))
        o.y = max(scr.minY + 10, min(o.y, scr.maxY - size.height - 10))
        editor.setFrame(NSRect(origin: o, size: size), display: true)
        editor.invalidateShadow()
        NSApp.activate(ignoringOtherApps: true)
        editor.makeKeyAndOrderFront(nil)
    }

    func toggleCalendar() {
        if calendar?.isVisible == true { calendar?.orderOut(nil); return }
        let size = NSSize(width: 800, height: 600)
        if calendar == nil {
            let p = Panel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
            p.hidesOnDeactivate = false; p.isMovableByWindowBackground = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.appearance = NSAppearance(named: .aqua)
            let host = NSHostingView(rootView: CalendarView(
                close: { [weak self] in self?.calendar?.orderOut(nil) },
                open: { [weak self] id in
                    guard let self, let c = self.calendar else { return }
                    self.openEditor(id, at: NSPoint(x: c.frame.maxX - 10, y: c.frame.midY))
                }).environmentObject(store))
            host.sizingOptions = []
            p.contentView = host
            calendar = p
        }
        guard let calendar else { return }
        calendar.level = levelMode == 0 ? .normal : .floating
        let scr = (stack.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let f = stack.frame
        let k = StackLayout.scale
        var o = NSPoint(x: f.minX + StackLayout.padX * k, y: f.minY - size.height + (StackLayout.padTop + 20) * k)
        if o.y < scr.minY + 10 { o.y = f.maxY - 20 }
        o.x = max(scr.minX + 10, min(o.x, scr.maxX - size.width - 10))
        o.y = max(scr.minY + 10, min(o.y, scr.maxY - size.height - 10))
        calendar.setFrame(NSRect(origin: o, size: size), display: true)
        calendar.invalidateShadow()
        NSApp.activate(ignoringOtherApps: true)
        calendar.makeKeyAndOrderFront(nil)
    }

    /// Dyktowanie: nil = nowa karteczka (pierwsze zdanie tytułem), id = zadania do tej karteczki.
    func startDictation(into id: UUID?) {
        let d = Dictation.shared
        if d.recording { return }
        let hint = id == nil ? L("Pierwsze zdanie to tytuł, kolejne to zadania.") : L("Mów, co jest do zrobienia. Każde zdanie to osobne zadanie.")
        let p = dictWin ?? Panel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 190), styleMask: [.borderless], backing: .buffered, defer: false)
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
        p.hidesOnDeactivate = false; p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.level = .floating
        let host = NSHostingView(rootView: DictationView(hint: hint,
            done: { [weak self] in self?.finishDictation(into: id) },
            cancel: { [weak self] in Dictation.shared.cancel(); self?.dictWin?.orderOut(nil) }))
        p.contentView = host
        let size = host.fittingSize
        // nad stosem albo pod otwartą karteczką
        var o: NSPoint
        if id != nil, let e = editor, e.isVisible { o = NSPoint(x: e.frame.midX - size.width / 2, y: e.frame.minY - size.height - 10) }
        else { o = NSPoint(x: stack.frame.minX + StackLayout.padX * StackLayout.scale,
                           y: stack.frame.maxY - (StackLayout.padTop + StackLayout.cardH + StackLayout.toolbarH + 30) * StackLayout.scale - size.height) }
        let scr = (stack.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        o.x = max(scr.minX + 10, min(o.x, scr.maxX - size.width - 10))
        o.y = max(scr.minY + 10, min(o.y, scr.maxY - size.height - 10))
        p.setFrame(NSRect(origin: o, size: size), display: true)
        dictWin = p
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
        d.start()
    }

    func finishDictation(into id: UUID?) {
        Dictation.shared.finish { [weak self] text in
            guard let self else { return }
            self.dictWin?.orderOut(nil)
            let r = parseDictation(text)
            guard !(r.lead.isEmpty && r.tasks.isEmpty && r.client.isEmpty && r.project.isEmpty) else { return }
            func fill(_ n: inout Note) {
                if !r.client.isEmpty && n.client.isEmpty { n.client = r.client }
                if !r.project.isEmpty && n.project.isEmpty { n.project = r.project }
                for t in r.tags where !n.tags.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) { n.tags.append(t) }
                if let d = r.deadline, n.deadline == nil { n.deadline = d; n.hasTime = r.hasTime }
            }
            if let id {
                var n = self.store.binding(id).wrappedValue
                n.tasks.removeAll { $0.text.trimmingCharacters(in: .whitespaces).isEmpty }
                n.tasks += ((r.lead.isEmpty ? [] : [r.lead]) + r.tasks).map { TaskItem(text: $0) }
                fill(&n)
                self.store.binding(id).wrappedValue = n
            } else {
                let nid = self.store.add()
                var n = self.store.binding(nid).wrappedValue
                var tasks = r.tasks
                // to, co padło przed pierwszym zadaniem, to projekt i tytuł („Studio Nova poprawić prezentację…”)
                // tytuł: tekst przed pierwszym zadaniem, projekt albo klient; zadania zostają zadaniami
                if !r.lead.isEmpty {
                    n.title = r.lead
                    if r.project.isEmpty { n.project = r.lead }
                } else if !r.project.isEmpty {
                    n.title = r.project
                } else if !r.client.isEmpty {
                    n.title = r.client
                } else if !tasks.isEmpty {
                    n.title = tasks.removeFirst()
                }
                n.tasks = tasks.isEmpty ? [TaskItem()] : tasks.map { TaskItem(text: $0) }
                fill(&n)
                self.store.binding(nid).wrappedValue = n
                self.store.ensureTagColors()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    let f = self.stack.frame
                    self.openEditor(nid, at: NSPoint(x: f.minX + (StackLayout.padX + StackLayout.cardW) * StackLayout.scale, y: f.maxY - 200))
                }
            }
        }
    }

    func showWelcome(startPage: Int = 0, newSince: String? = nil) {
        let size = NSSize(width: 560, height: 470)
        let p = welcomeWin ?? Panel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
        p.hidesOnDeactivate = false; p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.appearance = NSAppearance(named: .aqua)
        p.level = .floating
        let host = NSHostingView(rootView: WelcomeView(close: { [weak self] in
            UserDefaults.standard.set(APP_VERSION, forKey: "welcomeSeen")
            self?.welcomeWin?.orderOut(nil)
            self?.welcomeWin?.contentView = nil   // animacje (TimelineView) przestają liczyć w tle
        }, startPage: startPage, newSince: newSince))
        host.sizingOptions = []
        p.contentView = host
        let scr = (stack?.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        p.setFrame(NSRect(x: scr.midX - size.width / 2, y: scr.midY - size.height / 2, width: size.width, height: size.height), display: true)
        welcomeWin = p
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
    }

    func toggleTrash() {
        if trashWin?.isVisible == true { trashWin?.orderOut(nil); return }
        let size = NSSize(width: 380, height: 460)
        if trashWin == nil {
            let p = Panel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
            p.hidesOnDeactivate = false; p.isMovableByWindowBackground = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.appearance = NSAppearance(named: .aqua)
            let host = NSHostingView(rootView: TrashView(close: { [weak self] in self?.trashWin?.orderOut(nil) }).environmentObject(store))
            host.sizingOptions = []
            p.contentView = host
            trashWin = p
        }
        guard let w = trashWin else { return }
        w.level = levelMode == 0 ? .normal : .floating
        let f = stack.frame
        let scr = (stack.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let k = StackLayout.scale
        var o = NSPoint(x: f.minX + StackLayout.padX * k, y: f.maxY - (StackLayout.padTop + StackLayout.cardH + 50) * k - size.height)
        o.x = max(scr.minX + 10, min(o.x, scr.maxX - size.width - 10))
        o.y = max(scr.minY + 10, min(o.y, scr.maxY - size.height - 10))
        w.setFrame(NSRect(origin: o, size: size), display: true)
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    func closeEditor() {
        editor?.orderOut(nil)
        editorID = nil
        store.save()
    }

    // MARK: pasek menu

    func buildStatus() {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.image = AppDelegate.statusIcon()
        status.button?.imagePosition = .imageLeading
        let menu = NSMenu(); menu.delegate = self
        status.menu = menu
        updateStatusTitle()
    }

    /// Ikonka w pasku: zaokrąglony kwadrat w obrysie i jedna mocna warstwa z ukośną górą (jak ikonka pilności).
    static func statusIcon() -> NSImage {
        let img = NSImage(size: NSSize(width: 19, height: 17), flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let card = CGRect(x: 2, y: 4, width: 11.5, height: 11.5)
            // karteczka z tyłu: przekrzywiona, przygaszona
            ctx.saveGState()
            ctx.translateBy(x: card.midX + 3.2, y: card.midY - 2.2)
            ctx.rotate(by: .pi / 180 * 16)
            let bw = card.width
            ctx.addPath(CGPath(roundedRect: CGRect(x: -bw / 2, y: -bw / 2, width: bw, height: bw),
                               cornerWidth: 2.8, cornerHeight: 2.8, transform: nil))
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.5).cgColor); ctx.fillPath()
            ctx.restoreGState()
            // odstęp wokół przedniej karteczki
            ctx.setBlendMode(.clear)
            ctx.addPath(CGPath(roundedRect: card.insetBy(dx: -1.2, dy: -1.2), cornerWidth: 3.6, cornerHeight: 3.6, transform: nil)); ctx.fillPath()
            ctx.setBlendMode(.normal)
            // karteczka z przodu: pełna
            ctx.addPath(CGPath(roundedRect: card, cornerWidth: 2.6, cornerHeight: 2.6, transform: nil))
            ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "Stosik"
        return img
    }

    func updateStatusTitle() {
        let urgent = store.active.filter { (dueInfo($0)?.level ?? 0) >= 2 }.count
        status?.button?.title = urgent > 0 ? " \(urgent)" : ""
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        // Stos
        menu.addItem(item(L("Nowa karteczka"), #selector(menuNew), "n", "plus"))
        menu.addItem(item(L("Kalendarz i podsumowanie"), #selector(menuCalendar), "k", "calendar"))
        menu.addItem(item(stack.isVisible ? L("Schowaj stos") : L("Pokaż stos"), #selector(menuToggle), "",
                          stack.isVisible ? "eye.slash" : "eye"))

        // Terminy
        let due = store.active.filter { (dueInfo($0)?.level ?? -1) >= 1 }
        if !due.isEmpty {
            menu.addItem(.separator())
            menu.addItem(.sectionHeader(title: L("Zbliża się termin")))
            for n in due {
                let it = item("\(n.title.isEmpty ? L("Bez tytułu") : n.title) · \(dueInfo(n)!.text)", #selector(menuOpen(_:)), "", "clock")
                it.representedObject = n.id
                menu.addItem(it)
            }
        }

        // Karteczki
        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: L("Karteczki")))
        let tagsItem = item(L("Pokaż tag"), nil, "", "number")
        let tsub = NSMenu()
        let all = item(L("Wszystkie karteczki"), #selector(menuTag(_:)), ""); all.state = ui.filterTag == nil ? .on : .off
        tsub.addItem(all)
        if !store.allTags.isEmpty { tsub.addItem(.separator()) }
        for t in store.allTags {
            let it = item("#\(t.tag)  (\(t.count))", #selector(menuTag(_:)), ""); it.representedObject = t.tag
            it.state = ui.filterTag?.caseInsensitiveCompare(t.tag) == .orderedSame ? .on : .off
            tsub.addItem(it)
        }
        tagsItem.submenu = tsub; menu.addItem(tagsItem)
        let arch = item(LF("Archiwum (%d)", store.archived.count), nil, "", "archivebox")
        let asub = NSMenu()
        if store.archived.isEmpty {
            let e = NSMenuItem(title: L("Pusto"), action: nil, keyEquivalent: ""); e.isEnabled = false; asub.addItem(e)
        }
        for n in store.archived.reversed() {
            let it = item(LF("Przywróć: %@", n.title.isEmpty ? L("Bez tytułu") : n.title), #selector(menuRestore(_:)), "")
            it.representedObject = n.id
            asub.addItem(it)
        }
        arch.submenu = asub; menu.addItem(arch)
        menu.addItem(item(LF("Kosz (%d)", store.trash.count), #selector(menuTrash), "", "trash"))

        // Ustawienia
        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: L("Ustawienia")))
        let pos = item(L("Położenie stosu"), nil, "", "square.stack")
        let sub = NSMenu()
        for (i, t) in [L("Na pulpicie (pod oknami)"), L("Zwykłe okno"), L("Zawsze na wierzchu")].enumerated() {
            let it = item(t, #selector(menuLevel(_:)), ""); it.tag = i; it.state = levelMode == i ? .on : .off
            sub.addItem(it)
        }
        pos.submenu = sub; menu.addItem(pos)
        let langItem = item(Lang.current == "pl" ? "Język · Language" : "Language · Język", nil, "", "globe")
        let lsub = NSMenu()
        for (code, title) in [("auto", L("Automatycznie (system)")), ("pl", "Polski"), ("en", "English")] {
            let it = item(title, #selector(menuLang(_:)), ""); it.representedObject = code
            it.state = Lang.setting == code ? .on : .off
            lsub.addItem(it)
        }
        langItem.submenu = lsub; menu.addItem(langItem)
        let mini = item(L("Małe karteczki"), #selector(menuMini), "", "rectangle.compress.vertical")
        mini.state = StackLayout.mini ? .on : .off
        menu.addItem(mini)
        let login = item(L("Otwieraj przy logowaniu"), #selector(menuLogin), "", "power")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        if Updater.shared.teamID != nil {
            let up = item(L("Aktualizuj automatycznie"), #selector(menuAutoUpdate), "", "arrow.down.circle")
            up.state = Updater.shared.enabled ? .on : .off
            menu.addItem(up)
            menu.addItem(item(LF("Sprawdź aktualizacje (masz %@)", APP_VERSION), #selector(menuCheckUpdate), "", "arrow.triangle.2.circlepath"))
        }

        // Na koniec
        menu.addItem(.separator())
        menu.addItem(item(L("Witaj i co nowego"), #selector(menuWelcome), "", "sparkles"))
        menu.addItem(item(L("Zakończ Stosik"), #selector(menuQuit), "q"))
    }

    private func item(_ t: String, _ s: Selector?, _ k: String, _ icon: String? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: t, action: s, keyEquivalent: k); i.target = self
        if let icon { i.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil) }
        return i
    }

    @objc func menuNew() { stack.orderFrontRegardless(); newNote() }
    @objc func menuToggle() { if stack.isVisible { stack.orderOut(nil); closeEditor() } else { stack.orderFrontRegardless() } }
    @objc func menuOpen(_ s: NSMenuItem) { if let id = s.representedObject as? UUID { openEditor(id) } }
    @objc func menuTag(_ s: NSMenuItem) { ui.setFilter(tag: s.representedObject as? String); stack.orderFrontRegardless() }
    @objc func menuTrash() { toggleTrash() }
    @objc func menuWelcome() { showWelcome() }
    @objc func menuAutoUpdate() { Updater.shared.enabled.toggle() }
    /// Z menu: sprawdź teraz; nowa wersja instaluje się od razu (apka uruchamia się ponownie), inaczej krótkie powiadomienie.
    @objc func menuCheckUpdate() { Updater.shared.checkNow(install: true) }
    func updateResult(_ s: Updater.Status) {
        let c = UNMutableNotificationContent()
        switch s {
        case .upToDate: c.title = LF("Masz najnowszą wersję (%@)", APP_VERSION)
        case .failed: c.title = L("Nie udało się sprawdzić aktualizacji"); c.body = L("Sprawdź połączenie z internetem i spróbuj później.")
        default: return
        }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "update-check", content: c, trigger: nil))
    }
    /// Małe karteczki (np. na 13–14 cali): tylko tytuł, data i licznik; pełna treść w edytorze.
    @objc func menuMini() { setMini(!StackLayout.mini) }
    func setMini(_ on: Bool) {
        StackLayout.mini = on
        UserDefaults.standard.set(on, forKey: "miniCards")
        resizeStack(force: true)
        ui.objectWillChange.send(); store.objectWillChange.send()
    }
    /// Rozmiar stosu: lewy górny róg zostaje na miejscu, okno i jego zawartość zmieniają skalę.
    func setStackScale(_ k: CGFloat) {
        StackLayout.fullScale = k
        UserDefaults.standard.set(Double(k), forKey: "stackScale")
        resizeStack(force: true)
        // skala nie jest obserwowana przez SwiftUI: stos przerysowuje się od razu, nie dopiero po ruchu myszy
        ui.objectWillChange.send(); store.objectWillChange.send()
    }
    @objc func menuCalendar() { stack.orderFrontRegardless(); toggleCalendar() }
    @objc func menuLang(_ s: NSMenuItem) {
        guard let code = s.representedObject as? String else { return }
        Lang.setting = code
        relocalize()
    }

    /// Nowy język od razu: stos, otwarte okna i przypomnienia dostają nowe napisy.
    func relocalize() {
        let editingID = editor?.isVisible == true ? editorID : nil
        let calOpen = calendar?.isVisible == true
        let root = StackRoot(openEditor: { [weak self] id in self?.toggleEditor(id) },
                             newNote: { [weak self] in self?.newNote() },
                             openCalendar: { [weak self] in self?.toggleCalendar() })
            .environmentObject(store).environmentObject(ui)
        let host = NSHostingView(rootView: root); host.sizingOptions = []
        stack.contentView = host
        if let editingID, let e = editor {
            let f = e.frame
            openEditor(editingID, at: NSPoint(x: f.minX - 30, y: f.midY))
        }
        calendar?.orderOut(nil); calendar = nil
        trashWin?.orderOut(nil); trashWin = nil
        if welcomeWin?.isVisible == true { showWelcome() }
        if calOpen { toggleCalendar() }
        store.save()
    }

    @objc func menuLevel(_ s: NSMenuItem) { levelMode = s.tag }
    @objc func menuRestore(_ s: NSMenuItem) { if let id = s.representedObject as? UUID { store.setArchived(id, false) } }
    @objc func menuQuit() { store.save(); NSApp.terminate(nil) }
    @objc func menuLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch {
            let a = NSAlert(); a.messageText = L("Nie udało się ustawić"); a.informativeText = error.localizedDescription; a.runModal()
        }
    }

    // MARK: powiadomienia

    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification,
                                withCompletionHandler h: @escaping (UNNotificationPresentationOptions) -> Void) {
        h([.banner, .sound])
    }

    func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse,
                                withCompletionHandler h: @escaping () -> Void) {
        if r.notification.request.content.userInfo["whatsNew"] != nil {
            DispatchQueue.main.async { self.showWelcome(startPage: WelcomeView.changelogPage) }
        } else if let s = r.notification.request.content.userInfo["note"] as? String, let id = UUID(uuidString: s) {
            DispatchQueue.main.async {
                self.stack.orderFrontRegardless()
                let f = self.stack.frame
                self.openEditor(id, at: NSPoint(x: f.minX + 260, y: f.maxY - 160))
            }
        }
        h()
    }

    // MARK: zrzuty do sprawdzania (STOSIK_SNAP=folder)

    func runSnapshots(_ dir: String) {
        ui.frozen = true
        func shot(_ w: NSWindow, _ name: String) {
            guard let v = w.contentView, let r = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
            v.cacheDisplay(in: v.bounds, to: r)
            try? r.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
        }
        // kilka karteczek z terminem na dziś: pierwsza w stosie jest wtedy kartka „Na dziś”
        for i in store.notes.indices where [1, 3, 4, 5, 6].contains(i) {
            store.notes[i].deadline = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: Date())
        }
        // jeden klient z dwoma projektami: pod nazwą klienta linijka z projektami
        if store.notes.count > 5 { store.notes[5].client = "Kawiarnia Róża"; store.notes[5].project = L("Ulotki") }
        resizeStack(force: true)
        let s = store.active
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            shot(self.stack, "1_stos")
            self.ui.bounceTick += 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) {
            self.ui.spread = true; self.ui.hovered = s.count > 1 ? s[1].id : s.first?.id
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            shot(self.stack, "2_rozlozony")
            if let id = s.first?.id { self.openEditor(id, at: NSPoint(x: 900, y: 600)) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            guard let id = s.first?.id else { return }
            let w = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 290, height: 420), styleMask: [.borderless], backing: .buffered, defer: false)
            w.appearance = NSAppearance(named: .aqua)
            let h = NSHostingView(rootView: AlertsRow(note: self.store.binding(id), fg: .ink).padding(16).frame(width: 360).background(Color(hex: 0xF7F1E7)))
            w.contentView = h; w.orderFront(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { shot(w, "8_przypomnienia"); w.orderOut(nil) }
            let w2 = NSWindow(contentRect: NSRect(x: 500, y: 100, width: 320, height: 260), styleMask: [.borderless], backing: .buffered, defer: false)
            w2.appearance = NSAppearance(named: .aqua)
            w2.contentView = NSHostingView(rootView: SettingsView().background(Color.white))
            w2.orderFront(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { shot(w2, "9_ustawienia"); w2.orderOut(nil) }
            let w3 = NSWindow(contentRect: NSRect(x: 900, y: 100, width: 300, height: 120), styleMask: [.borderless], backing: .buffered, defer: false)
            w3.contentView = NSHostingView(rootView: HStack(spacing: 30) {
                TrashTarget(armed: false, progress: 0); TrashTarget(armed: false, progress: 0.5); TrashTarget(armed: true, progress: 1)
            }.padding(20).background(Color(hex: 0x1D3BE0)))
            w3.orderFront(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { shot(w3, "12_kosz_pokrywka"); w3.orderOut(nil) }
            Dictation.shared.text = "Zadzwonić do drukarni w sprawie ulotek. Poprawić logo, potem wysłać fakturę do Kawiarni Róża"
            Dictation.shared.recording = true; Dictation.shared.level = 0.5
            for t in ["Studio Nova poprawić prezentację dorobić obrazki wysłać do klienta",
                      "klient Kawiarnia Róża projekt menu zadzwonić do drukarni i poprawić logo tag pilne",
                      "iść kupić chleb potem zapłacić rachunki. Oddać książkę",
                      "zrobić porządek w pamięci telefonu i wysłać część plików",
                      "klient Studio Nova poprawić prezentację dorobić trzy slajdy i na koniec wysłać ją do dwunastej",
                      "jutro o 9:30 zadzwonić do mamy"] { print("DYKT:", parseDictation(t)) }
            let w4 = NSWindow(contentRect: NSRect(x: 1300, y: 100, width: 360, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
            w4.isOpaque = false; w4.backgroundColor = .clear
            w4.contentView = NSHostingView(rootView: DictationView(hint: "", done: {}, cancel: {}))
            w4.orderFront(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { shot(w4, "13_dyktowanie"); w4.orderOut(nil); Dictation.shared.recording = false; Dictation.shared.text = "" }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            if let e = self.editor { shot(e, "3_edytor") }
            self.closeEditor()
            self.ui.hovered = CAL_ID
            self.toggleCalendar()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            shot(self.stack, "4_stos_kalendarz")
            if let c = self.calendar { shot(c, "5_kalendarz") }
            self.savedMode = UserDefaults.standard.string(forKey: "calMode")
            UserDefaults.standard.set("tag", forKey: "calMode")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            if let c = self.calendar { shot(c, "6_kalendarz_tagi") }
            UserDefaults.standard.set(true, forKey: "calYear")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.8) {
            if let c = self.calendar { shot(c, "7_rok") }
            UserDefaults.standard.set(false, forKey: "calYear")
            UserDefaults.standard.set(self.savedMode ?? "project", forKey: "calMode")
            self.calendar?.orderOut(nil)
            let act = self.store.active
            if act.count > 1 { self.ui.spread = true; self.ui.hovered = act[1].id; self.ui.dragID = act[1].id; self.ui.dragDY = 45 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.4) {
            shot(self.stack, "10a_kosz_wysuwa")
            self.ui.dragDY = 130
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 7.0) {
            shot(self.stack, "10_do_kosza")
            self.ui.dragID = nil; self.ui.dragDY = 0
            if let last = self.store.active.last { self.store.delete(last.id) }
            self.toggleTrash()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 7.7) {
            if let w = self.trashWin { shot(w, "11_kosz") }
            self.trashWin?.orderOut(nil)
        }
        // po aktualizacji z 1.2: same nowości
        for (k, pg) in [(7.8, 0), (7.85, 1), (7.9, 2), (7.95, 3)] {
            DispatchQueue.main.asyncAfter(deadline: .now() + k) {
                let w = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 560, height: 470), styleMask: [.borderless], backing: .buffered, defer: false)
                w.appearance = NSAppearance(named: .aqua)
                w.contentView = NSHostingView(rootView: WelcomeView(close: {}, startPage: pg, newSince: "1.2"))
                w.orderFront(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { shot(w, "18_nowosci_\(pg)"); w.orderOut(nil) }
            }
        }
        for (k, pg) in [(8.0, 0), (8.4, 1), (8.8, 2), (9.0, 3), (9.2, 4), (9.4, 5), (9.6, 6), (10.0, 7), (10.4, 8), (10.8, 9), (10.9, 10), (10.95, 11), (11.0, 12), (11.05, 13)] {
            DispatchQueue.main.asyncAfter(deadline: .now() + k) {
                let w = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 560, height: 470), styleMask: [.borderless], backing: .buffered, defer: false)
                w.appearance = NSAppearance(named: .aqua)
                w.contentView = NSHostingView(rootView: WelcomeView(close: {}, startPage: pg))
                w.orderFront(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { shot(w, "14_witaj_\(pg)"); w.orderOut(nil) }
            }
        }
        for k in [(11.0, (5, 0.25)), (11.3, (5, 0.5)), (11.6, (5, 0.75)), (11.9, (6, 0.45)), (12.2, (6, 0.8)), (12.3, (8, 0.5)), (12.35, (9, 0.3)), (12.4, (9, 0.78)), (12.5, (11, 0.35)), (12.6, (11, 0.85))].enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + k.element.0) {
                                let (pg, ph) = k.element.1
                FROZEN_PHASE = ph
                let w = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 560, height: 470), styleMask: [.borderless], backing: .buffered, defer: false)
                w.appearance = NSAppearance(named: .aqua)
                w.contentView = NSHostingView(rootView: WelcomeView(close: {}, startPage: pg))
                w.orderFront(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { shot(w, "15_klatka_\(k.offset)"); w.orderOut(nil); FROZEN_PHASE = nil }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 12.5) {
            // karteczka z plikami (zdjęcie i tekst z projektu)
            let id = self.store.add()
            if let i = self.store.notes.firstIndex(where: { $0.id == id }) {
                self.store.notes[i].title = L("Pomysły na weekend")
                self.store.notes[i].tasks = ["Jedna kartka podsumowująca, co każdego dnia trzeba zrobić i dla kogo", "Mini wersja na pulpit"].map { var t = TaskItem(); t.text = $0; return t }
                self.store.notes[i].body = ""
                self.store.notes[i].deadline = Calendar.current.date(bySettingHour: 14, minute: 30, second: 0, of: Date())
                self.store.notes[i].hasTime = true
            }
            let here = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            self.store.attach(id, [URL(fileURLWithPath: "/System/Library/Desktop Pictures/Mac Pink.heic"),
                                   here.appendingPathComponent("README.md")])
            let w = NSWindow(contentRect: NSRect(x: 300, y: 100, width: 400, height: 640), styleMask: [.borderless], backing: .buffered, defer: false)
            w.isOpaque = false; w.backgroundColor = .clear
            w.contentView = NSHostingView(rootView: EditorView(id: id, close: {}).environmentObject(self.store))
            w.orderFront(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { shot(w, "16_pliki"); w.orderOut(nil) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 12.8) {
            // „Na dziś” przesunięta na trzecie miejsce (po zrzucie: z powrotem, to ustawienie użytkownika)
            self.ui.setTodayPos(2); self.ui.spread = true; self.ui.hovered = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                shot(self.stack, "17_na_dzis_przesunieta")
                UserDefaults.standard.removeObject(forKey: "todayPos"); UserDefaults.standard.removeObject(forKey: "todayPosDay")
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 13.6) {
            NSApp.terminate(nil)
        }
    }
}

if let out = ProcessInfo.processInfo.environment["STOSIK_ICON"] {
    // Ikona aplikacji: warstwy pilności z ptaszkiem na ciemnym tle.
    MainActor.assumeIsolated {
    let v = ZStack {
        RoundedRectangle(cornerRadius: 230, style: .continuous).fill(Color(hex: 0xF7F1E7))
        PriorityIcon(level: 3, done: true, classic: true).frame(width: 640, height: 640)
    }.frame(width: 1024, height: 1024).padding(0)
    let r = ImageRenderer(content: v.frame(width: 824, height: 824).frame(width: 1024, height: 1024))
    if let cg = r.cgImage { let rep = NSBitmapImageRep(cgImage: cg); try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out)) }
    }
    exit(0)
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
