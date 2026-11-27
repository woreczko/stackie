import SwiftUI
import Speech
import AVFoundation
import UserNotifications

// MARK: - Okienko powitalne: strony z animacjami możliwości i historia zmian

let APP_VERSION = "1.4.1"

/// `since`: wersja, w której funkcja się pojawiła (po aktualizacji pokazujemy tylko nowsze strony).
struct WelcomePage { let title: String; let text: String; let demo: AnyView; var since = "1.0" }

struct WelcomeView: View {
    var close: () -> Void
    @State private var page: Int
    /// Po aktualizacji: tylko strony z funkcjami nowszymi niż ta wersja, bez zgód i historii zmian.
    var newSince: String?

    /// Strona „Co nowego” (po stronach z pokazami i zgodach).
    static var changelogPage: Int { WelcomeView(close: {}).pages.count + 1 }
    /// Czy po aktualizacji z tej wersji jest co pokazać.
    static func hasNew(since v: String) -> Bool { !WelcomeView(close: {}, newSince: v).pages.isEmpty }

    init(close: @escaping () -> Void, startPage: Int = 0, newSince: String? = nil) {
        self.close = close
        self.newSince = newSince
        _page = State(initialValue: startPage)
    }

    var pages: [WelcomePage] {
        guard let v = newSince else { return allPages }
        return allPages.filter { Updater.newer($0.since, than: v) }
    }

    private var allPages: [WelcomePage] {
        [
            WelcomePage(title: L("Witaj w Stosiku"), text: L("Karteczki leżą na pulpicie jak talia kart. Najedź myszką, a stos się rozłoży."), demo: AnyView(DemoStack())),
            WelcomePage(title: L("Projekty i zadania"), text: L("Jedna karteczka to jeden projekt. Odhaczasz kółeczka, a pasek pokazuje postęp. Zadania przesuwasz za uchwyt."), demo: AnyView(DemoTasks())),
            WelcomePage(title: L("Terminy i przypomnienia"), text: L("Data w rogu, pilność w kolorach. Dzwoneczek ustawia przypomnienia, a karteczka podskakuje, gdy termin jest blisko."), demo: AnyView(DemoReminder())),
            WelcomePage(title: L("Klienci, projekty i tagi"), text: L("Każda karteczka może mieć klienta, projekt i tagi. Kliknij jeden z nich, żeby zostawić w stosie tylko to, co do niego pasuje."), demo: AnyView(DemoFilter())),
            WelcomePage(title: L("Kalendarz i podsumowanie"), text: L("Szara karta na końcu stosu to kalendarz. Kółka dni pokazują, co się działo, a wykres, ile zostało."), demo: AnyView(DemoCalendar())),
            WelcomePage(title: L("Pliki przy karteczce"), text: L("Przeciągnij PDF, zdjęcie albo inny plik na otwartą karteczkę. Stosik trzyma kopię, więc nic nie zginie."), demo: AnyView(DemoFiles())),
            WelcomePage(title: L("Kosz na 30 dni"), text: L("Pociągnij karteczkę w dół, aż kosz zrobi się czerwony. Przez 30 dni możesz ją przywrócić."), demo: AnyView(DemoTrash())),
            WelcomePage(title: L("Dyktowanie"), text: L("Kliknij mikrofon i powiedz, co jest do zrobienia. Każdy czasownik zaczyna nowe zadanie, a „klient”, „projekt” i „tag” wypełniają pola."), demo: AnyView(DemoDictation())),
            WelcomePage(title: L("Na dziś"), text: L("Biała kartka na początku stosu zbiera wszystko z terminem na dziś, po klientach. Możesz ją przesunąć, rano wraca na pierwsze miejsce."), demo: AnyView(DemoToday()), since: "1.3"),
            WelcomePage(title: L("Zadania z notatki"), text: L("Piszesz szybko i bez ładu, np. przy telefonie. Kliknij ✨ „Zrób zadania”, a Claude ułoży z tego listę zadań z klientem i terminem. Najpierw zobaczysz propozycję."), demo: AnyView(DemoSmart()), since: "1.3"),
            WelcomePage(title: L("Szybka notatka z rogu"), text: L("Wjedź kursorem w róg ekranu i pisz albo dyktuj, na brudno. Potem zapisz albo kliknij ✨ „Zrób zadania”. Róg wybierasz w ustawieniach pod kółkiem zębatym."), demo: AnyView(DemoCorner()), since: "1.4.1"),
            WelcomePage(title: L("Przenieś albo skopiuj zadanie"), text: L("Najedź na zadanie i kliknij strzałkę obok krzyżyka. Wybierz karteczkę z listy, a zadanie przejdzie tam albo trafi do obu."), demo: AnyView(DemoMove()), since: "1.4.1"),
            WelcomePage(title: L("Rozmiar stosu"), text: L("Mały ekran? W ustawieniach pod kółkiem zębatym zmniejszysz stos albo przełączysz się na małe karteczki: sam tytuł, data i licznik."), demo: AnyView(DemoSizes()), since: "1.3"),
        ]
    }

