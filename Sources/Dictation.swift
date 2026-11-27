import SwiftUI
import Speech
import AVFoundation

/// Dyktowanie: rozpoznawanie mowy macOS (po polsku albo angielsku, zależnie od języka apki).
final class Dictation: ObservableObject {
    static let shared = Dictation()
    @Published var text = ""
    @Published var recording = false
    @Published var level: CGFloat = 0
    @Published var error: String?

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func start() {
        text = ""; error = nil; level = 0
        SFSpeechRecognizer.requestAuthorization { st in
            DispatchQueue.main.async {
                guard st == .authorized else {
                    self.error = L("Brak zgody na rozpoznawanie mowy. Włącz ją w Ustawieniach systemowych → Prywatność → Rozpoznawanie mowy.")
                    return
                }
                AVCaptureDevice.requestAccess(for: .audio) { ok in
                    DispatchQueue.main.async {
                        if ok { self.begin() } else { self.error = L("Brak dostępu do mikrofonu. Włącz go w Ustawieniach systemowych → Prywatność → Mikrofon.") }
                    }
                }
            }
        }
    }

    private func begin() {
        let loc = Locale(identifier: Lang.current == "pl" ? "pl-PL" : "en-US")
        guard let rec = SFSpeechRecognizer(locale: loc), rec.isAvailable else {
            error = L("Rozpoznawanie mowy jest teraz niedostępne."); return
        }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.addsPunctuation = true
        request = req
        let input = engine.inputNode
        let fmt = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buf, _ in
            req.append(buf)
            guard let ch = buf.floatChannelData?[0] else { return }
            let n = Int(buf.frameLength); var sum: Float = 0
            for i in 0..<n { sum += ch[i] * ch[i] }
            let rms = sqrt(sum / Float(max(n, 1)))
            DispatchQueue.main.async { self?.level = min(1, CGFloat(rms) * 14) }
        }
        engine.prepare()
        do { try engine.start() } catch { self.error = L("Nie udało się włączyć mikrofonu."); return }
        recording = true
        task = rec.recognitionTask(with: req) { [weak self] res, err in
            DispatchQueue.main.async {
                if let res { self?.text = res.bestTranscription.formattedString }
                if err != nil || (res?.isFinal ?? false) { self?.stopAudio() }
            }
        }
    }

    /// Kończy nagrywanie; po chwili (ostatnie słowa) oddaje tekst.
    func finish(_ done: @escaping (String) -> Void) {
        request?.endAudio()
        stopAudio()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            let t = self.text
            self.task?.cancel(); self.task = nil; self.request = nil
            done(t)
        }
    }

    func cancel() {
        task?.cancel(); task = nil
        request = nil
        stopAudio()
        text = ""
    }

    private func stopAudio() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        recording = false; level = 0
    }
}

/// Wynik dyktowania: klient, projekt, tagi (gdy padły słowa-klucze), tekst przed pierwszym zadaniem i zadania.
struct DictationResult: Equatable {
    var client = ""
    var project = ""
    var tags: [String] = []
    var lead = ""
    var tasks: [String] = []
    /// Termin z głosu: „do dwunastej”, „jutro”, „pojutrze”, „dziś do 15”.
    var deadline: Date? = nil
    var hasTime = false
}

private let CLIENT_KW: Set<String> = ["klient", "klienta", "klientka", "client"]
private let PROJECT_KW: Set<String> = ["projekt", "projektu", "project"]
private let TAG_KW: Set<String> = ["tag", "tagi", "tagu", "tags"]
private let GLUE: Set<String> = ["i", "oraz", "a", "potem", "następnie", "później", "jeszcze", "na", "koniec", "końcu",
    "najpierw", "też", "także", "początek", "początku", "and", "then", "finally", "also"]
/// „do dwunastej” → 12
private let HOURS: [String: Int] = ["pierwszej": 1, "drugiej": 2, "trzeciej": 3, "czwartej": 4, "piątej": 5, "szóstej": 6, "siódmej": 7,
    "ósmej": 8, "dziewiątej": 9, "dziesiątej": 10, "jedenastej": 11, "dwunastej": 12, "trzynastej": 13, "czternastej": 14,
    "piętnastej": 15, "szesnastej": 16, "siedemnastej": 17, "osiemnastej": 18, "dziewiętnastej": 19, "dwudziestej": 20]
