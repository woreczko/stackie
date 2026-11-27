import SwiftUI
import ServiceManagement

let CAL_ID = UUID(uuidString: "00000000-0000-0000-0000-0000000CA1E0")!

enum StackLayout {
    static let cardW: CGFloat = 210, cardH: CGFloat = 262
    static let tight: CGFloat = 24
    /// Ile karteczek widać w złożonym stosie (reszta chowa się pod czwartą, wychodzi po najechaniu).
    static let shown = 4
    /// Odstęp po rozłożeniu: tyle, ile zmieści się na ekranie (najwyżej prawie cała karteczka).
    static var wide: CGFloat = 204
    static var lift: CGFloat { max(16, cardW + 12 - wide) }

    /// Ile kart w jednym rzędzie po rozłożeniu (na laptopie ok. 6, na dużym monitorze więcej) i ile rzędów.
    static var perRow = 99
    static var rows = 1
    static let rowStep: CGFloat = 262 + 26

    static func fit(count n: Int, screenWidth: CGFloat) {
        let items = n + 1                                   // + kalendarz
        let sw = ProcessInfo.processInfo.environment["STOSIK_SCREENW"].flatMap { Double($0) }.map { CGFloat($0) } ?? screenWidth
        let avail = sw * 0.95 - padX * 2 - 18
        perRow = max(3, Int((avail - cardW) / 196) + 1)
        let inRow = min(items, perRow)
        wide = inRow > 1 ? min(204, (avail - cardW) / CGFloat(inRow - 1)) : 204
        rows = (items + perRow - 1) / perRow
    }
    /// Lewa krawędź paska: pod środkiem pierwszej karteczki (stoi tam i w złożonym, i w rozłożonym stosie;
    /// rozwinięty pasek rośnie w prawo, żeby ikony nie uciekały spod kursora).
    static let toolX: CGFloat = padX + cardW / 2 - 42

    // Mała karteczka-kalendarz: zawsze za całym stosem.
    static let calW: CGFloat = cardW, calH: CGFloat = cardH
    static func calY(_ n: Int, spread: Bool) -> CGFloat { y(max(n, 1), spread: spread) }
    static func calX(_ n: Int, spread: Bool, hovered: Int?) -> CGFloat {
        guard spread else { return padX + CGFloat(min(n, shown)) * tight }
        return x(max(n, 1), spread: true, hovered: hovered)
    }
    /// Górna krawędź karty (rząd po rozłożeniu).
    static func y(_ i: Int, spread: Bool) -> CGFloat {
        spread ? padTop + CGFloat(i / perRow) * rowStep : padTop
    }
    static let padX: CGFloat = 40, padTop: CGFloat = 66, toolbarH: CGFloat = 24
    /// Pasek: pod stosem albo pod ostatnim rzędem rozłożonych kart.
    static func toolbarY(_ spread: Bool) -> CGFloat { padTop + CGFloat(spread ? rows - 1 : 0) * rowStep + cardH + 9 }
    /// Pod stosem zostaje przezroczyste miejsce na kosz przy przeciąganiu w dół.
    static let trashRoom: CGFloat = 170
    static var height: CGFloat { toolbarY(true) + toolbarH + 18 + trashRoom }
    static let trashArm: CGFloat = 70
    /// Górna krawędź kosza: tuż pod dolną krawędzią karteczki.
    static func trashY(_ i: Int) -> CGFloat { y(i, spread: true) + cardH + 22 }

    static func width(_ n: Int) -> CGFloat { padX * 2 + CGFloat(max(min(n + 1, perRow) - 1, 0)) * wide + lift + calW }
    static func collapsedWidth(_ n: Int) -> CGFloat { calX(n, spread: false, hovered: nil) + calW - padX }

    static func x(_ i: Int, spread: Bool, hovered: Int?) -> CGFloat {
        guard spread else { return padX + CGFloat(min(i, shown - 1)) * tight }
        let col = i % perRow
        var x = padX + CGFloat(col) * wide
        if let h = hovered, h / perRow == i / perRow, col > h % perRow { x += lift }
        return x
    }

    static func angle(_ i: Int, spread: Bool) -> Double {
        // rozłożony: fala; złożony: na przemian lekko w lewo i w prawo
        guard !spread else { return sin(Double(i) * 1.15) * 2.0 }
        return min(i, shown) % 2 == 0 ? -3.2 : 3.6
    }
    /// Złożony: każda kolejna karta wyżej (rogi wystają spod przedniej). Rozłożony: fala.
    static func wave(_ i: Int, spread: Bool) -> CGFloat {
        spread ? CGFloat(sin(Double(i) * 1.15 + 0.9)) * 8 : -CGFloat(min(i, shown)) * 4
    }
}

