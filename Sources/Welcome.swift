import SwiftUI
import Speech
import AVFoundation
import UserNotifications

// MARK: - Okienko powitalne: strony z animacjami możliwości i historia zmian

let APP_VERSION = "1.0"

struct WelcomePage { let title: String; let text: String; let demo: AnyView }

struct WelcomeView: View {
    var close: () -> Void
    @State private var page: Int

    init(close: @escaping () -> Void, startPage: Int = 0) {
        self.close = close
        _page = State(initialValue: startPage)
    }

    private var pages: [WelcomePage] {
        [
            WelcomePage(title: L("Witaj w Stosiku"), text: L("Karteczki leżą na pulpicie jak talia kart. Najedź myszką, a stos się rozłoży."), demo: AnyView(DemoStack())),
            WelcomePage(title: L("Projekty i zadania"), text: L("Jedna karteczka to jeden projekt. Odhaczasz kółeczka, a pasek pokazuje postęp. Zadania przesuwasz za uchwyt."), demo: AnyView(DemoTasks())),
            WelcomePage(title: L("Terminy i przypomnienia"), text: L("Data w rogu, pilność w kolorach. Dzwoneczek ustawia przypomnienia, a karteczka podskakuje, gdy termin jest blisko."), demo: AnyView(DemoReminder())),
            WelcomePage(title: L("Klienci, projekty i tagi"), text: L("Każda karteczka może mieć klienta, projekt i tagi. Kliknij jeden z nich, żeby zostawić w stosie tylko to, co do niego pasuje."), demo: AnyView(DemoFilter())),
            WelcomePage(title: L("Kalendarz i podsumowanie"), text: L("Szara karta na końcu stosu to kalendarz. Kółka dni pokazują, co się działo, a wykres, ile zostało."), demo: AnyView(DemoCalendar())),
            WelcomePage(title: L("Kosz na 30 dni"), text: L("Pociągnij karteczkę w dół, aż kosz zrobi się czerwony. Przez 30 dni możesz ją przywrócić."), demo: AnyView(DemoTrash())),
            WelcomePage(title: L("Dyktowanie"), text: L("Kliknij mikrofon i powiedz, co jest do zrobienia. Każdy czasownik zaczyna nowe zadanie, a „klient”, „projekt” i „tag” wypełniają pola."), demo: AnyView(DemoDictation())),
        ]
    }

    var body: some View {
        let all = pages.count + 2
        VStack(spacing: 0) {
            ZStack {
                if page < pages.count {
                    pages[page].demo
                        .id(page)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                } else if page == pages.count {
                    Permissions().transition(.opacity)
                } else {
                    Changelog().transition(.opacity)
                }
            }
            .frame(height: page < pages.count ? 260 : 380)
            .frame(maxWidth: .infinity)
            .background(page < pages.count ? Color(hex: 0x1F1E23) : CAL_PAPER)
            .clipped()

            if page < pages.count {
                VStack(alignment: .leading, spacing: 8) {
                    Text(pages[page].title).font(.system(size: 24, weight: .semibold)).tracking(-0.5)
                    Text(pages[page].text).font(.system(size: 13.5)).foregroundStyle(Color.ink.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 20, leading: 26, bottom: 0, trailing: 26))
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                ForEach(0..<all, id: \.self) { i in
                    Capsule().fill(Color.ink.opacity(i == page ? 0.8 : 0.15)).frame(width: i == page ? 18 : 6, height: 6)
                        .onTapGesture { withAnimation(.spring(response: 0.35)) { page = i } }
                }
                Spacer()
                if page > 0 {
                    Button(L("Wstecz")) { withAnimation(.spring(response: 0.35)) { page -= 1 } }
                        .buttonStyle(.plain).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.ink.opacity(0.6))
                        .padding(.trailing, 10)
                }
                Button {
                    if page < all - 1 { withAnimation(.spring(response: 0.35)) { page += 1 } } else { close() }
                } label: {
                    Text(page < all - 1 ? L("Dalej") : L("Zaczynamy"))
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 18).frame(height: 32).background(Capsule().fill(Color.ink))
                }
                .buttonStyle(.plain).keyboardShortcut(.defaultAction)
            }
            .padding(EdgeInsets(top: 12, leading: 26, bottom: 20, trailing: 22))
        }
        .foregroundStyle(Color.ink)
        .frame(width: 560, height: 470)
        .background(CAL_PAPER)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.black.opacity(0.12)))
        .overlay(alignment: .topTrailing) {
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.8))
                    .frame(width: 24, height: 24).background(Circle().fill(.white.opacity(0.15)))
            }
            .buttonStyle(.plain).keyboardShortcut(.cancelAction).padding(12)
            .opacity(page < pages.count ? 1 : 0)
        }
    }
}