/// Bezokoliczniki na -ść/-źć i -c, które są czasownikami (reszta na -ść to zwykle rzeczowniki: część, jakość).
private let SC_VERBS: Set<String> = ["iść", "pójść", "wyjść", "przyjść", "dojść", "wejść", "zejść", "odejść", "przejść", "obejść",
    "nieść", "przynieść", "zanieść", "wynieść", "donieść", "jeść", "zjeść", "kraść", "usiąść", "siąść", "znaleźć", "wleźć", "zleźć"]
private let C_VERBS: Set<String> = ["móc", "pomóc", "piec", "upiec", "biec", "pobiec", "przebiec", "strzyc", "ostrzyc", "zaprzec", "wlec"]
private let NOT_VERBS: Set<String> = ["pamięć", "sieć", "śmierć", "nić", "maść", "płeć", "ćwierć", "część", "ość", "kość", "teść", "gość", "boleść"]

/// Polski bezokolicznik: „poprawić”, „wysłać”, „iść”, „móc” (od niego zaczyna się nowe zadanie).
func isInfinitive(_ w: String) -> Bool {
    let x = w.lowercased()
    if NOT_VERBS.contains(x) { return false }
    if C_VERBS.contains(x) || SC_VERBS.contains(x) { return true }
    guard x.count > 2, x.hasSuffix("ć") else { return false }
    if x.hasSuffix("ść") { return false }
    return true
}

/// Dzieli podyktowany tekst bez polegania na kropkach: nowe zadanie zaczyna się od bezokolicznika,
/// kropka albo „potem” też dzieli; „klient …”, „projekt …”, „tag …” wypełniają pola.
func parseDictation(_ text: String) -> DictationResult {
    var r = DictationResult()
    enum Kind { case lead, task, client, project, tag }
    var kind = Kind.lead
    var cur: [String] = []

    func cap(_ t: String) -> String { t.isEmpty ? t : t.prefix(1).uppercased() + t.dropFirst() }
    func flush() {
        while let l = cur.last, GLUE.contains(l.lowercased()) { cur.removeLast() }
        let t = cur.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        cur = []
        guard !t.isEmpty else { return }
        switch kind {
        case .lead: r.lead = r.lead.isEmpty ? cap(t) : r.lead + " " + t
        case .task: r.tasks.append(cap(t))
        case .client: r.client = cap(t)
        case .project: r.project = cap(t)
        case .tag:
            for x in t.components(separatedBy: CharacterSet(charactersIn: ",")).flatMap({ $0.components(separatedBy: " i ") }) {
                let v = cleanTag(x); if !v.isEmpty { r.tags.append(v) }
            }
        }
    }

    // termin: dzień i godzina (zostają w tekście zadania, ustawiają termin karteczki)
    let low = text.lowercased()
    let cal = Calendar.current
    var day: Date? = nil
    if low.contains("pojutrze") { day = cal.date(byAdding: .day, value: 2, to: cal.startOfDay(for: Date())) }
    else if low.contains("jutro") || low.contains("tomorrow") { day = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) }
    else if low.contains("dziś") || low.contains("dzisiaj") || low.contains("today") { day = cal.startOfDay(for: Date()) }
    var hour: Int? = nil, minute = 0
    let tokens = low.split(whereSeparator: { " ,.;!?".contains($0) }).map(String.init)
    for (i, t) in tokens.enumerated() where ["do", "o", "na", "by", "at"].contains(t) && i + 1 < tokens.count {
        let nx = tokens[i + 1]
        if let h = HOURS[nx] { hour = h; if i + 2 < tokens.count, tokens[i + 2] == "trzydzieści" { minute = 30 } ; break }
        let parts = nx.split(separator: ":")
        if let h = Int(parts[0]), (1...23).contains(h), nx.allSatisfy({ $0.isNumber || $0 == ":" }) {
            hour = h; if parts.count > 1, let m = Int(parts[1]) { minute = m }; break
        }
    }
    if let hour {
        var d = day ?? cal.startOfDay(for: Date())
        d = cal.date(bySettingHour: hour, minute: minute, second: 0, of: d) ?? d
        if day == nil, d < Date() { d = cal.date(byAdding: .day, value: 1, to: d) ?? d }
        r.deadline = d; r.hasTime = true
    } else if let day { r.deadline = day }

    // separatory zdań zamieniamy na osobny znak
    var spaced = text
    for ch in [".", "!", "?", ";", "\n"] { spaced = spaced.replacingOccurrences(of: ch, with: " | ") }
    let words = spaced.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
    for raw in words {
        if raw == "|" { flush(); kind = .task; continue }
        let w = raw.trimmingCharacters(in: CharacterSet(charactersIn: ",:"))
        guard !w.isEmpty else { continue }
        let lw = w.lowercased()
        if CLIENT_KW.contains(lw) && kind != .task || lw == "klient" { flush(); kind = .client; continue }
        if PROJECT_KW.contains(lw) && kind != .task || lw == "projekt" { flush(); kind = .project; continue }
        if TAG_KW.contains(lw) { flush(); kind = .tag; continue }
        if ["potem", "następnie", "then"].contains(lw) { flush(); kind = .task; continue }
        if isInfinitive(w) {
            // „iść kupić chleb”: czasownik zaraz po czasowniku zostaje w tym samym zadaniu
            let onlyVerbSoFar = kind == .task && cur.count == 1 && isInfinitive(cur[0])
            if !onlyVerbSoFar { flush(); kind = .task }
        }
        cur.append(w)
        if raw.hasSuffix(",") && kind != .tag && kind != .lead && cur.count > 1 { /* przecinek nie dzieli */ }
    }
    flush()
    // sam termin na początku („jutro o 9:30 zadzwonić…”) nie jest tytułem
    if !r.lead.isEmpty {
        let timeWords: Set<String> = ["jutro", "pojutrze", "dziś", "dzisiaj", "do", "o", "na", "rano", "wieczorem", "po", "południu",
                                      "tomorrow", "today", "at", "by", "trzydzieści"]
        let rest = r.lead.lowercased().split(separator: " ").map(String.init).filter { w in
            !(timeWords.contains(w) || HOURS[w] != nil || w.allSatisfy { $0.isNumber || $0 == ":" })
        }
        if rest.isEmpty { r.lead = "" }
    }
    return r
}