    var body: some View {
        let all = newSince == nil ? pages.count + 2 : pages.count
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
    Release(version: "1.4.1", date: "27.11.2026", items: [
        L("Szybka notatka z rogu ekranu: pisz albo dyktuj, zapisz na brudno albo zrób z tego zadania"),
        L("Przenieś albo skopiuj zadanie na inną karteczkę"),
        L("Kopiuj, wklej i cofnij (⌘C, ⌘V, ⌘Z) działają w polach tekstowych"),
        L("Enter w zadaniu dodaje następne; „Dodaj zadanie” trzyma się dołu przy długiej liście"),
        L("Termin w jednej linii z rozwijanym „Kiedy”; klient, projekt i tagi jako pastylki"),
    ]),
    Release(version: "1.4", date: "27.11.2026", items: [
        L("Sprawdź aktualizacje z palca: w ustawieniach pod zębatką albo w menu w pasku"),
        L("Samoczynne sprawdzanie przy starcie oraz o 10:37 i 21:37"),
        L("Nad przyciskami paska zwykła strzałka zamiast rączki"),
    ]),
    Release(version: "1.3", date: "27.11.2026", items: [
        L("Kartka „Na dziś”: wszystko z terminem na dziś, po klientach i projektach; wraca rano na początek stosu"),
        L("Rozmiar stosu: duży, średni albo mały, i małe karteczki (tytuł, data, licznik)"),
        L("Długie zadania zawijają się w edytorze"),
        L("„Zrób zadania”: Claude zamienia chaotyczną notatkę na zadania z klientem i terminem"),
        L("Nowa karteczka z rogu ekranu (do wyboru w ustawieniach)"),
        L("Złożony stos pokazuje tylko trzy karty: Na dziś, karteczkę i kalendarz"),
        L("Ustawienia jako pastylki"),
    ]),
    Release(version: "1.2", date: "27.11.2026", items: [
        L("Samoczynne aktualizacje: raz dziennie Stackie sprawdza nową wersję i instaluje ją, gdy nie używasz komputera"),
        L("Wyłącznik w menu w pasku: Ustawienia → Aktualizuj automatycznie"),
    ]),
    Release(version: "1.1", date: "27.11.2026", items: [
        L("Pliki przy karteczce: przeciągnij PDF, zdjęcie albo inny plik, Stosik trzyma kopię"),
        L("Data i godzina terminu jako pigułki z kalendarzem"),
        L("Przycisk OK na dole karteczki (albo Cmd+Enter)"),
        L("Menu w pasku podzielone na sekcje, z ikonkami"),
        L("Pasek pod pierwszą karteczką, mniejszy krzyżyk, powitanie z prawdziwymi karteczkami"),
    ]),
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

/// Prawdziwa karteczka ze stosu, pomniejszona (żeby pokaz wyglądał jak apka).
struct DemoCard: View {
    var note: Note
    var scale: CGFloat
    var body: some View {
        CardView(note: .constant(note))
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: StackLayout.fullW * scale, height: StackLayout.fullH * scale, alignment: .topLeading)
            .allowsHitTesting(false)
    }
}

/// Karteczka do pokazu: kolor, tytuł, zadania (ile odhaczonych), klient, projekt, tag, pilność, termin za ile dni.
func demoNote(_ color: Int, _ title: String, _ tasks: [String], done: Int = 0, client: String = "", project: String = "",
              tags: [String] = [], priority: Int = 0, due: Int? = nil, alerts: [Int] = []) -> Note {
    var n = Note()
    n.color = color; n.title = title; n.client = client; n.project = project; n.tags = tags; n.priority = priority
    n.tasks = tasks.enumerated().map { TaskItem(text: $0.element, done: $0.offset < done) }
    if let due { n.deadline = Calendar.current.date(byAdding: .day, value: due, to: Calendar.current.startOfDay(for: Date())) }
    n.alerts = alerts
    return n
}

/// Szara karta kalendarza na końcu stosu (w małej wersji).
struct MiniCalendarCard: View {
    var w: CGFloat, h: CGFloat
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(monthName(Calendar.current.component(.month, from: Date())))
                .font(.system(size: w * 0.085, weight: .semibold)).foregroundStyle(Color.ink)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 3) {
                ForEach(0..<28, id: \.self) { i in
                    Circle().fill(i == 19 ? PriorityIcon.purple : Color.ink.opacity(0.1)).frame(width: w * 0.055, height: w * 0.055)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(w * 0.08)
        .frame(width: w, height: h, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: w * 0.07, style: .continuous).fill(CAL_GREY))
    }
}

