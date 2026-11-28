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

/// Pierścień dnia: równe części na każdy projekt albo tag z tego dnia.
struct DayRing: View {
    var segs: [Seg]
    var width: CGFloat

    var body: some View {
        let n = Double(segs.count)
        let gap = n > 1 ? 0.06 : 0
        ZStack {
            ForEach(Array(segs.enumerated()), id: \.offset) { i, sg in
                Circle()
                    .trim(from: Double(i) / n + gap / 2, to: Double(i + 1) / n - gap / 2)
                    .stroke(sg.color, style: StrokeStyle(lineWidth: width, lineCap: n > 1 ? .round : .butt))
            }
        }
        .rotationEffect(.degrees(-90))
        .padding(width / 2)
    }
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
        let today = Calendar.current.isDateInToday(day)
        let closed = store.closedOn(day)
        let due = store.deadlineOn(day)
        let ring = size * 0.09
        let fill: Color = today ? PriorityIcon.purple : closed ? Color.ink : Color.ink.opacity(0.05)
        ZStack {
            Circle().fill(fill).padding(ring + size * 0.04)
            DayRing(segs: store.segments(on: day, mode: mode), width: ring)
            Text("\(Calendar.current.component(.day, from: day))")
                .font(.system(size: size * 0.34, weight: today || closed ? .bold : .medium).monospacedDigit())
                .foregroundStyle(today ? .white : closed ? Color.onInk : Color.ink.opacity(dim ? 0.45 : 0.85))
            if due {
                Circle().fill(PriorityIcon.purple)
                    .overlay(Circle().strokeBorder(CAL_PAPER, lineWidth: size * 0.04))
                    .frame(width: size * 0.26, height: size * 0.26)
                    .offset(x: size * 0.34, y: size * 0.34)
            }
            if selected {
                Circle().strokeBorder(Color.ink, lineWidth: 1.5).padding(-size * 0.08)
            }
        }
        .frame(width: size, height: size)
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
                    HStack(spacing: 2) {
                        ForEach([CalMode.client, .project, .tag], id: \.self) { m in
                            Button { withAnimation(.spring(response: 0.25)) { modeRaw = m.rawValue } } label: {
                                Text(m == .client ? L("Klienci") : m == .project ? L("Projekty") : L("Tagi")).font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(mode == m ? Color.onInk : Color.ink.opacity(0.7))
                                    .padding(.horizontal, 10).frame(height: 24)
                                    .background(Capsule().fill(mode == m ? Color.ink : .clear))
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(2).background(Capsule().fill(Color.ink.opacity(0.07)))
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
                .frame(width: 280)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(CAL_BG)
        }
        .foregroundStyle(Color.ink)
        .frame(width: 800, height: 600)
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
            DayBubble(day: day, mode: mode, size: 52, dim: weekend, selected: sel)
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

                Donut(progress: store.progress(in: month, g), year: g == .year).padding(.top, 22)

                let legend = store.segments(of: store.projects(in: month, g), mode: mode)
                if !legend.isEmpty {
                    sectionTitle(mode == .client ? L("Kolory klientów") : mode == .project ? L("Kolory projektów") : L("Kolory tagów"))
                    FlowLayout(spacing: 6) {
                        ForEach(legend, id: \.self) { sg in
                            HStack(spacing: 5) {
                                Circle().fill(sg.color).frame(width: 8, height: 8)
                                Text(sg.label).font(.system(size: 11, weight: .medium)).lineLimit(1)
                            }
                            .padding(.horizontal, 8).frame(height: 22)
                            .background(Capsule().fill(.white.opacity(0.08)))
                        }
                    }
                }

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

/// Wykres: ile zadań z projektów tego miesiąca zrobione, a ile zostało.
private struct Donut: View {
    var progress: (done: Int, total: Int)
    var year = false

    var body: some View {
        let p = progress.total == 0 ? 0 : Double(progress.done) / Double(progress.total)
        HStack(spacing: 18) {
            ZStack {
                Circle().stroke(.white.opacity(0.13), lineWidth: 14)
                Circle().trim(from: 0, to: p)
                    .stroke(Color(hex: 0x9BE08F), style: StrokeStyle(lineWidth: 14, lineCap: p > 0 && p < 1 ? .round : .butt))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(Int((p * 100).rounded()))%").font(.system(size: 22, weight: .semibold)).monospacedDigit()
                }
            }
            .frame(width: 104, height: 104)
            .animation(.spring(response: 0.4), value: p)
            VStack(alignment: .leading, spacing: 8) {
                legendRow(Color(hex: 0x9BE08F), L("zrobione"), progress.done)
                legendRow(.white.opacity(0.25), L("zostało"), progress.total - progress.done)
                Text(L(year ? "zadania z projektów\ntego roku" : "zadania z projektów\ntego miesiąca")).font(.system(size: 9.5)).opacity(0.45)
            }
        }
    }

    private func legendRow(_ c: Color, _ t: String, _ n: Int) -> some View {
        HStack(spacing: 6) {
            Circle().fill(c).frame(width: 8, height: 8)
            Text("\(n)").font(.system(size: 13, weight: .semibold)).monospacedDigit()
            Text(t).font(.system(size: 11)).opacity(0.65)
        }
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
