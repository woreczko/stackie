import SwiftUI

let CAL_BG = Color(hex: 0x1F1E23)
var CAL_GREY: Color { Theme.dark ? Color(hex: 0x2A2A2E) : Color(hex: 0xD3D1CD) }
var CAL_PAPER: Color { Theme.dark ? Color(hex: 0x1B1B1E) : Color(hex: 0xF7F1E7) }
/// Jasny papier okienka powitalnego (bez zmiany w ciemnym wyglądzie).
let PAPER_FIXED = Color(hex: 0xF7F1E7)

/// Dni miesiąca w siatce od poniedziałku (puste pola = nil).
func monthGrid(_ m: Date) -> [Date?] {
    var cal = Calendar.current; cal.firstWeekday = 2
    let start = cal.date(from: cal.dateComponents([.year, .month], from: m))!
    let days = cal.range(of: .day, in: .month, for: start)!.count
    let lead = (cal.component(.weekday, from: start) + 5) % 7
    var out: [Date?] = Array(repeating: nil, count: lead)
    for d in 0..<days { out.append(cal.date(byAdding: .day, value: d, to: start)) }
    while out.count % 7 != 0 { out.append(nil) }
    return out
}

func monthTitle(_ m: Date) -> (String, Int) {
    let c = Calendar.current.dateComponents([.month, .year], from: m)
    return (monthName(c.month ?? 1), c.year ?? 2026)
}


/// Kółeczko dnia: pierścień, wypełnienie (dziś, zamknięty projekt) i kropka terminu.
struct DayBubble: View {
    @EnvironmentObject var store: Store
    var day: Date
    var mode: CalMode
    var size: CGFloat
    var dim = false
    var selected = false

    var body: some View {
        // mały dzień (kartka kalendarza w stosie, widok roku): kolor mówi, jak poszedł dzień
        let today = Calendar.current.isDateInToday(day)
        let st = store.dayStatus(day)
        let fill: Color = today ? PriorityIcon.purple : DAY_FILL(st)
        ZStack {
            Circle().fill(fill).padding(size * 0.06)
            Text("\(Calendar.current.component(.day, from: day))")
                .font(.system(size: size * 0.38, weight: today || st != .none ? .bold : .medium).monospacedDigit())
                .foregroundStyle(today || st == .overdue ? .white : st == .done ? Color.inkFixed : Color.ink.opacity(dim ? 0.45 : 0.85))
            if selected { Circle().strokeBorder(Color.ink, lineWidth: 1.5).padding(-size * 0.04) }
        }
        .frame(width: size, height: size)
    }
}

let DAY_DONE = Color(hex: 0x7DD39A)
let DAY_LATE = Color(hex: 0xE5533D)
func DAY_FILL(_ s: Store.DayStatus) -> Color {
    switch s {
    case .done: return DAY_DONE
    case .overdue: return DAY_LATE
    case .open: return Color.ink.opacity(0.2)
    case .none: return Color.ink.opacity(0.05)
    }
}

/// Dzień w widoku miesiąca: pigułka z numerem, pod nim jeden znak (zrobione, zaległe, otwarte), dziś z obwódką.
struct DayPill: View {
    @EnvironmentObject var store: Store
    var day: Date
    var dim = false
    var selected = false