/// Stan najechania i przeciągania (mysz czytana zegarem, działa też gdy apka nie jest aktywna).
final class UIState: ObservableObject {
    static let shared = UIState()
    @Published var hovered: UUID?
    @Published var spread = false
    @Published var dragID: UUID?
    @Published var dragDX: CGFloat = 0
    @Published var dragDY: CGFloat = 0
    @Published var toolbarHover = false
    /// Która ikonka paska jest pod myszą (0 plus, 1 lupa).
    @Published var toolIcon: Int?
    /// Pasek rozwinięty (po chwili trzymania kursora na nim): widać lupę.
    @Published var toolExpanded = false
    /// Przytrzymany przycisk myszy na pasku: przenosimy stos.
    @Published var toolHold = false
    @Published var showFilter = false
    @Published var showSettings = false
    private var expandWork: DispatchWorkItem?
    private var foldWork: DispatchWorkItem?
    /// Co kilka sekund +1: karteczki z bliskim terminem podskakują.
    @Published var bounceTick = 0
    @Published var filterTag: String?
    @Published var filterClient: String?
    @Published var filterProject: String?
    @Published var query = ""
    var filtering: Bool { filterTag != nil || filterClient != nil || filterProject != nil || !query.trimmingCharacters(in: .whitespaces).isEmpty }
    func visible(_ notes: [Note]) -> [Note] {
        filtering ? notes.filter { $0.matches(tag: filterTag, client: filterClient, project: filterProject, query: query) } : notes
    }
    func setFilter(tag: String? = nil, client: String? = nil, project: String? = nil) {
        filterTag = tag; filterClient = client; filterProject = project; query = ""
    }
    func clearFilter() { setFilter() }
    var filterLabel: String {
        if let c = filterClient { return filterProject.map { c + " · " + $0 } ?? c }
        if let p = filterProject { return p }
        if let t = filterTag { return "#" + t }
        return "„\(query)”"
    }
    var frozen = false
    /// Otwarte menu (np. drzemka na dzwoneczku): stos się nie składa, dopóki menu jest na ekranie.
    var menuOpen = false
    private var collapse: DispatchWorkItem?

    func mouse(at p: CGPoint?, notes: [Note]) {
        guard !frozen, dragID == nil, !menuOpen else { return }
        let ty = StackLayout.toolbarY(spread)
        // przypisanie tylko przy zmianie: każde przypisanie @Published przerysowuje cały stos (60 razy na sekundę)
        let overBar = p.map { $0.y > ty - 6 && $0.y < ty + StackLayout.toolbarH + 8
            && $0.x > StackLayout.toolX - 8 && $0.x < StackLayout.toolX + 200 } ?? false
        if overBar != toolbarHover { toolbarHover = overBar }
        var icon: Int? = nil
        if toolbarHover, let p {
            let k = Int(floor((p.x - StackLayout.toolX - 6) / 24))
            if (0...(toolExpanded ? 3 : 1)).contains(k) && p.y >= ty && p.y <= ty + StackLayout.toolbarH { icon = k }
        }
        if icon != toolIcon { toolIcon = icon }
        updateExpand()
        guard let p else { return scheduleCollapse() }
        // z karteczek na pasek: stos zostaje rozłożony
        if toolbarHover && spread { collapse?.cancel(); collapse = nil; return }
        var spreadNow = spread
        if !spreadNow {
            let r = CGRect(x: StackLayout.padX - 6, y: StackLayout.padTop - 12,
                           width: StackLayout.collapsedWidth(notes.count) + 12, height: StackLayout.cardH + 14)
            if r.contains(p), !notes.isEmpty { spreadNow = true }
        }
        guard spreadNow else { return scheduleCollapse() }
        let h = notes.firstIndex { $0.id == hovered }
        var order = Array(notes.indices)
        if let h { order.removeAll { $0 == h }; order.insert(h, at: 0) }
        let calRect = CGRect(x: StackLayout.calX(notes.count, spread: true, hovered: h), y: StackLayout.calY(notes.count, spread: true) - 14,
                             width: StackLayout.calW, height: StackLayout.calH + 28)
        if hovered == CAL_ID, calRect.contains(p) { collapse?.cancel(); collapse = nil; return }
        for i in order {
            let r = CGRect(x: StackLayout.x(i, spread: true, hovered: h), y: StackLayout.y(i, spread: true) - 14,
                           width: StackLayout.cardW, height: StackLayout.cardH + 28)
            if r.contains(p) {
                collapse?.cancel(); collapse = nil
                if !spread { spread = true }
                if hovered != notes[i].id { hovered = notes[i].id }
                return
            }
        }
        if calRect.contains(p) {
            collapse?.cancel(); collapse = nil
            if !spread { spread = true }
            if hovered != CAL_ID { hovered = CAL_ID }
            return
        }
        // rozłożony stos nie składa się, dopóki kursor jest w jego obszarze (puste miejsca między rzędami, droga do paska)
        if spread {
            let top = StackLayout.padTop - 20
            let bounds = CGRect(x: StackLayout.padX - 14, y: top,
                                width: StackLayout.width(notes.count) - StackLayout.padX * 2 + 28,
                                height: StackLayout.toolbarY(true) + StackLayout.toolbarH + 16 - top)
            if bounds.contains(p) { collapse?.cancel(); collapse = nil; return }
        }
        scheduleCollapse()
    }