// MARK: - Historia zmian

struct Release { let version: String; let date: String; let items: [String] }

var RELEASES: [Release] {[
    Release(version: "1.0", date: "27.11.2026", items: [
        L("Stos karteczek na pulpicie jak talia kart: rozkłada się po najechaniu, na mniejszym ekranie w rzędach"),
        L("Projekty z zadaniami, klient, projekt i tagi w kolorach, pilność, szukanie i filtr"),
        L("Terminy i przypomnienia jak w Kalendarzu, karteczki podskakują przy bliskim terminie, drzemka na dzwoneczku"),
        L("Kalendarz z pierścieniami dni, widok roku i podsumowanie: zrobione i zostało"),
        L("Kosz na 30 dni: przeciągnij karteczkę w dół"),
        L("Dyktowanie zadań głosem, wersja polska (Stosik) i angielska (Stackie)"),
    ]),
]}

struct Changelog: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("Co nowego")).font(.system(size: 24, weight: .semibold)).tracking(-0.5)
            Text(LF("Wersja %@", APP_VERSION)).font(.system(size: 12)).foregroundStyle(Color.ink.opacity(0.5)).padding(.bottom, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(RELEASES, id: \.version) { r in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(r.version).font(.system(size: 13, weight: .bold))
                                    .padding(.horizontal, 8).padding(.vertical, 2)
                                    .background(Capsule().fill(r.version == APP_VERSION ? PriorityIcon.yellow : Color.ink.opacity(0.07)))
                                Text(r.date).font(.system(size: 11)).foregroundStyle(Color.ink.opacity(0.45))
                            }
                            ForEach(r.items, id: \.self) { it in
                                HStack(alignment: .top, spacing: 8) {
                                    Circle().fill(Color.ink.opacity(0.35)).frame(width: 4, height: 4).padding(.top, 6)
                                    Text(it).font(.system(size: 12.5)).foregroundStyle(Color.ink.opacity(0.8))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
        }
        .padding(EdgeInsets(top: 26, leading: 26, bottom: 0, trailing: 26))
    }
}

// MARK: - Animacje (zapętlone, liczone od czasu)

/// Faza 0…1 w pętli o długości `period` sekund.
/// Do zrzutów testowych: zatrzymuje animacje w danej fazie.
var FROZEN_PHASE: Double? = nil

struct Loop<C: View>: View {
    var period: Double
    @ViewBuilder var content: (Double) -> C
    var body: some View {
        if let f = FROZEN_PHASE { content(f) } else {
            TimelineView(.animation) { tl in
                content(tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period)
            }
        }
    }
}

/// Gładkie przejście 0→1 między a i b (smoothstep).
func ease(_ t: Double, _ a: Double, _ b: Double) -> Double {
    let x = min(max((t - a) / (b - a), 0), 1); return x * x * (3 - 2 * x)
}