let DEMO_NOTES: [Note] = [
    demoNote(2, L("Prezentacja dla klienta"), [L("Poprawić slajdy"), L("Dorobić obrazki"), L("Wysłać do klienta")], done: 1,
             client: "Studio Nova", project: "Branding", tags: ["design"], priority: 3, due: 1, alerts: [1440]),
    demoNote(1, L("Pomysły na weekend"), [L("Rower"), L("Kino")], tags: [L("pomysły")], priority: 1),
    demoNote(3, L("Zakupy"), [L("Chleb"), L("Kawa"), L("Baterie AA")], done: 1, tags: [L("dom")]),
    demoNote(6, L("Klient: kawiarnia"), [L("Pierwszy krok")], client: L("Kawiarnia Róża"), project: L("Menu")),
]


struct DemoStack: View {
    var body: some View {
        Loop(period: 4) { t in
            let s = ease(t, 0.15, 0.35) - ease(t, 0.7, 0.9)   // rozkładanie i składanie
            ZStack {
                ForEach((0..<5).reversed(), id: \.self) { i in
                    let tight = -40 + CGFloat(i) * 12, wide = (CGFloat(i) - 2) * 100
                    let x = tight + (wide - tight) * s
                    let ang = (i % 2 == 0 ? -3.2 : 3.6) * (1 - s)
                    Group {
                        if i < 4 { DemoCard(note: DEMO_NOTES[i], scale: 0.44) } else { MiniCalendarCard(w: 92, h: 115) }
                    }
                    .shadow(color: .black.opacity(0.25), radius: 5, y: 3)
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
            DemoCard(note: demoNote(4, L("Prezentacja"), [L("Poprawić slajdy"), L("Dorobić obrazki"), L("Wysłać do klienta")],
                                    done: done, client: "Studio Nova", project: "Branding", priority: 2), scale: 0.88)
                .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
                .animation(.spring(response: 0.3), value: done)
        }
    }
}

struct DemoReminder: View {
    var body: some View {
        Loop(period: 4) { t in
            let hop = t < 0.3 ? -sin(t / 0.3 * .pi * 2).magnitude * 22 * (1 - t / 0.3) : 0
            let banner = ease(t, 0.35, 0.45) - ease(t, 0.85, 0.95)
            ZStack {
                DemoCard(note: demoNote(2, L("Prezentacja dla klienta"), [L("Poprawić slajdy"), L("Dorobić obrazki"), L("Wysłać do klienta")],
                                        done: 1, client: "Studio Nova", project: "Branding", priority: 3, due: 1, alerts: [1440]), scale: 0.72)
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                .offset(x: -80, y: 8 + hop)

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
                        DemoCard(note: demoNote([2, 1, 4, 6][i], [L("Prezentacja"), L("Ulotka"), L("Logo"), L("Menu")][i],
                                                [L("Pierwszy krok"), L("Drugi krok")], done: i == 0 ? 1 : 0,
                                                client: match ? "Studio Nova" : L("Kawiarnia")), scale: 0.4)
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

struct DemoFiles: View {
    var body: some View {
        Loop(period: 4.4) { t in
            let fly1 = ease(t, 0.1, 0.35), fly2 = ease(t, 0.42, 0.67)
            let out = ease(t, 0.9, 1.0)
            let n = (fly1 > 0.98 ? 1 : 0) + (fly2 > 0.98 ? 1 : 0)
            let note = withFiles(demoNote(5, L("Prezentacja"), [L("Poprawić slajdy"), L("Wysłać do klienta")], client: "Studio Nova"), n)
            ZStack {
                DemoCard(note: note, scale: 0.72)
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                    .offset(x: -60)
                fileIcon("doc.richtext.fill", "PDF")
                    .offset(x: 150 - 210 * fly1, y: -40 + 40 * fly1)
                    .scaleEffect(1 - 0.5 * fly1).opacity(1 - ease(t, 0.3, 0.36))
                fileIcon("photo.fill", "JPG")
                    .offset(x: 150 - 210 * fly2, y: 40 - 30 * fly2)
                    .scaleEffect(1 - 0.5 * fly2).opacity(fly1 > 0.5 ? 1 - ease(t, 0.62, 0.68) : 0)
                Image(systemName: "cursorarrow").font(.system(size: 18)).foregroundStyle(.white).shadow(radius: 2)
                    .offset(x: 165 - 210 * (fly1 < 1 ? fly1 : fly2), y: (fly1 < 1 ? -25 + 40 * fly1 : 55 - 30 * fly2))
            }
            .opacity(1 - out)
        }
    }

    private func withFiles(_ n: Note, _ count: Int) -> Note {
        var n = n; n.files = (0..<count).map { _ in Attachment(name: "plik") }; return n
    }

    private func fileIcon(_ sym: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: sym).font(.system(size: 30)).foregroundStyle(.white.opacity(0.9))
            Text(label).font(.system(size: 9, weight: .bold)).tracking(0.6).foregroundStyle(.white.opacity(0.6))
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
                        DemoCard(note: DEMO_NOTES[i], scale: 0.38)
                            .scaleEffect(1.04 - 0.45 * down, anchor: .bottom)
                            .offset(x: base, y: -30 - 8 * grab + 96 * down)
                            .opacity(1 - gone)
                            .zIndex(1)
                    } else {
                        DemoCard(note: DEMO_NOTES[i], scale: 0.38)
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

                DemoCard(note: demoNote(1, "Studio Nova", [L("Poprawić slajdy"), L("Dorobić obrazki"), L("Wysłać do klienta")]), scale: 0.8)
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
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


// MARK: - Pokazy z 1.3

/// Kartka „Na dziś”: klienci dopisują się po kolei, potem jedno zadanie zostaje odhaczone.
struct DemoToday: View {
    var body: some View {
        Loop(period: 5.0) { t in
            let n = t < 0.18 ? 0 : t < 0.32 ? 1 : t < 0.46 ? 2 : 3
            let done = t > 0.66 ? 1 : 0
            let groups = Array([
                TodayGroup(key: "c:a", name: "Studio Nova", client: "Studio Nova", project: "", open: 3 - done, total: 3,
                           notes: [UUID(), UUID()], projects: [(L("Logo"), 2 - done), (L("Ulotki"), 1)]),
                TodayGroup(key: "c:b", name: "Kawiarnia Róża", client: "Kawiarnia Róża", project: "", open: 2, total: 2, notes: [UUID()]),
                TodayGroup(key: "t:c", name: L("Zakupy"), client: "", project: "", open: 2, total: 3, notes: [UUID()]),
            ].prefix(n))
            ZStack {
                ForEach(0..<2) { i in
                    DemoCard(note: DEMO_NOTES[i + 1], scale: 0.62)
                        .rotationEffect(.degrees(i == 0 ? 3.6 : -2))
                        .offset(x: 40 + CGFloat(i) * 26, y: -6 - CGFloat(i) * 4)
                }
                TodayCard(groups: groups)
                    .scaleEffect(0.78)
                    .frame(width: StackLayout.fullW * 0.78, height: StackLayout.fullH * 0.78)
                    .rotationEffect(.degrees(-2.5))
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                    .offset(x: -40)
            }
            .opacity(1 - ease(t, 0.92, 1.0))
        }
    }
}

/// Ten sam stos w trzech rozmiarach, a na koniec małe karteczki; pod spodem pastylka z nazwą.
struct DemoSizes: View {
    var body: some View {
        Loop(period: 6.0) { t in
            let step = min(Int(t * 4), 3)
            let scales: [CGFloat] = [1, 0.85, 0.7, 1]
            let names = [L("Duży"), L("Średni"), L("Mały"), L("Małe karteczki")]
            let k = step == 3 ? 0.85 : scales[step] * 0.62
            VStack(spacing: 14) {
                ZStack(alignment: .topLeading) {
                    ForEach((0..<3).reversed(), id: \.self) { i in
                        Group {
                            if step == 3 { CardView(note: .constant(DEMO_NOTES[i]), mini: true) }
                            else { CardView(note: .constant(DEMO_NOTES[i])) }
                        }
                        .rotationEffect(.degrees(i % 2 == 0 ? -3 : 3.5))
                        .offset(x: CGFloat(i) * 26, y: -CGFloat(i) * 4)
                    }
                }
                .scaleEffect(k, anchor: .bottom)
                .frame(width: 320, height: 190, alignment: .bottom)
                .animation(.spring(response: 0.45, dampingFraction: 0.8), value: step)
                HStack(spacing: 6) {
                    ForEach(0..<4) { i in
                        Text(names[i]).font(.system(size: 11, weight: i == step ? .semibold : .medium))
                            .foregroundStyle(i == step ? Color.ink : .white.opacity(0.7))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Capsule().fill(i == step ? Color.white : .white.opacity(0.12)))
                    }
                }
            }
        }
    }
}


/// Kursor jedzie w lewy dolny róg ekranu, róg się podświetla i wyskakuje pusta karteczka.
struct DemoCorner: View {
    var body: some View {
        Loop(period: 6.0) { t in
            let go = ease(t, 0.03, 0.25), pop = ease(t, 0.3, 0.4), out = ease(t, 0.92, 1.0)
            let full = L("Beata dzwoniła, reklama do ELLE na piątek!! logo od Kampa")
            let typed = String(full.prefix(Int(Double(full.count) * ease(t, 0.42, 0.78))))
            let press = ease(t, 0.8, 0.84) * (1 - ease(t, 0.86, 0.9))
            ZStack {
                // ekran
                RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.25), lineWidth: 1.5)
                    .frame(width: 360, height: 210)
                // podświetlony róg
                Circle().fill(Color(hex: 0x9BE08F).opacity(0.55 * ease(t, 0.22, 0.28) * (1 - pop * 0.6)))
                    .frame(width: 46, height: 46).blur(radius: 8)
                    .offset(x: -180, y: 105)
                // okienko szybkiej notatki na środku
                VStack(alignment: .leading, spacing: 7) {
                    Text(L("Szybka notatka")).font(.system(size: 7.5, weight: .bold)).tracking(0.6).textCase(.uppercase)
                        .foregroundStyle(Color.ink.opacity(0.5))
                    Text(typed).font(.system(size: 10.5)).foregroundStyle(Color.ink.opacity(0.85))
                        .frame(width: 236, height: 46, alignment: .topLeading)
                    HStack(spacing: 5) {
                        Label(L("Dyktuj"), systemImage: "mic.fill").font(.system(size: 8, weight: .semibold)).lineLimit(1).fixedSize()
                            .padding(.horizontal, 7).padding(.vertical, 4).background(Capsule().fill(Color.ink.opacity(0.08)))
                        Spacer()
                        Text(L("Zapisz na brudno")).font(.system(size: 8, weight: .semibold)).lineLimit(1).fixedSize()
                            .padding(.horizontal, 7).padding(.vertical, 4).background(Capsule().fill(Color.ink.opacity(0.08)))
                        HStack(spacing: 3) { Image(systemName: "sparkles"); Text(L("Zrób zadania")) }.lineLimit(1).fixedSize()
                            .font(.system(size: 8, weight: .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(Color.ink))
                            .scaleEffect(1 + 0.12 * press)
                            .shadow(color: Color(hex: 0x8B7CF6).opacity(0.9 * press), radius: 8)
                    }
                    .foregroundStyle(Color.ink)
                }
                .padding(11)
                .frame(width: 260)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: 0xF7F1E7)))
                .shadow(color: .black.opacity(0.35), radius: 10, y: 5)
                .scaleEffect(0.7 + 0.3 * pop).opacity(pop)
                Image(systemName: "cursorarrow").font(.system(size: 20)).foregroundStyle(.white).shadow(radius: 2)
                    .offset(x: 80 - 254 * go, y: -30 + 132 * go)
                    .opacity(1 - pop)
            }
            .opacity(1 - out)
        }
    }
}

/// Zadanie wychodzi z jednej karteczki i ląduje na drugiej.
struct DemoMove: View {
    var body: some View {
        Loop(period: 5.0) { t in
            let menu = ease(t, 0.12, 0.2) * (1 - ease(t, 0.32, 0.36))
            let fly = ease(t, 0.36, 0.62), landed = t > 0.62, gone = t > 0.36
            let task = L("Wysłać fakturę")
            ZStack {
                HStack(spacing: 60) {
                    DemoCard(note: demoNote(6, L("Faktury"), gone ? [L("Zebrać paragony")] : [L("Zebrać paragony"), task],
                                            client: "Studio Nova"), scale: 0.74)
                        .shadow(color: .black.opacity(0.3), radius: 8, y: 4).rotationEffect(.degrees(-2))
                    DemoCard(note: demoNote(2, L("Na piątek"), landed ? [L("Zadzwonić do drukarni"), task] : [L("Zadzwonić do drukarni")],
                                            client: "Studio Nova"), scale: 0.74)
                        .shadow(color: .black.opacity(0.3), radius: 8, y: 4).rotationEffect(.degrees(2.5))
                }
                // menu przy zadaniu
                Text(L("Przenieś na inną karteczkę…")).font(.system(size: 9, weight: .medium)).foregroundStyle(Color.ink)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.white))
                    .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                    .opacity(menu).scaleEffect(0.9 + 0.1 * menu)
                    .offset(x: -40, y: 40)
                // lecące zadanie
                HStack(spacing: 5) {
                    Circle().strokeBorder(Color.ink.opacity(0.6), lineWidth: 1.2).frame(width: 9, height: 9)
                    Text(task).font(.system(size: 9.5, weight: .medium)).foregroundStyle(Color.ink)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(.white))
                .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
                .offset(x: -110 + 230 * fly, y: 12 - 50 * sin(fly * .pi))
                .opacity(t > 0.34 && !landed ? 1 : 0)
            }
            .opacity(1 - ease(t, 0.93, 1.0))
        }
    }
}