    var body: some View {
        let today = Calendar.current.isDateInToday(day)
        let st = store.dayStatus(day)
        VStack(spacing: 6) {
            Text("\(Calendar.current.component(.day, from: day))")
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .opacity(dim && !today ? 0.5 : 1)
            ZStack {
                switch st {
                case .done:
                    Circle().fill(DAY_DONE)
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(Color.inkFixed)
                case .overdue:
                    Circle().fill(DAY_LATE)
                    Image(systemName: "exclamationmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                case .open:
                    Circle().fill(Color.ink.opacity(0.22))
                case .none:
                    Color.clear
                }
            }
            .frame(width: 18, height: 18)
        }
        .frame(width: 44, height: 60)
        .background(RoundedRectangle(cornerRadius: 19, style: .continuous).fill(Color.ink.opacity(selected ? 0.14 : 0.05)))
        .overlay { if today { RoundedRectangle(cornerRadius: 19, style: .continuous).strokeBorder(Color.ink, lineWidth: 2) } }
        .frame(maxWidth: .infinity)
        .help(st == .done ? L("Wszystko z terminem tego dnia zrobione") : st == .overdue ? L("Termin minął, coś zostało")
              : st == .open ? L("Termin tego dnia") : "")
    }
}

/// Mała karteczka-kalendarz za stosem.
struct CalendarCard: View {
    @EnvironmentObject var store: Store
    var month: Date
    var lifted = false
    var mini = false
    @AppStorage("calMode") private var modeRaw = CalMode.project.rawValue

    var body: some View {
        if mini { miniCard } else { fullCard }
    }

    /// Mała wersja: miesiąc i dwa liczniki, bez siatki dni.
    private var miniCard: some View {
        let (name, year) = monthTitle(month)
        let closed = store.closed(in: month).count
        let ahead = store.due(in: month).filter { !$0.allDone }.count
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(name).font(.system(size: 14, weight: .semibold)).tracking(-0.3).lineLimit(1)
                Spacer(minLength: 2)
                Text("'\(String(format: "%02d", year % 100))").font(.system(size: 9, weight: .semibold)).opacity(0.5)
            }
            Spacer(minLength: 0)
            Image(systemName: "calendar").font(.system(size: 22, weight: .light)).opacity(0.35)
                .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Label("\(closed)", systemImage: "checkmark").help(L("Zamknięte w tym miesiącu"))
                Label("\(ahead)", systemImage: "arrow.right").help(L("Przed nami w tym miesiącu"))
            }
            .font(.system(size: 11, weight: .semibold))
            .labelStyle(TightLabel())
        }
        .foregroundStyle(Color.ink)
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        .frame(width: 150, height: 116, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous).fill(CAL_GREY)
                .shadow(color: .black.opacity(lifted ? 0.3 : 0.18), radius: lifted ? 14 : 6, y: lifted ? 8 : 3)
        )
    }

    private var fullCard: some View {
        let mode = CalMode(rawValue: modeRaw) ?? .project
        let (name, year) = monthTitle(month)
        let grid = monthGrid(month)
        let closed = store.closed(in: month).count
        let ahead = store.due(in: month).filter { !$0.allDone }.count
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(name).font(.system(size: 19, weight: .semibold)).tracking(-0.5)
                Spacer()
                Text("'\(String(format: "%02d", year % 100))").font(.system(size: 11, weight: .semibold)).opacity(0.5)
            }
            .padding(.bottom, 10)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
                ForEach(0..<7, id: \.self) { i in
                    Text(String(weekdays[i].prefix(1))).font(.system(size: 8.5, weight: .bold)).opacity(0.45)
                }
                ForEach(Array(grid.enumerated()), id: \.offset) { _, d in
                    if let d { DayBubble(day: d, mode: mode, size: 23) } else { Color.clear.frame(height: 23) }
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Label("\(closed)", systemImage: "checkmark").help(L("Zamknięte w tym miesiącu"))
                Label("\(ahead)", systemImage: "arrow.right").help(L("Przed nami w tym miesiącu"))
            }
            .font(.system(size: 12, weight: .semibold))
            .labelStyle(TightLabel())
        }
        .foregroundStyle(Color.ink)
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 15, trailing: 16))
        .frame(width: StackLayout.fullW, height: StackLayout.fullH, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(CAL_GREY)
                .shadow(color: .black.opacity(lifted ? 0.3 : 0.18), radius: lifted ? 16 : 7, y: lifted ? 10 : 3)
        )
    }
}

struct TightLabel: LabelStyle {
    func makeBody(configuration c: Configuration) -> some View {
        HStack(spacing: 3) { c.icon.font(.system(size: 8.5, weight: .heavy)); c.title }
    }
}