    /// Kursor chwilę na pasku: rozwija się; po zjechaniu zwija (chyba że działa filtr albo szukanie).
    private func updateExpand() {
        if toolbarHover || showFilter || showSettings {
            foldWork?.cancel(); foldWork = nil
            guard !toolExpanded, expandWork == nil else { return }
            let w = DispatchWorkItem { [weak self] in
                self?.expandWork = nil
                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) { self?.toolExpanded = true }
            }
            expandWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: w)
        } else {
            expandWork?.cancel(); expandWork = nil
            guard toolExpanded, foldWork == nil else { return }
            let w = DispatchWorkItem { [weak self] in
                self?.foldWork = nil
                withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) { self?.toolExpanded = false }
            }
            foldWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: w)
        }
    }

    private func scheduleCollapse() {
        guard (hovered != nil || spread), collapse == nil else { return }
        let w = DispatchWorkItem { [weak self] in
            self?.hovered = nil; self?.spread = false; self?.collapse = nil
        }
        collapse = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: w)
    }
}

struct StackView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: UIState
    var openEditor: (UUID) -> Void
    var newNote: () -> Void
    var openCalendar: () -> Void

    var body: some View {
        let notes = ui.visible(store.active)
        let hIdx = notes.firstIndex { $0.id == ui.hovered }
        ZStack(alignment: .topLeading) {
            Color.clear
            if notes.isEmpty && ui.filtering {
                VStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 22, weight: .light))
                    Text(L("Nic tu nie pasuje")).font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: StackLayout.cardW, height: StackLayout.cardH)
                .background(RoundedRectangle(cornerRadius: 14).fill(.black.opacity(0.3)))
                .offset(x: StackLayout.padX, y: StackLayout.padTop)
            } else if notes.isEmpty {
                Button(action: newNote) {
                    VStack(spacing: 8) {
                        Image(systemName: "plus").font(.system(size: 26, weight: .light))
                        Text(L("Nowa karteczka")).font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: StackLayout.cardW, height: StackLayout.cardH)
                    .background(RoundedRectangle(cornerRadius: 14).fill(.black.opacity(0.25)))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
                }
                .buttonStyle(.plain)
                .offset(x: StackLayout.padX, y: StackLayout.padTop)
            }
            ForEach(Array(notes.enumerated()), id: \.element.id) { i, n in
                let isHover = ui.hovered == n.id
                let isDrag = ui.dragID == n.id
                let down = isDrag ? max(0, ui.dragDY) : 0
                let armed = down > StackLayout.trashArm
                let tilt = StackLayout.angle(i, spread: ui.spread)
                CardView(note: store.binding(n.id), lifted: isHover || isDrag)
                    .rotationEffect(.degrees(isHover || isDrag ? 0 : tilt))
                    .scaleEffect(isDrag ? 1.05 - 0.4 * min(down / (StackLayout.trashArm + 20), 1) : isHover ? 1.03 : 1, anchor: .bottom)
                    .opacity(isDrag ? 1 - 0.25 * min(down / (StackLayout.trashArm + 20), 1) : 1)
                    .offset(x: StackLayout.x(i, spread: ui.spread, hovered: hIdx) + (isDrag && down < 18 ? ui.dragDX : 0),
                            y: StackLayout.y(i, spread: ui.spread) + (isHover || isDrag ? -12 : StackLayout.wave(i, spread: ui.spread)) + down)
                    .modifier(Hop(level: ui.spread || !n.hops ? 0 : (dueInfo(n)?.level ?? 0), tick: ui.bounceTick, delay: Double(i) * 0.12))
                    .zIndex(isDrag ? 2000 : isHover ? 1000 : Double(notes.count - i))
                    .opacity(ui.spread || i < StackLayout.shown ? 1 : 0)
                    .transaction { if isDrag { $0.animation = .interactiveSpring(response: 0.12, dampingFraction: 0.9) } }
                    .onTapGesture { openEditor(n.id) }
                    .gesture(
                        DragGesture(minimumDistance: 5, coordinateSpace: .global)
                            .onChanged { v in
                                if ui.dragID != n.id { ui.dragID = n.id; ui.hovered = n.id; ui.spread = true }
                                ui.dragDX = v.translation.width
                                ui.dragDY = v.translation.height
                            }
                            .onEnded { v in
                                // w dół do kosza, w bok zmiana kolejności
                                if v.translation.height > StackLayout.trashArm {
                                    NSSound(named: "Pop")?.play()
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                        store.delete(n.id)
                                        ui.dragID = nil; ui.dragDX = 0; ui.dragDY = 0; ui.hovered = nil
                                    }
                                    return
                                }
                                let step = StackLayout.wide
                                let to = v.translation.height > 18 ? i : i + Int((v.translation.width / step).rounded())
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                    store.move(n.id, toVisible: to, in: notes)
                                    ui.dragID = nil; ui.dragDX = 0; ui.dragDY = 0
                                }
                            }
                    )
                    .help(n.title)
            }
            if let did = ui.dragID, let di = notes.firstIndex(where: { $0.id == did }), ui.dragDY > 18 {
                let armed = ui.dragDY > StackLayout.trashArm
                TrashTarget(armed: armed, progress: min(max(ui.dragDY - 18, 0) / (StackLayout.trashArm - 18), 1))
                    .offset(x: StackLayout.x(di, spread: true, hovered: di) + StackLayout.cardW / 2 - 28,
                            y: StackLayout.trashY(di))
                    .id(did)
                    .transition(.opacity)
                    .zIndex(2500)
            }
            let calHover = ui.hovered == CAL_ID
            let calIdx = ui.spread ? max(notes.count, 1) : min(notes.count, StackLayout.shown)
            CalendarCard(month: Date(), lifted: calHover)
                .rotationEffect(.degrees(calHover ? 0 : StackLayout.angle(calIdx, spread: ui.spread)))
                .scaleEffect(calHover ? 1.04 : 1)
                .offset(x: StackLayout.calX(notes.count, spread: ui.spread, hovered: hIdx),
                        y: StackLayout.calY(notes.count, spread: ui.spread) + (calHover ? -12 : StackLayout.wave(calIdx, spread: ui.spread)))
                .zIndex(calHover ? 1000 : -1)
                .onTapGesture { openCalendar() }
                .help(L("Kalendarz i podsumowanie miesiąca"))
            Toolbar(count: notes.count, newNote: newNote)
                .environmentObject(ui).environmentObject(store)
                .offset(x: StackLayout.toolX, y: StackLayout.toolbarY(ui.spread || ui.toolbarHover && ui.spread))
    
                .zIndex(3000)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(ui.dragID == nil ? .spring(response: 0.2, dampingFraction: 0.86) : .interactiveSpring(), value: ui.hovered)
        .animation(.spring(response: 0.2, dampingFraction: 0.86), value: ui.spread)
        .animation(.interactiveSpring(), value: ui.dragDX)
    }
}