struct MiniCard: View {
    var color: Color
    var title = ""
    var lines = 3
    var done = 0
    var w: CGFloat = 92, h: CGFloat = 116
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack { Spacer(); Text("27").font(.system(size: 15, weight: .regular)).foregroundStyle(Color.ink.opacity(0.6)) }
            if !title.isEmpty { Text(title).font(.system(size: 9.5, weight: .bold)).foregroundStyle(Color.ink).lineLimit(1) }
            ForEach(0..<lines, id: \.self) { i in
                HStack(spacing: 4) {
                    Circle().strokeBorder(Color.ink.opacity(0.6), lineWidth: 1).background(Circle().fill(i < done ? Color.ink : .clear))
                        .frame(width: 7, height: 7)
                    RoundedRectangle(cornerRadius: 1.5).fill(Color.ink.opacity(i < done ? 0.18 : 0.35)).frame(height: 3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(width: w, height: h, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(color).shadow(color: .black.opacity(0.25), radius: 5, y: 3))
    }
}

private let DEMO_COLORS = [palette(2).bg, palette(1).bg, palette(3).bg, palette(6).bg, CAL_GREY]

struct DemoStack: View {
    var body: some View {
        Loop(period: 4) { t in
            let s = ease(t, 0.15, 0.35) - ease(t, 0.7, 0.9)   // rozkładanie i składanie
            ZStack {
                ForEach((0..<5).reversed(), id: \.self) { i in
                    let tight = -40 + CGFloat(i) * 12, wide = (CGFloat(i) - 2) * 100
                    let x = tight + (wide - tight) * s
                    let ang = (i % 2 == 0 ? -3.2 : 3.6) * (1 - s)
                    MiniCard(color: DEMO_COLORS[i], lines: 3, done: i == 0 ? 1 : 0)
                        .rotationEffect(.degrees(ang))
                        .offset(x: x, y: -CGFloat(i) * 2 * (1 - s))
                }
                Image(systemName: "cursorarrow").font(.system(size: 18)).foregroundStyle(.white)
                    .shadow(radius: 2)
                    .offset(x: -60 + 20 * s, y: 70 - 40 * ease(t, 0.05, 0.15))
            }
        }
    }
}

struct DemoTasks: View {
    var body: some View {
        Loop(period: 4.5) { t in
            let done = Int(ease(t, 0.15, 0.75) * 3.99)
            HStack(spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Studio Nova").font(.system(size: 11, weight: .bold)).tracking(0.6).foregroundStyle(Color.ink.opacity(0.55))
                    Text(L("Prezentacja")).font(.system(size: 18, weight: .semibold)).foregroundStyle(Color.ink)
                    ForEach(0..<3, id: \.self) { i in
                        HStack(spacing: 8) {
                            CheckCircle(done: i < done, color: .ink, size: 15)
                            Text([L("Poprawić slajdy"), L("Dorobić obrazki"), L("Wysłać do klienta")][i])
                                .font(.system(size: 12.5)).strikethrough(i < done).foregroundStyle(Color.ink.opacity(i < done ? 0.45 : 0.9))
                        }
                        .animation(.spring(response: 0.3), value: done)
                    }
                    HStack(spacing: 6) {
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.ink.opacity(0.14))
                                Capsule().fill(Color.ink.opacity(0.8)).frame(width: g.size.width * CGFloat(done) / 3)
                            }
                        }.frame(height: 3)
                        Text("\(done)/3").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.ink.opacity(0.7))
                    }
                    .animation(.spring(response: 0.4), value: done)
                }
                .padding(16)
                .frame(width: 230, height: 200, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: 14).fill(palette(4).bg).shadow(color: .black.opacity(0.3), radius: 10, y: 5))
            }
        }
    }
}

