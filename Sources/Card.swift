import SwiftUI

/// Karteczka w stosie.
struct CardView: View {
    @Binding var note: Note
    var lifted = false
    private var maxTasks: Int {
        max(1, 4 - (note.tags.isEmpty ? 0 : 1) - (note.title.count > 17 ? 1 : 0) - (note.client.isEmpty && note.project.isEmpty ? 0 : 1))
    }

    var body: some View {
        let pal = palette(note.color)
        let fg: Color = pal.dark ? .white : .ink
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                if note.priority > 0 || note.allDone {
                    PriorityIcon(level: note.priority, done: note.allDone, faint: fg)
                        .frame(width: 30, height: 30)
                }
                if note.remind {
                    SnoozeBell(note: $note, fg: fg)
                        .padding(.leading, note.priority > 0 || note.allDone ? 4 : 0)
                }
                Spacer(minLength: 6)
                DateBadge(note: note, fg: fg)
            }
            .frame(minHeight: 62, alignment: .top)

            if !note.client.isEmpty || !note.project.isEmpty {
                Button { UIState.shared.setFilter(client: note.client.isEmpty ? nil : note.client,
                                                  project: note.client.isEmpty ? note.project : nil) } label: {
                    HStack(spacing: 5) {
                        if !note.client.isEmpty {
                            Circle().fill(Store.shared.clientColor(note.client))
                                .overlay(Circle().strokeBorder(fg.opacity(0.35), lineWidth: 0.5)).frame(width: 7, height: 7)
                        }
                        Text([note.client, note.project].filter { !$0.isEmpty }.joined(separator: " · ").uppercased())
                            .font(.system(size: 9.5, weight: .bold)).tracking(0.7).lineLimit(1)
                            .foregroundStyle(fg.opacity(0.6))
                    }
                }
                .buttonStyle(.plain)
                .help(note.client.isEmpty ? note.project : LF("Pokaż projekty klienta %@", note.client))
                .padding(.top, 4)
            }

            Text(note.title.isEmpty ? L("Bez tytułu") : note.title)
                .font(.system(size: 19, weight: .semibold))
                .tracking(-0.5)
                .lineSpacing(-2)
                .foregroundStyle(fg.opacity(note.title.isEmpty ? 0.4 : 1))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            if !note.tasks.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(note.tasks.prefix(maxTasks).enumerated()), id: \.element.id) { i, t in
                        HStack(alignment: .top, spacing: 7) {
                            Button { note.tasks[i].done.toggle() } label: { CheckCircle(done: t.done, color: fg, size: 15) }
                                .buttonStyle(.plain)
                            Text(t.text.isEmpty ? "…" : t.text)
                                .font(.system(size: 12.5))
                                .strikethrough(t.done, color: fg.opacity(0.5))
                                .foregroundStyle(fg.opacity(t.done ? 0.45 : 0.9))
                                .lineLimit(1)
                        }
                    }
                    if note.tasks.count > maxTasks {
                        Text(LF("+ jeszcze %d", note.tasks.count - maxTasks)).font(.system(size: 11, weight: .medium))
                            .foregroundStyle(fg.opacity(0.5)).padding(.leading, 22)
                    }
                }
                .padding(.top, 10)
            } else if !note.body.isEmpty {
                Text(note.body).font(.system(size: 12.5)).foregroundStyle(fg.opacity(0.75))
                    .lineLimit(5).padding(.top, 8)
            }

            Spacer(minLength: 0)

            if !note.tags.isEmpty || !note.files.isEmpty {
                HStack(spacing: 4) {
                    ForEach(note.tags.prefix(2), id: \.self) { t in
                        Button { UIState.shared.setFilter(tag: t) } label: { TagPill(text: t, fg: fg, dark: palette(note.color).dark, bg: palette(note.color).bg) }
                            .buttonStyle(.plain).help(LF("Pokaż karteczki z tagiem %@", t))
                    }
                    if note.tags.count > 2 {
                        Text("+\(note.tags.count - 2)").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(fg.opacity(0.55))
                    }
                    if !note.files.isEmpty {
                        Spacer(minLength: 4)
                        HStack(spacing: 2) {
                            Image(systemName: "paperclip").font(.system(size: 10, weight: .bold))
                            Text("\(note.files.count)").font(.system(size: 11, weight: .semibold).monospacedDigit())
                        }
                        .foregroundStyle(fg.opacity(0.6))
                        .help(LF("Pliki: %d", note.files.count))
                    }
                }
                .padding(.bottom, note.tasks.isEmpty ? 0 : 9)
            }

            if !note.tasks.isEmpty {
                HStack(spacing: 8) {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(fg.opacity(0.14))
                            Capsule().fill(fg.opacity(0.8))
                                .frame(width: g.size.width * CGFloat(note.doneCount) / CGFloat(max(1, note.tasks.count)))
                        }
                    }
                    .frame(height: 3)
                    Text("\(note.doneCount)/\(note.tasks.count)")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(fg.opacity(0.7))
                }
            }
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 15, trailing: 16))
        .frame(width: StackLayout.cardW, height: StackLayout.cardH, alignment: .topLeading)
        .background(
            // cień tylko pod samą kartką, nie pod tekstem i tagami
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(pal.bg)
                .shadow(color: .black.opacity(lifted ? 0.28 : 0.16), radius: lifted ? 16 : 7, x: 0, y: lifted ? 10 : 3)
        )
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.black.opacity(0.07), lineWidth: 1))
    }
}