// MARK: - Duży kalendarz

struct CalendarView: View {
    @EnvironmentObject var store: Store
    var close: () -> Void
    var open: (UUID) -> Void
    @State private var month = Date()
    @State private var selected: Date?
    @AppStorage("calMode") private var modeRaw = CalMode.project.rawValue
    private var mode: CalMode { CalMode(rawValue: modeRaw) ?? .project }
    @AppStorage("calYear") private var yearView = false

    var body: some View {
        let (name, year) = monthTitle(month)
        let isNow = Calendar.current.isDate(month, equalTo: Date(), toGranularity: yearView ? .year : .month)
        HStack(alignment: .top, spacing: 0) {
            // Siatka miesiąca
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    if !yearView {
                        Text(name).font(.system(size: 30, weight: .semibold)).tracking(-0.8).lineLimit(1).fixedSize()
                    }
                    Text(String(year)).font(.system(size: 30, weight: yearView ? .semibold : .regular)).tracking(-0.8)
                        .opacity(yearView ? 1 : 0.35).lineLimit(1).fixedSize()
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    segmented([(L("Miesiąc"), !yearView), (L("Rok"), yearView)]) { i in yearView = i == 1; selected = nil }
                    Spacer()
                    navButton("chevron.left") { shift(-1) }
                    if !isNow {
                        Button(L("Dziś")) { withAnimation(.spring(response: 0.25)) { month = Date(); selected = nil } }
                            .buttonStyle(.plain).font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 10).frame(height: 26).background(Capsule().fill(Color.ink.opacity(0.08)))
                    }
                    navButton("chevron.right") { shift(1) }
                }
                if yearView {
                    YearGrid(year: month, mode: mode) { m in
                        withAnimation(.spring(response: 0.25)) { month = m; yearView = false }
                    }
                } else {
                let grid = monthGrid(month)
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        ForEach(weekdays, id: \.self) { w in
                            Text(w.uppercased()).font(.system(size: 9.5, weight: .bold)).tracking(0.6).opacity(0.45)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 6)
                        }
                    }
                    ForEach(0..<(grid.count / 7), id: \.self) { r in
                        HStack(spacing: 4) {
                            ForEach(0..<7, id: \.self) { c in
                                DayCell(day: grid[r * 7 + c], selected: selected, weekend: c >= 5, mode: mode) { d in
                                    withAnimation(.spring(response: 0.22)) { selected = (selected.map { Calendar.current.isDate($0, inSameDayAs: d) } ?? false) ? nil : d }
                                }
                            }
                        }
                    }
                }
                }
            }
            .padding(24)
            .frame(width: 520)

            // Podsumowanie
            Summary(month: month, selected: selected, mode: mode, g: yearView ? .year : .month, open: open, clearDay: { selected = nil })
                .frame(width: 340)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(CAL_BG)
        }
        .foregroundStyle(Color.ink)
        .frame(width: 860, height: 600)
        .background(CAL_PAPER)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.black.opacity(0.12)))
        .overlay(alignment: .topTrailing) {
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.8))
                    .frame(width: 22, height: 22).background(Circle().fill(.white.opacity(0.12)))
            }
            .buttonStyle(.plain).keyboardShortcut(.cancelAction).padding(10)
        }
    }

    private func shift(_ k: Int) {
        withAnimation(.spring(response: 0.25)) {
            month = Calendar.current.date(byAdding: yearView ? .year : .month, value: k, to: month)!
            selected = nil
        }
    }

    private func segmented(_ items: [(String, Bool)], _ pick: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, it in
                Button { withAnimation(.spring(response: 0.25)) { pick(i) } } label: {
                    Text(it.0).font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(it.1 ? Color.onInk : Color.ink.opacity(0.7))
                        .padding(.horizontal, 10).frame(height: 24)
                        .background(Capsule().fill(it.1 ? Color.ink : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2).background(Capsule().fill(Color.ink.opacity(0.07)))
    }

    private func navButton(_ icon: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Image(systemName: icon).font(.system(size: 11, weight: .bold))
                .frame(width: 26, height: 26).background(Circle().fill(Color.ink.opacity(0.08))).contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct DayCell: View {
    var day: Date?
    var selected: Date?
    var weekend: Bool
    var mode: CalMode
    var tap: (Date) -> Void

    var body: some View {
        if let day {
            let sel = selected.map { Calendar.current.isDate($0, inSameDayAs: day) } ?? false
            DayPill(day: day, dim: weekend, selected: sel)
                .frame(maxWidth: .infinity, minHeight: 62, maxHeight: 62)
                .contentShape(Rectangle())
                .onTapGesture { tap(day) }
        } else {
            Color.clear.frame(maxWidth: .infinity, minHeight: 62, maxHeight: 62)
        }
    }
}

private struct Summary: View {
    @EnvironmentObject var store: Store
    var month: Date
    var selected: Date?
    var mode: CalMode
    var g: Calendar.Component = .month
    var open: (UUID) -> Void
    var clearDay: () -> Void

    var body: some View {
        let closed = store.closed(in: month, g)
        let done = store.tasksDone(in: month, g)
        let isNow = Calendar.current.isDate(month, equalTo: Date(), toGranularity: g)
        let isPast = month < Date() && !isNow
        // przed nami: w bieżącym miesiącu wszystko z terminem (też zaległe i dalsze), w innym tylko ten miesiąc
        let ahead = isNow ? store.upcoming : store.due(in: month, g).filter { !$0.allDone }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(L("PODSUMOWANIE")).font(.system(size: 10, weight: .bold)).tracking(1).opacity(0.5)
                HStack(spacing: 18) {
                    stat("\(closed.count)", L("zamknięte\nprojekty"))
                    stat("\(done)", L("odhaczone\nzadania"))
                    if !isPast { stat("\(ahead.count)", L("przed\nnami")) }
                }
                .padding(.top, 10)

                // dwa paski: status zadań i dla kogo robimy najwięcej (ten sam okres)
                StatusBar(status: store.taskStatus(in: month, g)).padding(.top, 22)
                ShareBar(month: month, g: g)
                if let selected {
                    let day = store.touched(on: selected)
                    sectionTitle("\(Calendar.current.component(.day, from: selected)) \(monthShort(Calendar.current.component(.month, from: selected)).lowercased())", clear: true)
                    if day.isEmpty { empty(L("Nic tego dnia.")) }
                    ForEach(day) { row($0) }
                }

                sectionTitle(L("Zamknięte"))
                if closed.isEmpty { empty(isPast || isNow ? L("Jeszcze nic nie zamknięte.") : L("To dopiero przed nami.")) }
                ForEach(closed) { row($0) }

                if !isPast {
                    sectionTitle(isNow ? L("Przed nami") : L(g == .year ? "Terminy w tym roku" : "Terminy w tym miesiącu"))
                    if ahead.isEmpty { empty(L("Brak terminów. Spokojnie.")) }
                    ForEach(ahead) { row($0) }
                }
            }
            .padding(EdgeInsets(top: 22, leading: 20, bottom: 20, trailing: 20))
        }
        .scrollIndicators(.never)
        .foregroundStyle(.white)
    }

    private func stat(_ n: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(n).font(.system(size: 30, weight: .regular)).tracking(-1).monospacedDigit()
            Text(label).font(.system(size: 9.5, weight: .semibold)).opacity(0.55).lineSpacing(0)
        }
    }

    private func sectionTitle(_ t: String, clear: Bool = false) -> some View {
        HStack {
            Text(t.uppercased()).font(.system(size: 10, weight: .bold)).tracking(1).opacity(0.5)
            if clear {
                Spacer()
                Button(action: clearDay) { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).opacity(0.6) }.buttonStyle(.plain)
            }
        }
        .padding(.top, 22).padding(.bottom, 8)
    }

    private func empty(_ t: String) -> some View {
        Text(t).font(.system(size: 12)).opacity(0.45)
    }

    private func row(_ n: Note) -> some View {
        Button { open(n.id) } label: {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 3).fill(accent(n.color)).frame(width: 6, height: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(n.shownTitle).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                        .strikethrough(n.archived, color: .white.opacity(0.5))
                    Text(subtitle(n)).font(.system(size: 10)).opacity(0.5).lineLimit(1)
                }
                Spacer(minLength: 4)
                if !n.archived, let info = dueInfo(n), info.level >= 1 {
                    DuePill(text: info.text, level: info.level, fg: .white)
                }
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func subtitle(_ n: Note) -> String {
        var parts: [String] = []
        let date = n.archived ? n.archivedAt : n.deadline
        if let date {
            let c = Calendar.current.dateComponents([.day, .month], from: date)
            parts.append(LF(n.archived ? "zamknięte %@" : "termin %@", "\(c.day!) \(monthShort(c.month!).lowercased())"))
        }
        if !n.tasks.isEmpty { parts.append(LF("%d/%d zadań", n.doneCount, n.tasks.count)) }
        if !n.client.isEmpty { parts.append(n.client) }
        else if !n.tags.isEmpty { parts.append(n.tags.prefix(2).joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }
}


/// Cały rok: 12 małych miesięcy z kółkami dni; kliknięcie miesiąca otwiera go.
private struct YearGrid: View {
    var year: Date
    var mode: CalMode
    var pick: (Date) -> Void

    var body: some View {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year], from: year))!
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
            ForEach(0..<12, id: \.self) { i in
                let m = cal.date(byAdding: .month, value: i, to: start)!
                let now = cal.isDate(m, equalTo: Date(), toGranularity: .month)
                VStack(alignment: .leading, spacing: 5) {
                    Text(monthName(i + 1)).font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(now ? PriorityIcon.purple : Color.ink)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 2) {
                        ForEach(Array(monthGrid(m).enumerated()), id: \.offset) { _, d in
                            if let d { DayBubble(day: d, mode: mode, size: 15) } else { Color.clear.frame(height: 15) }
                        }
                    }
                }
                .padding(7)
                .frame(maxWidth: .infinity, minHeight: 142, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.ink.opacity(now ? 0.07 : 0.03)))
                .contentShape(Rectangle())
                .onTapGesture { pick(m) }
            }
        }
    }
}