struct Toolbar: View {
    var count: Int
    var newNote: () -> Void
    @EnvironmentObject var ui: UIState
    @EnvironmentObject var store: Store

    var body: some View {
        let open = ui.toolExpanded || ui.filtering || ui.showFilter || ui.showSettings
        HStack(spacing: 0) {
            icon("plus", 11, 0).help(L("Nowa karteczka"))
            icon("mic.fill", 10.5, 1).help(L("Podyktuj, co jest do zrobienia"))
            if open {
                icon("magnifyingglass", 10.5, 2)
                    .popover(isPresented: $ui.showFilter, arrowEdge: .bottom) { FilterView().environmentObject(ui).environmentObject(store) }
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
                icon("gearshape", 10.5, 3)
                    .popover(isPresented: $ui.showSettings, arrowEdge: .bottom) { SettingsView() }
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
                if ui.filtering {
                    HStack(spacing: 5) {
                        Text(ui.filterLabel).lineLimit(1)
                        Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                    }
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .padding(.horizontal, 7).frame(height: 16)
                    .background(Capsule().fill(PriorityIcon.yellow))
                    .frame(maxWidth: 170)
                    .transition(.opacity)
                }
            }
            if count > 0 {
                Text("\(count)").font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .frame(minWidth: 24, minHeight: 24)
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(.horizontal, 6)
        .frame(height: StackLayout.toolbarH)
        .modifier(Glass())
        .overlay(ToolbarMouse(expanded: open, filtering: ui.filtering,
                              onPlus: newNote,
                              onMic: { AppDelegate.shared?.startDictation(into: nil) },
                              onSearch: { ui.showFilter.toggle() },
                              onSettings: { ui.showSettings.toggle() },
                              onClear: { ui.clearFilter() },
                              onHold: { h in withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { ui.toolHold = h } }))
        .scaleEffect(ui.toolHold ? 1.08 : 1)
        .shadow(color: .black.opacity(ui.toolHold ? 0.25 : 0), radius: 10, y: 6)
        .animation(.easeOut(duration: 0.12), value: ui.toolIcon)
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: open)
        .help(L("Złap i przeciągnij, żeby przenieść stos"))
    }

    /// Ikonka: przygaszona, po najechaniu jaśniejsza i lekko świeci.
    private func icon(_ name: String, _ size: CGFloat, _ k: Int) -> some View {
        let on = ui.toolIcon == k
        return Image(systemName: name).font(.system(size: size, weight: .semibold))
            .foregroundStyle(.white.opacity(on ? 1 : 0.55))
            .shadow(color: .white.opacity(on ? 0.9 : 0), radius: 3)
            .shadow(color: .white.opacity(on ? 0.5 : 0), radius: 7)
            .frame(width: 24, height: 24)
    }
}

/// Myszka na pasku: klik w plus, lupę albo koło zębate; złapanie i przeciągnięcie przenosi cały stos.
struct ToolbarMouse: NSViewRepresentable {
    var expanded: Bool
    var filtering: Bool
    var onPlus: () -> Void
    var onMic: () -> Void
    var onSearch: () -> Void
    var onSettings: () -> Void
    var onClear: () -> Void
    var onHold: (Bool) -> Void