/// Tag jak w referencji: biała pigułka.
struct TagPill: View {
    var text: String
    var fg: Color
    var dark: Bool
    var removable = false
    /// Kolor kartki: na pigułce staje się kolorem napisu (odwrócone barwy).
    var bg: Color = .white

    var body: some View {
        HStack(spacing: 4) {
            // zawsze wielkimi literami: równa linia bez ogonków (g, p, y)
            Text(text.uppercased()).tracking(0.5).lineLimit(1).truncationMode(.tail).frame(maxWidth: 100)
            if removable { Image(systemName: "xmark").font(.system(size: 5.5, weight: .semibold)).opacity(0.6) }
        }
        .font(.system(size: 7.5, weight: .medium))
        .foregroundStyle(dark ? Color.ink : bg)
        .fixedSize()
        .padding(.horizontal, 5).padding(.vertical, 1.5)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .circular).fill(dark ? Color(hex: 0xF7F1E7).opacity(0.9) : Color.ink.opacity(0.8))
            }
        }
    }
}

/// Data w prawym górnym rogu: duży dzień, pod nim miesiąc i rok, pod spodem ile zostało.
struct DateBadge: View {
    var note: Note
    var fg: Color

    var body: some View {
        let d = note.deadline ?? note.created
        let c = Calendar.current.dateComponents([.day, .month, .year], from: d)
        let info = dueInfo(note)
        let overdue = (info?.level ?? 0) == 3
        let dim = note.deadline == nil ? 0.35 : 1.0
        VStack(alignment: .trailing, spacing: 0) {
            Text("\(c.day ?? 1)")
                .font(.system(size: 38, weight: .regular))
                .tracking(-1.5)
                .foregroundStyle(overdue ? Color(hex: 0xC4281B) : fg)
                .opacity(dim)
                .frame(height: 36)
            Text("\(monthShort(c.month ?? 1)) '\(String(format: "%02d", (c.year ?? 2000) % 100))")
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(fg.opacity(0.8 * dim))
            if let info, info.level >= 0 {
                DuePill(text: info.text, level: info.level, fg: fg).padding(.top, 4)
            }
        }
    }
}

struct DuePill: View {
    var text: String
    var level: Int
    var fg: Color

    var body: some View {
        let bg: Color = level == 3 ? Color(hex: 0xD93A26) : level == 2 ? fg : fg.opacity(level == 1 ? 0.16 : 0.08)
        let tx: Color = level >= 2 ? (fg == .white && level == 2 ? .ink : .white) : fg.opacity(0.85)
        // wielkimi literami, jak tagi
        Text(text.uppercased())
            .font(.system(size: 8, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(tx)
            .padding(.horizontal, 6).padding(.vertical, 2.5)
            .background(Capsule().fill(bg))
    }
}

/// Dzwoneczek na karteczce: menu drzemki jak w budziku (odłóż, wycisz, przypomnienia).
struct SnoozeBell: View {
    @Binding var note: Note
    var fg: Color

    var body: some View {
        let icon = note.hopMuted ? "bell.slash.fill" : note.hopSnoozed ? "moon.zzz.fill" : "bell.fill"
        Menu {
            if let until = note.hopSnoozeUntil, note.hopSnoozed {
                Text(LF("Odłożone do %@", timeString(until)))
            }
            Button(L("Odłóż na 10 min")) { snooze(10) }
            Button(L("Odłóż na 30 min")) { snooze(30) }
            Button(L("Odłóż na 1 godz.")) { snooze(60) }
            Button(L("Do jutra rano")) {
                let cal = Calendar.current
                let morning = cal.date(bySettingHour: 9, minute: 0, second: 0,
                                       of: cal.date(byAdding: .day, value: 1, to: Date())!)!
                note.hopSnoozeUntil = morning
            }
            Divider()
            if note.hopMuted || note.hopSnoozed {
                Button(L("Włącz podskakiwanie")) { note.hopMutedFor = nil; note.hopSnoozeUntil = nil }
            } else {
                Button(L("Wycisz (do zmiany terminu)")) { note.hopMutedFor = note.deadline }
            }
            Divider()
            Button(L("Ustaw przypomnienia…")) { AppDelegate.shared?.openEditor(note.id) }
        } label: {
            Image(systemName: icon).font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(fg.opacity(note.hops ? 0.75 : 0.45))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L("Drzemka i wyciszenie"))
    }

    private func snooze(_ min: Double) { note.hopSnoozeUntil = Date().addingTimeInterval(min * 60) }
}