/// Okienko dyktowania: tekst na żywo, poziom głosu, Gotowe i Anuluj.
struct DictationView: View {
    @ObservedObject var d = Dictation.shared
    var hint: String
    var done: () -> Void
    var cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Color(hex: 0xD93A26).opacity(0.25)).scaleEffect(1 + d.level * 0.8)
                    Circle().fill(d.recording ? Color(hex: 0xD93A26) : Color.white.opacity(0.2)).frame(width: 30, height: 30)
                    Image(systemName: "mic.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                }
                .frame(width: 38, height: 38)
                .animation(.easeOut(duration: 0.1), value: d.level)
                Text(d.recording ? L("Słucham…") : (d.error == nil ? L("Włączam mikrofon…") : L("Dyktowanie")))
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                Spacer()
            }
            if let e = d.error {
                Text(e).font(.system(size: 12)).foregroundStyle(Color(hex: 0xFFB4A8)).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(d.text.isEmpty ? hint : d.text)
                    .font(.system(size: 15, weight: d.text.isEmpty ? .regular : .medium))
                    .foregroundStyle(.white.opacity(d.text.isEmpty ? 0.45 : 1))
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button(L("Anuluj"), action: cancel).buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(action: done) {
                    Text(L("Gotowe")).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.ink)
                        .padding(.horizontal, 14).frame(height: 26).background(Capsule().fill(.white))
                }
                .buttonStyle(.plain).keyboardShortcut(.defaultAction)
                .disabled(d.error != nil)
            }
        }
        .padding(16)
        .frame(width: 360)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(hex: 0x1F1E23).opacity(0.94)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.12)))
    }
}
