import SwiftUI
import ImageIO

/// Otwarta karteczka: tytuł, kolor, pilność, termin, zadania, notatka.
struct EditorView: View {
    @EnvironmentObject var store: Store
    let id: UUID
    var close: () -> Void
    @FocusState private var focus: UUID?
    @FocusState private var titleFocus: Bool
    @State private var askDelete = false
    @State private var hoverTask: UUID?
    @State private var dragTask: UUID?
    @State private var dragY: CGFloat = 0
    @State private var dragShift: CGFloat = 0   // o ile punktów wiersz w ręce przeskoczył przez zamiany
    @State private var rowH: [UUID: CGFloat] = [:]   // wysokości wierszy (długie zadania zawijają się w kilka linii)
    @State private var liftTask: UUID?
    @State private var dropping = false
    @State private var smartBusy = false
    @State private var lastSubmit = Date.distantPast   // Enter: nowe zadanie tylko raz (onSubmit albo nowa linia)
    @State private var smartShown = false
    @State private var smart: SmartProposal?
    @State private var smartPick: Set<Int> = []
    @State private var smartError: String?
    private let rowGap: CGFloat = 8     // odstęp między wierszami zadań

    var body: some View {
        let note = store.binding(id)
        let pal = palette(note.wrappedValue.color)
        let fg: Color = pal.dark ? .white : .ink
        VStack(alignment: .leading, spacing: 0) {
            // Pilność i zamknięcie
            HStack(spacing: 8) {
                ForEach(0..<4) { lvl in
                    Button { note.wrappedValue.priority = lvl } label: {
                        VStack(spacing: 3) {
                            if lvl == 0 {
                                Image(systemName: "minus").font(.system(size: 11, weight: .bold))
                                    .frame(width: 22, height: 22)
                                    .background(RoundedRectangle(cornerRadius: 7).strokeBorder(fg.opacity(0.35), lineWidth: 1.2))
                            } else {
                                PriorityIcon(level: lvl, faint: fg).frame(width: 22, height: 22)
                            }
                            Text([L("brak"), L("niska"), L("średnia"), L("pilne")][lvl]).font(.system(size: 9, weight: .semibold))
                        }
                        .padding(.horizontal, 5).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 8).fill(fg.opacity(note.wrappedValue.priority == lvl ? 0.14 : 0)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                DateBadge(note: note.wrappedValue, fg: fg)
            }
            .foregroundStyle(fg)

            ZStack(alignment: .topLeading) {
                if note.wrappedValue.title.isEmpty {
                    Text(L("Tytuł")).font(.system(size: 24, weight: .semibold)).tracking(-0.6)
                        .foregroundStyle(fg.opacity(0.3)).allowsHitTesting(false)
                }
                TextField("", text: note.title, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 24, weight: .semibold))
                    .tracking(-0.6)
                    .foregroundStyle(fg)
                    .focused($titleFocus)
                    .lineLimit(1...3)
            }
            .padding(.top, 10)

            // Kolory
            HStack(spacing: 7) {
                ForEach(PALETTE.indices, id: \.self) { i in
                    Button { note.wrappedValue.color = i } label: {
                        Circle().fill(PALETTE[i].bg)
                            .overlay(Circle().strokeBorder(.black.opacity(0.18), lineWidth: 1))
                            .overlay(Circle().strokeBorder(fg.opacity(0.85), lineWidth: note.wrappedValue.color == i ? 1 : 0).padding(-2.5))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain).help(L(PALETTE[i].name))
                }
            }
            .padding(.top, 12).padding(.leading, 3)

            VStack(alignment: .leading, spacing: 7) {
                NameField(label: L("Klient"), text: note.client, hint: L("np. Kawiarnia Róża"), fg: fg,
                          options: store.allClients.map(\.tag), dot: { store.clientColor($0) },
                          pickColor: { name, i in store.setColor(name, kind: "c:", index: i) })
                NameField(label: L("Projekt"), text: note.project, hint: L("np. Logo, Sklep online"), fg: fg,
                          options: store.allProjects(client: note.wrappedValue.client).map(\.tag), dot: { store.tagColor($0, kind: "p:") },
                          pickColor: { name, i in store.setColor(name, kind: "p:", index: i) })
                HStack(alignment: .top, spacing: 0) {
                    FieldLabel(text: L("Tagi"), fg: fg)
                    TagEditor(tags: note.tags, fg: fg, dark: pal.dark, bg: pal.bg)
                }
            }
            .padding(.top, 12)

            Divider().overlay(fg.opacity(0.15)).padding(.vertical, 12)

            DeadlineRow(note: note, fg: fg)

            Divider().overlay(fg.opacity(0.15)).padding(.vertical, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(L("Zadania")).font(.system(size: 11, weight: .bold)).tracking(0.8).textCase(.uppercase)
                            .foregroundStyle(fg.opacity(0.6))
                        Spacer()
                        if !note.wrappedValue.tasks.isEmpty {
                            Text("\(note.wrappedValue.doneCount)/\(note.wrappedValue.tasks.count)")
                                .font(.system(size: 11, weight: .semibold).monospacedDigit()).foregroundStyle(fg.opacity(0.6))
                        }
                    }
                    ForEach(note.tasks) { $t in
                        let dragging = dragTask == t.id
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(fg.opacity(dragging ? 0.9 : hoverTask == t.id ? 0.6 : 0.18))
                                .frame(width: 22, height: 26)
                                .contentShape(Rectangle())
                                .onHover { h in (h ? NSCursor.openHand : NSCursor.arrow).set() }
                                .gesture(reorder(t.id))
                                .help(L("Przeciągnij, żeby zmienić kolejność"))
                            Button { t.done.toggle() } label: { CheckCircle(done: t.done, color: fg, size: 18) }
                                .buttonStyle(.plain).padding(.top, 4)
                            // w edytorze całe zadanie, zawinięte; na karteczce zostaje jedna linia
                            TextField("", text: $t.text, axis: .vertical)
                                .lineLimit(1...8)
                                .overlay(alignment: .topLeading) {
                                    if t.text.isEmpty { Text(L("Zadanie")).font(.system(size: 14)).foregroundStyle(fg.opacity(0.3)).allowsHitTesting(false) }
                                }
                                .textFieldStyle(.plain)
                                .font(.system(size: 14))
                                .strikethrough(t.done, color: fg.opacity(0.5))
                                .foregroundStyle(fg.opacity(t.done ? 0.5 : 1))
                                .padding(.top, 4)
                                .focused($focus, equals: t.id)
                                .onSubmit { lastSubmit = Date(); insertTask(after: t.id) }
                                .onChange(of: t.text) { _, v in
                                    // Enter (albo wklejony tekst z nową linią) robi nowe zadanie, nie drugi wiersz
                                    guard v.contains("\n") else { return }
                                    let parts = v.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                                    t.text = parts[0]
                                    var after = t.id
                                    for p in parts.dropFirst() where !p.trimmingCharacters(in: .whitespaces).isEmpty {
                                        after = insertTask(after: after, text: p)
                                    }
                                    if parts.dropFirst().allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }),
                                       Date().timeIntervalSince(lastSubmit) > 0.3 {
                                        lastSubmit = Date()
                                        insertTask(after: t.id)
                                    }
                                }
                            Button { removeTask(t.id) } label: {
                                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(fg.opacity(0.5))
                                    .frame(width: 18, height: 18).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).padding(.top, 4)
                            .opacity(hoverTask == t.id ? 1 : 0)
                        }
                        .frame(minHeight: 26)
                        .background(GeometryReader { g in
                            Color.clear.onAppear { rowH[t.id] = g.size.height }
                                .onChange(of: g.size.height) { _, h in rowH[t.id] = h }
                        })
                        .padding(.horizontal, 6).padding(.leading, -10)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(dragging ? palette(note.wrappedValue.color).bg : .clear)
                                .brightness(dragging ? 0.03 : 0)
                                .shadow(color: .black.opacity(liftTask == t.id ? 0.22 : 0), radius: 10, y: 6)
                        )
                        .scaleEffect(liftTask == t.id ? 1.04 : 1)
                        .offset(y: dragging ? dragY - dragShift - (liftTask == t.id ? 3 : 0) : 0)
                        .zIndex(dragging || liftTask == t.id ? 10 : 0)
                        // wiersz w ręce idzie za myszą bez animacji, reszta rozstępuje się sprężyście
                        .transaction { if dragging && !$0[LiftKey.self] { $0.animation = nil } }
                        .onHover { h in hoverTask = h ? t.id : (hoverTask == t.id ? nil : hoverTask) }
                    }
                    HStack(spacing: 16) {
                        Button { insertTask(after: nil) } label: {
                            HStack(spacing: 9) {
                                Image(systemName: "plus").font(.system(size: 10, weight: .bold)).frame(width: 18, height: 18)
                                Text(L("Dodaj zadanie")).font(.system(size: 13, weight: .medium))
                            }
                            .foregroundStyle(fg.opacity(0.6)).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Button { AppDelegate.shared?.startDictation(into: id) } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "mic.fill").font(.system(size: 10, weight: .bold))
                                Text(L("Dyktuj")).font(.system(size: 13, weight: .medium))
                            }
                            .foregroundStyle(fg.opacity(0.6)).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).help(L("Mów, co jest do zrobienia. Każde zdanie to osobne zadanie."))
                    }

                    HStack {
                        Text(L("Notatka")).font(.system(size: 11, weight: .bold)).tracking(0.8).textCase(.uppercase)
                            .foregroundStyle(fg.opacity(0.6))
                        Spacer()
                        if !note.wrappedValue.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button { runSmart(note.wrappedValue.body) } label: {
                                HStack(spacing: 5) {
                                    if smartBusy { ProgressView().controlSize(.mini) }
                                    else { Image(systemName: "sparkles").font(.system(size: 10, weight: .bold)) }
                                    Text(L("Zrób zadania")).font(.system(size: 12, weight: .medium))
                                }
                                .foregroundStyle(fg.opacity(0.6)).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).disabled(smartBusy)
                            .help(ClaudeKey.isSet ? L("Claude zamieni notatkę na zadania. Najpierw zobaczysz propozycję.")
                                                  : L("Podzieli notatkę na zadania po czasownikach. Z kluczem Claude (ustawienia) zrozumie też kontekst."))
                            .popover(isPresented: $smartShown, arrowEdge: .bottom) { smartView(note) }
                            .padding(.trailing, 10)
                        }
                        Button { pickFiles(id) } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "paperclip").font(.system(size: 10, weight: .bold))
                                Text(L("Dołącz plik")).font(.system(size: 12, weight: .medium))
                            }
                            .foregroundStyle(fg.opacity(0.6)).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).help(L("Albo przeciągnij plik na karteczkę"))
                    }
                    .padding(.top, 14)
                    ZStack(alignment: .topLeading) {
                        if note.wrappedValue.body.isEmpty {
                            Text(L("Pisz tutaj. Możesz też upuścić plik: PDF, zdjęcie albo inny."))
                                .font(.system(size: 13.5)).foregroundStyle(fg.opacity(0.35))
                                .padding(.top, 0).allowsHitTesting(false)
                        }
                    TextEditor(text: note.body)
                        .font(.system(size: 13.5))
                        .foregroundStyle(fg)
                        .scrollContentBackground(.hidden)
                        .scrollDisabled(true)
                        .frame(minHeight: 70)
                        .padding(.horizontal, -5)
                    }
                    FilesSection(id: id, fg: fg)
                }
                .padding(.trailing, 6)
            }
            .scrollIndicators(.never)

            HStack {
                Button { close(); store.delete(id) } label: {
                    Label(L("Usuń"), systemImage: "trash").font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain).foregroundStyle(fg.opacity(0.6))
                Spacer()
                Button {
                    store.setArchived(id, !note.wrappedValue.archived); close()
                } label: {
                    Label(note.wrappedValue.archived ? L("Przywróć do stosu") : L("Zrobione, do archiwum"),
                          systemImage: note.wrappedValue.archived ? "arrow.uturn.backward" : "checkmark").font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(fg.opacity(0.1)))
                        .contentShape(Capsule())
                        .foregroundStyle(fg)
                }
                .buttonStyle(.plain)
                Button(action: close) {
                    Text("OK").font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 18).padding(.vertical, 7)
                        .background(Capsule().fill(fg))
                        .foregroundStyle(pal.dark ? Color.ink : .white)
                }
                .buttonStyle(.plain).keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.top, 10)
        }
        .padding(EdgeInsets(top: 18, leading: 22, bottom: 18, trailing: 22))
        .frame(width: 400, height: 640, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(pal.bg))
        .overlay {
            if dropping {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(fg.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(pal.bg.opacity(0.85)))
                    .overlay(VStack(spacing: 8) {
                        Image(systemName: "paperclip").font(.system(size: 26, weight: .semibold))
                        Text(L("Upuść, żeby dołączyć")).font(.system(size: 14, weight: .semibold))
                    }.foregroundStyle(fg.opacity(0.75)))
                    .padding(8).allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropping) { items in
            for it in items {
                _ = it.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async { store.attach(id, [url]) }
                }
            }
            return true
        }
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.black.opacity(0.1)))
        .overlay(alignment: .topTrailing) {
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 7, weight: .bold)).foregroundStyle(fg.opacity(0.6))
                    .frame(width: 15, height: 15).background(Circle().fill(fg.opacity(0.1)))
                    .padding(4).contentShape(Rectangle())
            }
            .buttonStyle(.plain).keyboardShortcut(.cancelAction).padding(2)
        }
        .tint(fg)
        .environment(\.colorScheme, pal.dark ? .dark : .light)
        .confirmationDialog(L("Usunąć tę karteczkę na zawsze?"), isPresented: $askDelete) {
            Button(L("Usuń"), role: .destructive) { close(); store.delete(id) }
            Button(L("Anuluj"), role: .cancel) {}
        }
        .onAppear {
            if store.binding(id).wrappedValue.title.isEmpty { titleFocus = true }
        }
    }

    /// Łapiesz zadanie za uchwyt i przesuwasz w górę albo w dół; reszta rozstępuje się na bieżąco.
    private func reorder(_ tid: UUID) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { v in
                let note = store.binding(id)
                if dragTask != tid {
                    dragTask = tid; dragShift = 0
                    DispatchQueue.main.async {
                        var tr = Transaction(animation: .spring(response: 0.2, dampingFraction: 0.7)); tr[LiftKey.self] = true
                        withTransaction(tr) { liftTask = tid }
                    }
                }
                dragY = v.translation.height
                guard let i = note.wrappedValue.tasks.firstIndex(where: { $0.id == tid }) else { return }
                let off = dragY - dragShift
                let tasks = note.wrappedValue.tasks
                // sąsiad może mieć kilka linii, więc przeskok to jego wysokość, nie stały krok
                func step(_ j: Int) -> CGFloat { (rowH[tasks[j].id] ?? 26) + rowGap }
                withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                    if i < tasks.count - 1, off > step(i + 1) / 2 {
                        let s = step(i + 1)
                        note.wrappedValue.tasks.swapAt(i, i + 1); dragShift += s
                    } else if i > 0, off < -step(i - 1) / 2 {
                        let s = step(i - 1)
                        note.wrappedValue.tasks.swapAt(i, i - 1); dragShift -= s
                    }
                }
            }
            .onEnded { _ in
                // puszczenie: wiersz „wskakuje” na swoje miejsce jak magnes
                withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) { dragTask = nil; dragY = 0; dragShift = 0; liftTask = nil }
            }
    }

    // MARK: zadania z notatki

    private func runSmart(_ text: String) {
        smartBusy = true; smartError = nil
        Smart.propose(text) { r in
            smartBusy = false
            switch r {
            case .success(let p): smart = p; smartPick = Set(p.result.tasks.indices)
            case .failure(let e): smart = nil; smartError = e.localizedDescription
            }
            smartShown = true
        }
    }

    /// Propozycja: zadania do odhaczenia, klient, projekt i termin; notatka zostaje bez zmian.
    @ViewBuilder private func smartView(_ note: Binding<Note>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let err = smartError {
                Text(err).font(.system(size: 12.5)).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button(L("Podziel bez AI")) {
                        let r = parseDictation(note.wrappedValue.body)
                        smart = SmartProposal(result: r, viaAI: false); smartPick = Set(r.tasks.indices); smartError = nil
                    }
                }
            } else if let p = smart {
                HStack(spacing: 5) {
                    Image(systemName: p.viaAI ? "sparkles" : "text.badge.checkmark").font(.system(size: 10, weight: .bold))
                    Text(p.viaAI ? L("Propozycja od Claude") : L("Podział po czasownikach")).font(.system(size: 10.5, weight: .bold))
                        .tracking(0.6).textCase(.uppercase)
                }
                .foregroundStyle(.secondary)
                let meta = [p.result.client, p.result.project].filter { !$0.isEmpty }.joined(separator: " · ")
                if !meta.isEmpty || p.result.deadline != nil || !p.result.tags.isEmpty {
                    HStack(spacing: 6) {
                        if !meta.isEmpty { Text(meta.uppercased()).font(.system(size: 10, weight: .bold)).tracking(0.6) }
                        if let d = p.result.deadline {
                            Label(dayLabel(d, time: p.result.hasTime), systemImage: "calendar").font(.system(size: 11, weight: .medium))
                        }
                        ForEach(p.result.tags, id: \.self) { t in Text("#" + t).font(.system(size: 11, weight: .medium)) }
                    }
                    .foregroundStyle(.secondary)
                }
                if p.result.tasks.isEmpty {
                    Text(L("Nie znalazłem tu zadań.")).font(.system(size: 12.5)).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(p.result.tasks.enumerated()), id: \.offset) { i, t in
                        Button {
                            if smartPick.contains(i) { smartPick.remove(i) } else { smartPick.insert(i) }
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: smartPick.contains(i) ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 13)).foregroundStyle(smartPick.contains(i) ? Color.accentColor : .secondary)
                                Text(t).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    if !p.viaAI && !ClaudeKey.isSet {
                        Text(L("Z kluczem Claude zrozumie też kontekst.")).font(.system(size: 10.5)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(L("Anuluj")) { smartShown = false }
                    Button(LF("Dodaj (%d)", smartPick.count)) { applySmart(p, to: note); smartShown = false }
                        .keyboardShortcut(.defaultAction).disabled(smartPick.isEmpty && p.result.client.isEmpty)
                }
            }
        }
        .padding(14)
        .frame(width: 340)
    }

    private func dayLabel(_ d: Date, time: Bool) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: Lang.current == "pl" ? "pl_PL" : "en_US")
        f.setLocalizedDateFormatFromTemplate("dMMM")
        return f.string(from: d) + (time ? " " + timeString(d) : "")
    }

    /// Wybrane zadania na koniec listy; klient, projekt, tagi, termin i tytuł tylko tam, gdzie pole jest puste.
    private func applySmart(_ p: SmartProposal, to note: Binding<Note>) {
        var n = note.wrappedValue
        let r = p.result
        n.tasks.removeAll { $0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        n.tasks += r.tasks.indices.filter { smartPick.contains($0) }.map { TaskItem(text: r.tasks[$0]) }
        if n.title.isEmpty, !p.title.isEmpty { n.title = p.title }
        if !r.client.isEmpty && n.client.isEmpty { n.client = r.client }
        if !r.project.isEmpty && n.project.isEmpty { n.project = r.project }
        for t in r.tags where !n.tags.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) { n.tags.append(t) }
        if let d = r.deadline, n.deadline == nil { n.deadline = d; n.hasTime = r.hasTime }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { note.wrappedValue = n }
        store.ensureTagColors()
    }

    @discardableResult
    private func insertTask(after tid: UUID?, text: String = "") -> UUID {
        let note = store.binding(id)
        var t = TaskItem(); t.text = text
        if let tid, let i = note.wrappedValue.tasks.firstIndex(where: { $0.id == tid }) {
            note.wrappedValue.tasks.insert(t, at: i + 1)
        } else {
            note.wrappedValue.tasks.append(t)
        }
        DispatchQueue.main.async { focus = t.id }
        return t.id
    }

    private func removeTask(_ tid: UUID) {
        store.binding(id).wrappedValue.tasks.removeAll { $0.id == tid }
    }
}