    final class V: NSView {
        var cfg: ToolbarMouse!
        private var downAt: NSPoint = .zero
        private var origin: NSPoint = .zero
        private var holding = false
        private var moved = false

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with e: NSEvent) {
            downAt = NSEvent.mouseLocation
            origin = window?.frame.origin ?? .zero
            holding = false; moved = false
        }

        override func mouseDragged(with e: NSEvent) {
            let p = NSEvent.mouseLocation
            // każdy ruch po złapaniu przenosi cały stos (bez czekania)
            if !holding {
                guard hypot(p.x - downAt.x, p.y - downAt.y) > 3 else { return }
                holding = true; moved = true
                cfg.onHold(true)
                NSCursor.closedHand.push()
            }
            window?.setFrameOrigin(NSPoint(x: origin.x + p.x - downAt.x, y: origin.y + p.y - downAt.y))
        }

        override func mouseUp(with e: NSEvent) {
            if holding {
                holding = false
                NSCursor.pop()
                cfg.onHold(false)
                return
            }
            guard !moved else { return }
            let x = convert(e.locationInWindow, from: nil).x
            let k = Int(floor((x - 6) / 24))
            if k == 0 { cfg.onPlus() }
            else if k == 1 { cfg.onMic() }
            else if k == 2 && cfg.expanded { cfg.onSearch() }
            else if k == 3 && cfg.expanded { cfg.onSettings() }
            else if k >= 4 && cfg.expanded && cfg.filtering { cfg.onClear() }
        }

        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    }

    func makeNSView(context: Context) -> V { let v = V(); v.cfg = self; return v }
    func updateNSView(_ v: V, context: Context) { v.cfg = self }
}

/// Szukanie po tekście i wybór tagu.
struct FilterView: View {
    @EnvironmentObject var ui: UIState
    @EnvironmentObject var store: Store
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L("Szukaj w karteczkach"), text: $ui.query).textFieldStyle(.plain).focused($focused)
                if !ui.query.isEmpty {
                    Button { ui.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 9).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8).fill(.primary.opacity(0.07)))
            if store.allClients.isEmpty && store.allTags.isEmpty && store.allProjects().isEmpty {
                Text(L("Nie ma jeszcze klientów ani tagów. Dodasz je w karteczce.")).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            section(L("KLIENCI"), store.allClients, on: { ui.filterClient }, dot: { store.clientColor($0) }) { ui.setFilter(client: $0) }
            section(L("PROJEKTY"), store.allProjects(client: ui.filterClient), on: { ui.filterProject }, dot: { store.tagColor($0, kind: "p:") }) {
                let c = ui.filterClient; ui.setFilter(client: c, project: $0)
            }
            section(L("TAGI"), store.allTags, on: { ui.filterTag }, dot: nil) { ui.setFilter(tag: $0) }
            if ui.filtering {
                Button(L("Pokaż wszystkie")) { ui.clearFilter() }.font(.system(size: 12))
            }
        }
        .padding(14)
        .frame(width: 290)
        .onAppear { focused = true }
    }
}