/// Chaotyczna notatka pisze się sama, ✨ „Zrób zadania” błyska, a obok wyrasta karteczka z zadaniami.
struct DemoSmart: View {
    var body: some View {
        Loop(period: 7.0) { t in
            let full = L("Beata dzwoniła, reklama do ELLE na piątek!! logo od Kampa, faktura Figure… drukarnia jutro rano")
            let typed = String(full.prefix(Int(Double(full.count) * ease(t, 0.04, 0.34))))
            let press = ease(t, 0.38, 0.42) * (1 - ease(t, 0.44, 0.5))
            let card = ease(t, 0.5, 0.6)
            let tasks = [L("Dokończyć reklamę do piątku"), L("Ogarnąć logo od Kampa"), L("Wysłać fakturę do Figure"), L("Zadzwonić do drukarni")]
            let n = t < 0.6 ? 0 : min(tasks.count, Int((t - 0.6) / 0.05) + 1)
            HStack(spacing: 26) {
                // notatka pisana na szybko
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(L("Notatka")).font(.system(size: 9, weight: .bold)).tracking(0.7).textCase(.uppercase)
                            .foregroundStyle(Color.ink.opacity(0.55))
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles").font(.system(size: 8.5, weight: .bold))
                            Text(L("Zrób zadania")).font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(Color.ink.opacity(0.6 + 0.4 * press))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(Color(hex: 0x8B7CF6).opacity(0.15 + 0.5 * press)))
                        .scaleEffect(1 + 0.12 * press)
                        .shadow(color: Color(hex: 0x8B7CF6).opacity(0.8 * press), radius: 8)
                    }
                    Text(typed).font(.system(size: 12.5, design: .rounded)).foregroundStyle(Color.ink.opacity(0.85))
                        .frame(width: 180, height: 110, alignment: .topLeading)
                }
                .padding(12)
                .frame(width: 210)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: 0xF7F1E7)))
                .rotationEffect(.degrees(-2))
                // karteczka z zadaniami
                DemoCard(note: demoNote(3, L("Reklama ELLE"), Array(tasks.prefix(n)), client: "ELLE", due: 7), scale: 0.78)
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                    .rotationEffect(.degrees(2.5))
                    .opacity(card).scaleEffect(0.85 + 0.15 * card)
                    .overlay(alignment: .topLeading) {
                        Image(systemName: "sparkles").font(.system(size: 18, weight: .bold)).foregroundStyle(Color(hex: 0xC9BEFF))
                            .opacity(card * (1 - ease(t, 0.75, 0.85))).offset(x: -10, y: -10)
                    }
            }
            .opacity(1 - ease(t, 0.93, 1.0))
        }
    }
}