struct DeadlineRow: View {
    @Binding var note: Note
    var fg: Color

    var body: some View {
        let has = Binding<Bool>(
            get: { note.deadline != nil },
            set: { on in
                note.deadline = on ? Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) : nil
                if !on { note.hasTime = false }
            })
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Toggle(isOn: has) { Text(L("Termin")).font(.system(size: 13, weight: .semibold)) }
                    .toggleStyle(FlatSwitch(fg: fg))
                Spacer()
                if note.deadline != nil {
                    Toggle(isOn: Binding(get: { note.hasTime }, set: { on in
                        note.hasTime = on
                        let cal = Calendar.current
                        if on, let d = note.deadline, cal.component(.hour, from: d) == 0, cal.component(.minute, from: d) == 0 {
                            note.deadline = cal.date(bySettingHour: 9, minute: 0, second: 0, of: d)
                        }
                    })) { Text(L("godzina")).font(.system(size: 12)) }
                        .toggleStyle(FlatCheck(fg: fg))
                }
            }
            if note.deadline != nil {
                HStack(spacing: 6) {
                    let d = Binding(get: { note.deadline ?? Date() }, set: { note.deadline = $0 })
                    DatePill(date: d, fg: fg)
                    if note.hasTime { DatePill(date: d, time: true, fg: fg) }
                    Spacer()
                    quick(L("Dziś"), 0); quick(L("Jutro"), 1); quick(L("+7 dni"), 7)
                }
                AlertsRow(note: $note, fg: fg)
            }
        }
        .foregroundStyle(fg)
    }

    private func quick(_ t: String, _ days: Int) -> some View {
        Button {
            let cal = Calendar.current
            var d = cal.date(byAdding: .day, value: days, to: cal.startOfDay(for: Date()))!
            if note.hasTime, let old = note.deadline {
                let c = cal.dateComponents([.hour, .minute], from: old)
                d = cal.date(bySettingHour: c.hour ?? 9, minute: c.minute ?? 0, second: 0, of: d) ?? d
            }
            note.deadline = d
        } label: {
            Text(t).font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(fg.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }
}

/// Tagi w otwartej karteczce: dopisz i Enter; podpowiedzi z innych karteczek.
struct TagEditor: View {
    @Binding var tags: [String]
    var fg: Color
    var dark: Bool
    var bg: Color
    @EnvironmentObject var store: Store
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        let q = cleanTag(draft)
        let hints = store.allTags.map(\.tag).filter { t in
            !tags.contains { $0.caseInsensitiveCompare(t) == .orderedSame } &&
            (q.isEmpty || t.range(of: q, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil)
        }.prefix(6)
        VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: 5) {
                ForEach(tags, id: \.self) { t in
                    Button { tags.removeAll { $0 == t } } label: { TagPill(text: t, fg: fg, dark: dark, removable: true, bg: bg) }
                        .buttonStyle(.plain).help(L("Usuń tag"))
                }
                HStack(spacing: 3) {
                    Text("#").font(.system(size: 11, weight: .semibold)).foregroundStyle(fg.opacity(0.45))
                    TextField("", text: $draft)
                        .overlay(alignment: .leading) {
                            if draft.isEmpty {
                                Text(tags.isEmpty ? L("np. pilne, faktura") : L("tag")).font(.system(size: 11.5))
                                    .foregroundStyle(fg.opacity(0.35)).allowsHitTesting(false)
                            }
                        }
                        .textFieldStyle(.plain)
                        .font(.system(size: 11.5))
                        .foregroundStyle(fg)
                        .focused($focused)
                        .onSubmit { add(draft) }
                        .frame(width: tags.isEmpty ? 130 : 70)
                }
                .padding(.horizontal, 8).frame(height: 20)
                .background(Capsule().strokeBorder(fg.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
            }
            if (focused || !draft.isEmpty) && !hints.isEmpty {
                HStack(spacing: 5) {
                    ForEach(Array(hints), id: \.self) { t in
                        Button { add(t) } label: {
                            Text("+ \(t)").font(.system(size: 10.5, weight: .medium)).foregroundStyle(fg.opacity(0.7))
                                .padding(.horizontal, 7).frame(height: 18)
                                .background(Capsule().fill(fg.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func add(_ raw: String) {
        for part in raw.split(separator: ",") {
            let t = cleanTag(String(part))
            guard !t.isEmpty, !tags.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) else { continue }
            let existing = store.allTags.map(\.tag).first { $0.caseInsensitiveCompare(t) == .orderedSame }
            tags.append(existing ?? t)
        }
        draft = ""
        focused = true
        store.ensureTagColors()
    }
}

/// Znacznik animacji „podniesienia” wiersza (przepuszczana, gdy inne animacje wiersza w ręce są wyłączone).
struct LiftKey: TransactionKey { static let defaultValue = false }

/// Płaski przełącznik w odcieniach szarości (bez cieni i systemowego połysku).
struct FlatSwitch: ToggleStyle {
    var fg: Color
    func makeBody(configuration c: Configuration) -> some View {
        HStack(spacing: 8) {
            c.label
            ZStack(alignment: c.isOn ? .trailing : .leading) {
                Capsule().fill(fg.opacity(c.isOn ? 0.7 : 0.14))
                Circle().fill(c.isOn ? Color.white.opacity(0.95) : fg.opacity(0.45)).padding(3)
            }
            .frame(width: 30, height: 17)
            .animation(.spring(response: 0.2, dampingFraction: 0.85), value: c.isOn)
        }
        .contentShape(Rectangle())
        .onTapGesture { c.isOn.toggle() }
    }
}

struct FlatCheck: ToggleStyle {
    var fg: Color
    func makeBody(configuration c: Configuration) -> some View {
        HStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 4).fill(fg.opacity(c.isOn ? 0.7 : 0.12))
                if c.isOn { Image(systemName: "checkmark").font(.system(size: 8, weight: .heavy)).foregroundStyle(.white) }
            }
            .frame(width: 14, height: 14)
            c.label
        }
        .contentShape(Rectangle())
        .onTapGesture { c.isOn.toggle() }
    }
}

struct FieldLabel: View {
    var text: String
    var fg: Color
    var body: some View {
        Text(text.uppercased()).font(.system(size: 9.5, weight: .bold)).tracking(0.7)
            .foregroundStyle(fg.opacity(0.5)).frame(width: 68, height: 20, alignment: .leading)
    }
}

/// Jedno pole z podpowiedziami (klient albo projekt).
struct NameField: View {
    var label: String
    @Binding var text: String
    var hint: String
    var fg: Color
    var options: [String]
    var dot: (String) -> Color
    var pickColor: ((String, Int) -> Void)? = nil
    @FocusState private var focused: Bool
    @State private var showColors = false

    var body: some View {
        let q = text.trimmingCharacters(in: .whitespaces)
        let hints = options.filter { o in
            o.caseInsensitiveCompare(q) != .orderedSame &&
            (q.isEmpty || o.range(of: q, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil)
        }.prefix(5)
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 0) {
                FieldLabel(text: label, fg: fg)
                HStack(spacing: 6) {
                    if !q.isEmpty {
                        Button { showColors.toggle() } label: {
                            Circle().fill(dot(q)).overlay(Circle().strokeBorder(fg.opacity(0.3), lineWidth: 0.5))
                                .frame(width: 11, height: 11).contentShape(Circle().inset(by: -4))
                        }
                        .buttonStyle(.plain)
                        .help(L("Zmień kolor"))
                        .popover(isPresented: $showColors, arrowEdge: .bottom) {
                            HStack(spacing: 7) {
                                ForEach(0..<PALETTE.count, id: \.self) { i in
                                    Button { pickColor?(q, i); showColors = false } label: {
                                        Circle().fill(PALETTE[i].bg)
                                            .overlay(Circle().strokeBorder(.black.opacity(0.18), lineWidth: 1))
                                            .frame(width: 18, height: 18)
                                    }
                                    .buttonStyle(.plain).help(L(PALETTE[i].name))
                                }
                            }
                            .padding(10)
                        }
                    }
                    TextField("", text: $text)
                        .overlay(alignment: .leading) {
                            if text.isEmpty { Text(hint).font(.system(size: 13)).foregroundStyle(fg.opacity(0.35)).allowsHitTesting(false) }
                        }
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(fg)
                        .focused($focused)
                        .onSubmit { text = q }
                }
                .padding(.horizontal, 8).frame(height: 22)
                .background(RoundedRectangle(cornerRadius: 6).fill(fg.opacity(focused ? 0.09 : 0.05)))
            }
            if focused && !hints.isEmpty {
                HStack(spacing: 5) {
                    ForEach(Array(hints), id: \.self) { o in
                        Button { text = o; focused = false } label: {
                            HStack(spacing: 4) {
                                Circle().fill(dot(o)).frame(width: 6, height: 6)
                                Text(o).lineLimit(1)
                            }
                            .font(.system(size: 10.5, weight: .medium)).foregroundStyle(fg.opacity(0.75))
                            .padding(.horizontal, 7).frame(height: 18)
                            .background(Capsule().fill(fg.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.leading, 68)
            }
        }
    }
}


/// Przypomnienia w sekcji „Termin”: pigułki z ×, menu z gotowymi odstępami i własna data.
struct AlertsRow: View {
    @Binding var note: Note
    var fg: Color
    @State private var custom = false
    @State private var when = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            FlowLayout(spacing: 6) {
                Image(systemName: note.alerts.isEmpty ? "bell" : "bell.fill")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(fg.opacity(0.6))
                    .frame(height: 22)
                ForEach(note.alerts.sorted(by: >), id: \.self) { m in
                    HStack(spacing: 5) {
                        Text(alertLabel(m)).font(.system(size: 11.5, weight: .medium))
                        Button { note.alerts.removeAll { $0 == m } } label: {
                            Image(systemName: "xmark").font(.system(size: 7.5, weight: .bold)).opacity(0.55)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 9).frame(height: 22)
                    .background(Capsule().fill(fg.opacity(0.1)))
                    .help(note.alertBase.map { line($0.addingTimeInterval(-Double(m) * 60)) } ?? "")
                }
                Menu {
                    ForEach(ALERT_PRESETS.filter { !note.alerts.contains($0) }, id: \.self) { m in
                        Button(alertLabel(m)) { note.alerts.append(m); Reminders.setup() }
                    }
                    Divider()
                    Button(L("Dokładnie…")) {
                        let base = note.alertBase ?? Date().addingTimeInterval(3600)
                        when = max(Date().addingTimeInterval(600), base.addingTimeInterval(-86400))
                        custom = true
                    }
                } label: {
                    Text(note.alerts.isEmpty ? L("+ Przypomnienie") : "+").font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(fg.opacity(0.7))
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .padding(.horizontal, 9).frame(height: 22)
                .background(Capsule().strokeBorder(fg.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
            }
            if custom {
                HStack(spacing: 8) {
                    DatePill(date: $when, fg: fg)
                    DatePill(date: $when, time: true, fg: fg)
                    Button(L("Dodaj")) {
                        if let base = note.alertBase {
                            let m = Int((base.timeIntervalSince(when) / 60).rounded())
                            if !note.alerts.contains(m) { note.alerts.append(m) }
                            Reminders.setup()
                        }
                        custom = false
                    }
                    .buttonStyle(.plain).font(.system(size: 11.5, weight: .semibold))
                    .padding(.horizontal, 10).frame(height: 24).background(Capsule().fill(fg.opacity(0.1)))
                    Button { custom = false } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).opacity(0.5) }
                        .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 2)
    }

    private func line(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.day, .month], from: d)
        return "\(c.day!) \(monthShort(c.month!).lowercased()) \(timeString(d))"
    }
}


/// Pliki karteczki: miniatura albo ikona, nazwa; kliknięcie otwiera, krzyżyk odpina.
struct FilesSection: View {
    @EnvironmentObject var store: Store
    let id: UUID
    let fg: Color
    @State private var hover: UUID?

    var body: some View {
        let files = store.notes.first { $0.id == id }?.files ?? []
        VStack(alignment: .leading, spacing: 6) {
            ForEach(files) { a in
                let url = store.fileURL(id, a)
                HStack(spacing: 8) {
                    FileThumb(url: url)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(a.name).font(.system(size: 12.5, weight: .medium)).foregroundStyle(fg)
                            .lineLimit(1).truncationMode(.middle)
                        Text(ByteCountFormatter.string(fromByteCount: a.size, countStyle: .file))
                            .font(.system(size: 10.5)).foregroundStyle(fg.opacity(0.5))
                    }
                    Spacer(minLength: 4)
                    if hover == a.id {
                        Button { store.detach(id, a) } label: {
                            Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(fg.opacity(0.6))
                                .frame(width: 18, height: 18).background(Circle().fill(fg.opacity(0.1)))
                        }
                        .buttonStyle(.plain).help(L("Odepnij plik"))
                    }
                }
                .padding(.horizontal, 6).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 8).fill(fg.opacity(hover == a.id ? 0.1 : 0.05)))
                .contentShape(Rectangle())
                .onHover { hover = $0 ? a.id : (hover == a.id ? nil : hover) }
                .onTapGesture { NSWorkspace.shared.open(url) }
                .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
                .contextMenu {
                    Button(L("Otwórz")) { NSWorkspace.shared.open(url) }
                    Button(L("Pokaż w Finderze")) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    Divider()
                    Button(L("Odepnij plik")) { store.detach(id, a) }
                }
                .help(a.name)
            }
        }
        .padding(.top, files.isEmpty ? 0 : 8)
    }
}

/// Okno wyboru plików do dołączenia.
func pickFiles(_ id: UUID) {
    let p = NSOpenPanel()
    p.allowsMultipleSelection = true
    p.canChooseDirectories = false
    NSApp.activate(ignoringOtherApps: true)
    if p.runModal() == .OK { Store.shared.attach(id, p.urls) }
}

/// Miniatura zdjęcia albo ikona pliku z Findera (mała kopia, żeby duże zdjęcia nie zjadały pamięci).
struct FileThumb: View {
    let url: URL
    @State private var img: NSImage?
    var body: some View {
        Image(nsImage: img ?? NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFill()
            .frame(width: 26, height: 26)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .task(id: url) {
                let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                             kCGImageSourceThumbnailMaxPixelSize: 96,
                                             kCGImageSourceCreateThumbnailWithTransform: true]
                if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                   CGImageSourceGetType(src) != nil, CGImageSourceGetCount(src) > 0,
                   let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) {
                    img = NSImage(cgImage: cg, size: .zero)
                }
            }
    }
}


/// Data albo godzina jako pigułka w kolorze karteczki (jak „Dziś” i „Jutro”); kliknięcie otwiera wybór.
struct DatePill: View {
    @Binding var date: Date
    var time = false
    var fg: Color
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 5) {
                Image(systemName: time ? "clock" : "calendar").font(.system(size: 10, weight: .bold)).opacity(0.7)
                Text(label).font(.system(size: 11.5, weight: .semibold).monospacedDigit())
            }
            .foregroundStyle(fg)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(fg.opacity(open ? 0.18 : 0.1)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            Group {
                if time {
                    DatePicker("", selection: $date, displayedComponents: [.hourAndMinute])
                        .labelsHidden().datePickerStyle(.stepperField)
                } else {
                    DatePicker("", selection: $date, displayedComponents: [.date])
                        .labelsHidden().datePickerStyle(.graphical)
                }
            }
            .environment(\.locale, Lang.locale)
            .padding(12)
        }
    }

    private var label: String {
        if time { return timeString(date) }
        let f = DateFormatter(); f.locale = Lang.locale
        f.setLocalizedDateFormatFromTemplate("dMMMyyyy")
        return f.string(from: date)
    }
}