extension FilterView {
    @ViewBuilder
    func section(_ title: String, _ items: [(tag: String, count: Int)], on: @escaping () -> String?,
                 dot: ((String) -> Color)?, pick: @escaping (String?) -> Void) -> some View {
        if !items.isEmpty {
            Text(title).font(.system(size: 10, weight: .bold)).tracking(0.8).foregroundStyle(.secondary).padding(.top, 2)
            FlowLayout(spacing: 6) {
                ForEach(items, id: \.tag) { t in
                    let active = on()?.caseInsensitiveCompare(t.tag) == .orderedSame
                    Button { pick(active ? nil : t.tag) } label: {
                        HStack(spacing: 4) {
                            if let dot { Circle().fill(dot(t.tag)).frame(width: 7, height: 7) }
                            Text(t.tag)
                            Text("\(t.count)").foregroundStyle(active ? Color.ink.opacity(0.6) : .secondary)
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(active ? Color.ink : .primary)
                        .padding(.horizontal, 9).frame(height: 24)
                        .background(Capsule().fill(active ? PriorityIcon.yellow : Color.primary.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Układ zawijający (chipy tagów).
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 300
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let z = s.sizeThatFits(.unspecified)
            if x > 0 && x + z.width > w { x = 0; y += row + spacing; row = 0 }
            x += z.width + spacing; row = max(row, z.height); maxX = max(maxX, x - spacing)
        }
        return CGSize(width: proposal.width ?? maxX, height: subviews.isEmpty ? 0 : y + row)
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = b.minX, y = b.minY, row: CGFloat = 0
        for s in subviews {
            let z = s.sizeThatFits(.unspecified)
            if x > b.minX && x + z.width > b.maxX { x = b.minX; y += row + spacing; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(z))
            x += z.width + spacing; row = max(row, z.height)
        }
    }
}

/// Szkło jak w nowym macOS (liquid glass); na starszym systemie przezroczysty materiał.
struct Glass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .capsule)
                .overlay(GlassRim())
        } else {
            content.background(Capsule().fill(.ultraThinMaterial)).overlay(GlassRim())
        }
    }
}

/// Podskok karteczki z bliskim terminem (dziś, jutro) albo po terminie: dwa skoki, zaległa skacze wyżej.
struct Hop: ViewModifier {
    var level: Int
    var tick: Int
    var delay: Double

    func body(content: Content) -> some View {
        let urgent = level >= 2
        let h: CGFloat = level >= 3 ? 34 : 26
        content.keyframeAnimator(initialValue: HopValue(), trigger: urgent ? tick : -1) { view, v in
            view.scaleEffect(x: v.sx, y: v.sy, anchor: .bottom).offset(y: v.y)
        } keyframes: { _ in
            KeyframeTrack(\.y) {
                LinearKeyframe(0, duration: max(delay, 0.02))
                LinearKeyframe(0, duration: 0.08)                      // przysiad
                CubicKeyframe(-h, duration: 0.2)                       // wyskok
                CubicKeyframe(0, duration: 0.18)                       // lądowanie
                CubicKeyframe(-h * 0.45, duration: 0.15)               // drugi, mniejszy
                SpringKeyframe(0, duration: 0.35, spring: .bouncy)
            }
            KeyframeTrack(\.sy) {
                LinearKeyframe(1, duration: max(delay, 0.02))
                LinearKeyframe(0.94, duration: 0.08)
                CubicKeyframe(1.04, duration: 0.2)
                CubicKeyframe(0.95, duration: 0.18)
                CubicKeyframe(1.02, duration: 0.15)
                SpringKeyframe(1, duration: 0.35)
            }
            KeyframeTrack(\.sx) {
                LinearKeyframe(1, duration: max(delay, 0.02))
                LinearKeyframe(1.04, duration: 0.08)
                CubicKeyframe(0.98, duration: 0.2)
                CubicKeyframe(1.03, duration: 0.18)
                CubicKeyframe(0.99, duration: 0.15)
                SpringKeyframe(1, duration: 0.35)
            }
        }
    }
}

struct HopValue { var y: CGFloat = 0; var sx: CGFloat = 1; var sy: CGFloat = 1 }

/// Jasna krawędź szkła (góra mocniej, dół słabiej), żeby pasek był przestrzenny także, gdy okno nie jest aktywne.
struct GlassRim: View {
    var body: some View {
        ZStack {
            Capsule().strokeBorder(
                LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.08), .white.opacity(0.25)],
                               startPoint: .top, endPoint: .bottom), lineWidth: 1)
            Capsule().fill(LinearGradient(colors: [.white.opacity(0.14), .clear], startPoint: .top, endPoint: .center))
                .padding(1.5)
        }
        .allowsHitTesting(false)
    }
}