struct DemoReminder: View {
    var body: some View {
        Loop(period: 4) { t in
            let hop = t < 0.3 ? -sin(t / 0.3 * .pi * 2).magnitude * 22 * (1 - t / 0.3) : 0
            let banner = ease(t, 0.35, 0.45) - ease(t, 0.85, 0.95)
            ZStack {
                HStack(alignment: .top, spacing: 10) {
                    PriorityIcon(level: 3).frame(width: 26, height: 26)
                    Image(systemName: "bell.fill").font(.system(size: 12)).foregroundStyle(Color.ink.opacity(0.7))
                        .rotationEffect(.degrees(t < 0.3 ? sin(t * 60) * 18 : 0), anchor: .top)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("28").font(.system(size: 30))
                        Text(L("jutro")).font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(Color.ink))
                    }
                }
                .foregroundStyle(Color.ink)
                .padding(14)
                .frame(width: 170, height: 150, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: 12).fill(palette(2).bg).shadow(color: .black.opacity(0.3), radius: 8, y: 4))
                .offset(x: -70, y: 20 + hop)

                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 5).fill(palette(2).bg).frame(width: 22, height: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L("Jutro termin: Prezentacja")).font(.system(size: 11, weight: .semibold))
                        Text(L("Zostało zadań: 2 z 3.")).font(.system(size: 10)).opacity(0.6)
                    }
                }
                .foregroundStyle(Color.ink)
                .padding(10).frame(width: 220, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.95)))
                .offset(x: 120 + 260 * (1 - banner), y: 60)
                .opacity(banner)
            }
        }
    }
}

struct DemoFilter: View {
    var body: some View {
        Loop(period: 4.5) { t in
            let on = ease(t, 0.3, 0.4) - ease(t, 0.8, 0.9)
            VStack(spacing: 18) {
                HStack(spacing: 8) {
                    ForEach(Array(["Studio Nova", "Kawiarnia", "#logo"].enumerated()), id: \.offset) { i, n in
                        HStack(spacing: 4) {
                            if i < 2 { Circle().fill(i == 0 ? palette(5).bg : palette(7).bg).frame(width: 7, height: 7) }
                            Text(n).font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(i == 0 && on > 0.5 ? Color.ink : .white)
                        .padding(.horizontal, 10).frame(height: 24)
                        .background(Capsule().fill(i == 0 && on > 0.5 ? PriorityIcon.yellow : Color.white.opacity(0.12)))
                    }
                }
                HStack(spacing: 12) {
                    ForEach(0..<4, id: \.self) { i in
                        let match = i == 0 || i == 2
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 3) {
                                Circle().fill(match ? palette(5).bg : palette(7).bg).frame(width: 5, height: 5)
                                Text(match ? "STUDIO NOVA" : "KAWIARNIA").font(.system(size: 6.5, weight: .bold)).foregroundStyle(Color.ink.opacity(0.6))
                            }
                            MiniCard(color: DEMO_COLORS[i], lines: 2, w: 76, h: 80).shadow(radius: 0)
                        }
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 10).fill(DEMO_COLORS[i]))
                        .opacity(match ? 1 : 1 - on * 0.85)
                        .scaleEffect(match ? 1 : 1 - on * 0.08)
                    }
                }
            }
        }
    }
}

struct DemoCalendar: View {
    var body: some View {
        Loop(period: 4) { t in
            let p = ease(t, 0.05, 0.6)
            let segs: [[Color]] = [[palette(5).bg], [palette(5).bg, palette(7).bg], [], [palette(2).bg, palette(5).bg, palette(7).bg],
                                   [palette(7).bg], [], [palette(2).bg], [palette(5).bg, palette(2).bg], [], [palette(7).bg],
                                   [palette(5).bg], [palette(2).bg, palette(7).bg], [], [palette(5).bg]]
            HStack(spacing: 30) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(monthName(Calendar.current.component(.month, from: Date()))).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 6), count: 7), spacing: 6) {
                        ForEach(0..<14, id: \.self) { i in
                            ZStack {
                                Circle().fill(i == 9 ? PriorityIcon.purple : .white.opacity(0.08)).padding(4)
                                let n = Double(segs[i].count)
                                ForEach(Array(segs[i].enumerated()), id: \.offset) { k, c in
                                    let a = Double(k) / n, b = Double(k + 1) / n - (n > 1 ? 0.05 : 0)
                                    Circle().trim(from: a, to: a + (b - a) * p).stroke(c, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                        .rotationEffect(.degrees(-90)).padding(1.5)
                                }
                                Text("\(i + 10)").font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                            }
                            .frame(width: 30, height: 30)
                        }
                    }
                }
                ZStack {
                    Circle().stroke(.white.opacity(0.13), lineWidth: 12)
                    Circle().trim(from: 0, to: 0.68 * p).stroke(Color(hex: 0x9BE08F), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(68 * p))%").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white).monospacedDigit()
                }
                .frame(width: 96, height: 96)
            }
        }
    }
}