/// Pasek z segmentami (szerokość = udział), zaokrąglone kawałki z odstępem jak na referencji.
private struct SegBar: View {
    var parts: [(Color, Int)]
    var height: CGFloat = 24
    var body: some View {
        let total = max(1, parts.reduce(0) { $0 + $1.1 })
        GeometryReader { g in
            let gap: CGFloat = 3, n = CGFloat(parts.filter { $0.1 > 0 }.count)
            let w = max(0, g.size.width - gap * max(0, n - 1))
            HStack(spacing: gap) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, p in
                    if p.1 > 0 {
                        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(p.0)
                            .frame(width: max(4, w * CGFloat(p.1) / CGFloat(total)))
                    }
                }
            }
        }
        .frame(height: height)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white.opacity(parts.allSatisfy { $0.1 == 0 } ? 0.08 : 0)))
        .animation(.spring(response: 0.35), value: parts.map(\.1))
    }
}

/// Status zadań okresu: zamknięte, w trakcie, nieruszone.
private struct StatusBar: View {
    var status: (done: Int, doing: Int, idle: Int)
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(L("STATUS ZADAŃ")).font(.system(size: 10, weight: .bold)).tracking(1).opacity(0.5)
            SegBar(parts: [(Color(hex: 0x7DD39A), status.done), (Color(hex: 0xA597F3), status.doing), (.white.opacity(0.22), status.idle)])
            HStack(alignment: .top, spacing: 0) {
                item(Color(hex: 0x7DD39A), status.done, L("zamknięte"))
                item(Color(hex: 0xA597F3), status.doing, L("w trakcie"))
                item(.white.opacity(0.35), status.idle, L("nieruszone"))
            }
        }
    }
    private func item(_ c: Color, _ n: Int, _ t: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5).fill(c).frame(width: 3, height: 30)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(n)").font(.system(size: 15, weight: .semibold)).monospacedDigit()
                Text(t).font(.system(size: 10.5)).opacity(0.6).lineLimit(1).fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Dla kogo robimy najwięcej: klienci albo projekty, wszystkie albo zamknięte zadania.