/// Szybkie ustawienia z koła zębatego na pasku (te same co w menu w górnym pasku).
struct SettingsView: View {
    @State private var level = AppDelegate.shared?.levelMode ?? 1
    @State private var lang = Lang.setting
    @State private var login = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("USTAWIENIA")).font(.system(size: 10, weight: .bold)).tracking(0.8).foregroundStyle(.secondary)
            row(L("Położenie stosu")) {
                Picker("", selection: $level) {
                    Text(L("Pulpit")).tag(0); Text(L("Okno")).tag(1); Text(L("Na wierzchu")).tag(2)
                }
                .pickerStyle(.segmented).labelsHidden()
                .onChange(of: level) { _, v in AppDelegate.shared?.levelMode = v }
            }
            row(L("Język")) {
                Picker("", selection: $lang) {
                    Text(L("Auto")).tag("auto"); Text("Polski").tag("pl"); Text("English").tag("en")
                }
                .pickerStyle(.segmented).labelsHidden()
                .onChange(of: lang) { _, v in
                    Lang.setting = v
                    DispatchQueue.main.async { AppDelegate.shared?.relocalize() }
                }
            }
            Toggle(L("Otwieraj przy logowaniu"), isOn: $login)
                .toggleStyle(.switch).controlSize(.small)
                .onChange(of: login) { _, v in
                    do { if v { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                    catch { login = SMAppService.mainApp.status == .enabled }
                }
            Divider()
            HStack {
                Button { UIState.shared.showSettings = false; AppDelegate.shared?.toggleTrash() } label: {
                    Label(LF("Kosz (%d)", Store.shared.trash.count), systemImage: "trash")
                }
                Spacer()
                Button { UIState.shared.showSettings = false; AppDelegate.shared?.showWelcome() } label: {
                    Label(L("Witaj i co nowego"), systemImage: "sparkles")
                }
            }
            .font(.system(size: 12))
            HStack {
                Button { UIState.shared.showSettings = false; AppDelegate.shared?.toggleCalendar() } label: {
                    Label(L("Kalendarz i podsumowanie"), systemImage: "calendar")
                }
                Spacer()
                Button(L("Zakończ")) { AppDelegate.shared?.menuQuit() }
            }
            .font(.system(size: 12))
        }
        .padding(14)
        .frame(width: 320)
    }

    private func row<C: View>(_ t: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(t).font(.system(size: 12, weight: .medium))
            c()
        }
    }
}

/// Kosz pod przeciąganą karteczką; czerwienieje, gdy puszczenie wyrzuci karteczkę.
struct TrashTarget: View {
    var armed: Bool
    /// 0 = karteczka daleko (pokrywka otwarta), 1 = nad koszem (zamknięta)
    var progress: CGFloat
    @State private var shown = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().fill(armed ? Color(hex: 0xD93A26) : Color.black.opacity(0.5))
                BinIcon(open: armed ? 0 : 1 - progress)
                    .frame(width: 22, height: 26)
                    .offset(y: 2)
            }
            .frame(width: 56, height: 56)
            .scaleEffect(armed ? 1.15 : 1)
            .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
            Text(armed ? L("Puść, żeby usunąć") : L("Do kosza")).font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Capsule().fill(.black.opacity(0.45)))
                .fixedSize()
        }
        .frame(width: 56)
        .scaleEffect(shown ? 1 : 0.3, anchor: .top)
        .offset(y: shown ? 0 : -24)
        .opacity(shown ? 1 : 0)
        .onAppear { withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) { shown = true } }
        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: armed)
        .animation(.interactiveSpring(response: 0.18), value: progress)
    }
}