struct DemoTrash: View {
    var body: some View {
        Loop(period: 4.6) { t in
            // po usunięciu scena gaśnie i zaczyna od czystego stanu (4 karty w rzędzie)
            let restart = t >= 0.92
            let sceneOpacity = restart ? ease(t, 0.92, 1.0) : 1 - ease(t, 0.84, 0.92)
            let grab = restart ? 0 : ease(t, 0.04, 0.14)            // kursor dochodzi do karteczki
            let down = restart ? 0 : ease(t, 0.16, 0.5)
            let gone = restart ? 0 : ease(t, 0.52, 0.58)
            let close = restart ? 0 : ease(t, 0.58, 0.7)
            let bin = restart ? 0 : ease(t, 0.18, 0.26) * (1 - ease(t, 0.66, 0.74))
            let armed = down > 0.85
            let dx: CGFloat = 92, pick = 2
            let px = (CGFloat(pick) - 1.5) * dx
            ZStack {
                ForEach(0..<4, id: \.self) { i in
                    let base = (CGFloat(i) - 1.5) * dx - (i > pick ? dx * close : 0)
                    if i == pick {
                        MiniCard(color: DEMO_COLORS[i], lines: 3, w: 80, h: 100)
                            .scaleEffect(1.04 - 0.45 * down, anchor: .bottom)
                            .offset(x: base, y: -30 - 8 * grab + 96 * down)
                            .opacity(1 - gone)
                            .zIndex(1)
                    } else {
                        MiniCard(color: DEMO_COLORS[i], lines: 3, w: 80, h: 100)
                            .rotationEffect(.degrees(sin(Double(i) * 1.15) * 2))
                            .offset(x: base, y: -30 + CGFloat(sin(Double(i) * 1.15 + 0.9)) * 5)
                    }
                }
                ZStack {
                    Circle().fill(armed ? Color(hex: 0xD93A26) : Color.white.opacity(0.18))
                    BinIcon(open: armed ? 0 : 1 - down).frame(width: 20, height: 24).offset(y: 2)
                }
                .frame(width: 50, height: 50)
                .scaleEffect((armed ? 1.15 : 1) * (0.4 + 0.6 * bin))
                .offset(x: px, y: 80)
                .opacity(bin)
                .zIndex(2)
                Image(systemName: "cursorarrow").font(.system(size: 18)).foregroundStyle(.white).shadow(radius: 2)
                    .offset(x: -170 + (px + 6 + 170) * grab, y: 90 - 110 * grab + 96 * down)
                    .opacity(restart ? 0 : 1 - gone)
                    .zIndex(3)
            }
            .opacity(sceneOpacity)
        }
    }
}