private struct ShareBar: View {
    @EnvironmentObject var store: Store
    var month: Date
    var g: Calendar.Component
    @AppStorage("shareByClient") private var byClient = true
    @AppStorage("shareDone") private var doneOnly = false

    var body: some View {
        let list = store.share(in: month, g, byClient: byClient, doneOnly: doneOnly)
        let total = max(1, list.reduce(0) { $0 + $1.count })
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("DLA KOGO NAJWIĘCEJ")).font(.system(size: 10, weight: .bold)).tracking(1).opacity(0.5)
                Spacer()
            }
            .padding(.top, 22)
            HStack(spacing: 6) {
                toggle([(L("Klienci"), byClient), (L("Projekty"), !byClient)]) { byClient = $0 == 0 }
                toggle([(L("Wszystkie"), !doneOnly), (L("Zamknięte"), doneOnly)]) { doneOnly = $0 == 1 }
            }
            SegBar(parts: list.map { ($0.color, $0.count) })
            if list.isEmpty {
                Text(doneOnly ? L("Nic jeszcze nie odhaczone.") : L("Brak zadań w tym okresie.")).font(.system(size: 12)).opacity(0.45)
            }
            // legenda: kolor, nazwa, liczba zadań, udział
            VStack(alignment: .leading, spacing: 7) {
                ForEach(list) { s in
                    Button { pick(s) } label: {
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 1.5).fill(s.color).frame(width: 3, height: 16)
                            Text(s.label).font(.system(size: 12, weight: .medium)).lineLimit(1).opacity(0.85)
                            Spacer(minLength: 6)
                            Text("\(s.count)").font(.system(size: 12, weight: .semibold)).monospacedDigit().opacity(0.85)
                            Text("\(Int((Double(s.count) * 100 / Double(total)).rounded()))%").font(.system(size: 10.5, weight: .semibold)).monospacedDigit()
                                .padding(.horizontal, 6).frame(height: 18).background(Capsule().fill(.white.opacity(0.08)))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(s.client.isEmpty && s.project.isEmpty)
                    .help(s.client.isEmpty && s.project.isEmpty ? "" : L("Pokaż w stosie tylko te karteczki"))
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.05)))
            Text(L("Udział w liczbie zadań, nie w czasie pracy.")).font(.system(size: 9.5)).opacity(0.4)
        }
    }

    /// Kliknięcie: stos pokazuje tylko tego klienta albo projekt.
    private func pick(_ s: Store.Share) {
        if !s.client.isEmpty { UIState.shared.setFilter(client: s.client) }
        else if !s.project.isEmpty { UIState.shared.setFilter(project: s.project) }
        else { return }
        AppDelegate.shared?.toggleCalendar()
    }

    private func toggle(_ items: [(String, Bool)], _ pick: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, it in
                Button { withAnimation(.spring(response: 0.25)) { pick(i) } } label: {
                    Text(it.0).font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(it.1 ? Color(hex: 0x1E1D22) : .white.opacity(0.7))
                        .padding(.horizontal, 8).frame(height: 20)
                        .fixedSize()
                        .background(Capsule().fill(it.1 ? .white.opacity(0.9) : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2).background(Capsule().fill(.white.opacity(0.08)))
    }
}