/// Kosz z pokrywką na zawiasie (lewa strona); open 1 = otwarta, 0 = zamknięta.
struct BinIcon: View {
    var open: CGFloat

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack(alignment: .topLeading) {
                // korpus: zwężający się ku dołowi, z trzema żłobieniami
                Path { p in
                    p.move(to: CGPoint(x: w * 0.12, y: h * 0.30))
                    p.addLine(to: CGPoint(x: w * 0.88, y: h * 0.30))
                    p.addLine(to: CGPoint(x: w * 0.80, y: h * 0.98))
                    p.addLine(to: CGPoint(x: w * 0.20, y: h * 0.98))
                    p.closeSubpath()
                }
                .stroke(.white, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                ForEach(0..<3) { k in
                    let x = w * (0.36 + 0.14 * CGFloat(k))
                    Path { p in
                        p.move(to: CGPoint(x: x, y: h * 0.44)); p.addLine(to: CGPoint(x: x, y: h * 0.84))
                    }
                    .stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                }
                // pokrywka z uchwytem, obraca się na lewym zawiasie
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 1.5).fill(.white).frame(width: w * 1.04, height: 2.4)
                    RoundedRectangle(cornerRadius: 1.5).stroke(.white, lineWidth: 1.8)
                        .frame(width: w * 0.36, height: h * 0.1).offset(y: -2.4)
                }
                .frame(width: w * 1.04, height: h * 0.2, alignment: .bottom)
                .offset(x: -w * 0.02, y: h * 0.08)
                .rotationEffect(.degrees(-38 * Double(open)), anchor: UnitPoint(x: 0.02, y: 1.0))
                .offset(y: -h * 0.06 * open)
            }
        }
    }
}

/// Kosz: usunięte karteczki przez 30 dni.
struct TrashView: View {
    @EnvironmentObject var store: Store
    var close: () -> Void
    @State private var askEmpty = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("Kosz")).font(.system(size: 24, weight: .semibold)).tracking(-0.5)
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.ink.opacity(0.6))
                        .frame(width: 22, height: 22).background(Circle().fill(Color.ink.opacity(0.07)))
                }
                .buttonStyle(.plain).keyboardShortcut(.cancelAction)
            }
            Text(LF("Karteczki znikają same po %d dniach.", Store.TRASH_DAYS)).font(.system(size: 11.5)).foregroundStyle(Color.ink.opacity(0.5))
                .padding(.top, 2).padding(.bottom, 14)
            if store.trash.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "trash").font(.system(size: 28, weight: .light))
                    Text(L("Kosz jest pusty")).font(.system(size: 13))
                }
                .foregroundStyle(Color.ink.opacity(0.35))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(store.trash) { n in
                            HStack(spacing: 10) {
                                RoundedRectangle(cornerRadius: 3).fill(palette(n.color).bg)
                                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.black.opacity(0.1)))
                                    .frame(width: 6, height: 30)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(n.title.isEmpty ? L("Bez tytułu") : n.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                    Text(LF("zostało %@", daysLabel(store.daysLeft(n)))
                                         + (n.client.isEmpty ? "" : " · " + n.client))
                                        .font(.system(size: 10.5)).foregroundStyle(Color.ink.opacity(0.5)).lineLimit(1)
                                }
                                Spacer(minLength: 4)
                                Button(L("Przywróć")) { withAnimation { store.restore(n.id) } }
                                    .buttonStyle(.plain).font(.system(size: 11.5, weight: .semibold))
                                    .padding(.horizontal, 9).frame(height: 24)
                                    .background(Capsule().fill(Color.ink.opacity(0.08)))
                                Button { withAnimation { store.deleteForever(n.id) } } label: {
                                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.ink.opacity(0.45))
                                        .frame(width: 22, height: 22).contentShape(Rectangle())
                                }
                                .buttonStyle(.plain).help(L("Usuń na zawsze"))
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 9).fill(Color.ink.opacity(0.04)))
                        }
                    }
                }
                .scrollIndicators(.never)
                HStack {
                    Spacer()
                    Button(L("Opróżnij kosz")) { askEmpty = true }
                        .buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(hex: 0xC4281B))
                }
                .padding(.top, 10)
            }
        }
        .foregroundStyle(Color.ink)
        .padding(20)
        .frame(width: 380, height: 460)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(CAL_PAPER))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.black.opacity(0.1)))
        .confirmationDialog(L("Usunąć wszystko z kosza na zawsze?"), isPresented: $askEmpty) {
            Button(L("Opróżnij kosz"), role: .destructive) { withAnimation { store.emptyTrash() } }
            Button(L("Anuluj"), role: .cancel) {}
        }
    }
}