struct DemoDictation: View {
    var body: some View {
        Loop(period: 6) { t in
            let full = L("Studio Nova poprawić slajdy dorobić obrazki wysłać do klienta")
            let typed = String(full.prefix(Int(Double(full.count) * ease(t, 0.05, 0.5))))
            let card = ease(t, 0.58, 0.7)
            ZStack {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle().fill(Color(hex: 0xD93A26).opacity(0.3)).scaleEffect(1 + 0.3 * abs(sin(t * 40)))
                            Circle().fill(Color(hex: 0xD93A26)).frame(width: 24, height: 24)
                            Image(systemName: "mic.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                        }
                        .frame(width: 30, height: 30)
                        Text(L("Słucham…")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                    }
                    Text(typed).font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                        .frame(width: 250, height: 40, alignment: .topLeading)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.08)))
                .opacity(1 - card)
                .scaleEffect(1 - 0.1 * card)

                VStack(alignment: .leading, spacing: 7) {
                    Text("Studio Nova").font(.system(size: 16, weight: .semibold))
                    ForEach([L("Poprawić slajdy"), L("Dorobić obrazki"), L("Wysłać do klienta")], id: \.self) { s in
                        HStack(spacing: 6) { CheckCircle(done: false, color: .ink, size: 12); Text(s).font(.system(size: 11.5)) }
                    }
                }
                .foregroundStyle(Color.ink)
                .padding(14)
                .frame(width: 200, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(palette(1).bg).shadow(color: .black.opacity(0.3), radius: 8, y: 4))
                .opacity(card)
                .scaleEffect(0.85 + 0.15 * card)
            }
        }
    }
}

// MARK: - Zgody systemowe

/// Strona „Zgody”: po co są i jaki mają stan; przycisk prosi system, skrót otwiera Ustawienia.
struct Permissions: View {
    @State private var notif = "?"
    @State private var mic = "?"
    @State private var speech = "?"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("Zgody")).font(.system(size: 24, weight: .semibold)).tracking(-0.5)
            Text(L("Stosik prosi tylko o to, czego potrzebuje. Możesz to zmienić w każdej chwili w Ustawieniach systemowych."))
                .font(.system(size: 12)).foregroundStyle(Color.ink.opacity(0.55)).fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 16)
            row("bell.fill", L("Powiadomienia"), L("Przypomnienia o terminach (dzwoneczek w karteczce)."), notif,
                ask: { Reminders.setup(); DispatchQueue.main.asyncAfter(deadline: .now() + 1) { refresh() } },
                settings: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
            row("mic.fill", L("Mikrofon"), L("Dyktowanie zadań. Stosik słucha tylko, gdy klikniesz mikrofon."), mic,
                ask: { AVCaptureDevice.requestAccess(for: .audio) { _ in DispatchQueue.main.async { refresh() } } },
                settings: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
            row("waveform", L("Rozpoznawanie mowy"), L("Zamienia podyktowany głos na tekst zadań."), speech,
                ask: { SFSpeechRecognizer.requestAuthorization { _ in DispatchQueue.main.async { refresh() } } },
                settings: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 26, leading: 26, bottom: 0, trailing: 26))
        .onAppear { refresh() }
    }

    private func refresh() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: mic = "ok"; case .denied, .restricted: mic = "no"; default: mic = "?"
        }
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: speech = "ok"; case .denied, .restricted: speech = "no"; default: speech = "?"
        }
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().getNotificationSettings { st in
            let v: String
            switch st.authorizationStatus { case .authorized, .provisional: v = "ok"; case .denied: v = "no"; default: v = "?" }
            DispatchQueue.main.async { notif = v }
        }
    }

    private func row(_ icon: String, _ title: String, _ why: String, _ state: String,
                     ask: @escaping () -> Void, settings: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 34, height: 34).background(RoundedRectangle(cornerRadius: 9).fill(Color.ink))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13.5, weight: .semibold))
                Text(why).font(.system(size: 11.5)).foregroundStyle(Color.ink.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if state == "ok" {
                Label(L("Włączone"), systemImage: "checkmark.circle.fill").font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x2E8A4C))
            } else if state == "no" {
                Button(L("Otwórz Ustawienia")) { if let u = URL(string: settings) { NSWorkspace.shared.open(u) } }
                    .buttonStyle(.plain).font(.system(size: 11.5, weight: .semibold))
                    .padding(.horizontal, 10).frame(height: 26).background(Capsule().fill(Color.ink.opacity(0.08)))
            } else {
                Button(L("Zezwól"), action: ask)
                    .buttonStyle(.plain).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 12).frame(height: 26).background(Capsule().fill(Color.ink))
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.ink.opacity(0.04)))
        .padding(.bottom, 8)
    }
}
