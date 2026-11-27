import SwiftUI

/// Szybka notatka (róg ekranu): jedno pole, pisanie albo dyktowanie,
/// potem „Zapisz na brudno” (do rozpisania później) albo ✨ „Zrób zadania” (Claude dzieli na zadania i dopasowuje klienta).
struct QuickNoteView: View {
    var close: () -> Void
    /// Tekst na start (zrzuty do sprawdzania).
    var initial = ""
    @ObservedObject private var dict = Dictation.shared
    @State private var text = ""
    @State private var busy = false
    @State private var proposal: SmartProposal?
    @State private var pick: Set<Int> = []
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L("Szybka notatka")).font(.system(size: 11, weight: .bold)).tracking(0.8).textCase(.uppercase)
                    .foregroundStyle(Color.ink.opacity(0.5))
                Spacer()
                Button(action: cancel) {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(Color.ink.opacity(0.55))
                        .frame(width: 18, height: 18).background(Circle().fill(Color.ink.opacity(0.08)))
                }
                .buttonStyle(.plain).keyboardShortcut(.cancelAction)
            }
            if let p = proposal { proposalView(p) } else { editor }
        }
        .padding(18)
        .frame(width: 460, height: 320, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(hex: 0xF7F1E7)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.black.opacity(0.1)))
        .foregroundStyle(Color.ink)
        .onAppear { focused = true; if text.isEmpty { text = initial } }
    }

    // MARK: pisanie i dyktowanie

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty && !dict.recording {
                    Text(L("Co masz w głowie? Pisz albo dyktuj, na brudno. Potem zapiszesz albo zrobisz z tego zadania."))
                        .font(.system(size: 15)).foregroundStyle(Color.ink.opacity(0.35))
                        .padding(.top, 1).padding(.leading, 5).allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .font(.system(size: 15)).scrollContentBackground(.hidden)
                    .focused($focused)
            }
            if dict.recording {
                HStack(alignment: .top, spacing: 6) {
                    Circle().fill(Color(hex: 0xD93A26)).frame(width: 8, height: 8).padding(.top, 5)
                    Text(dict.text.isEmpty ? L("Słucham…") : dict.text).font(.system(size: 13)).foregroundStyle(Color.ink.opacity(0.6))
                        .lineLimit(3)
                }
            }
            if let error {
                Text(error).font(.system(size: 12)).foregroundStyle(Color(hex: 0xC4281B))
            }
            HStack(spacing: 8) {
                Button(action: toggleDictation) {
                    Label(dict.recording ? L("Stop") : L("Dyktuj"), systemImage: dict.recording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(dict.recording ? Color(hex: 0xD93A26).opacity(0.18) : Color.ink.opacity(0.08)))
                }
                .buttonStyle(.plain)
                Spacer()
                Button(action: saveRough) {
                    Text(L("Zapisz na brudno")).font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(Color.ink.opacity(0.08)))
                }
                .buttonStyle(.plain).keyboardShortcut("s", modifiers: .command)
                .disabled(isEmpty)
                Button(action: makeTasks) {
                    HStack(spacing: 5) {
                        if busy { ProgressView().controlSize(.small) } else { Image(systemName: "sparkles") }
                        Text(L("Zrób zadania"))
                    }
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Capsule().fill(Color.ink))
                }
                .buttonStyle(.plain).keyboardShortcut(.return, modifiers: .command)
                .disabled(isEmpty || busy)
            }
            .opacity(isEmpty && !dict.recording ? 0.6 : 1)
        }
    }

    private var isEmpty: Bool { fullText.isEmpty }
    private var fullText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func toggleDictation() {
        if dict.recording {
            Dictation.shared.finish { said in appendSaid(said) }
        } else {
            error = nil
            Dictation.shared.start()
        }
    }

    private func appendSaid(_ said: String) {
        let s = said.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return }
        text = text.isEmpty ? s : text.trimmingCharacters(in: .whitespacesAndNewlines) + "\n" + s
    }

    /// Najpierw kończymy dyktowanie (żeby nic nie zginęło), potem dalej.
    private func withDictationDone(_ then: @escaping () -> Void) {
        if dict.recording { Dictation.shared.finish { said in appendSaid(said); then() } } else { then() }
    }

    private func cancel() {
        if dict.recording { Dictation.shared.cancel() }
        close()
    }

    // MARK: zapis

    /// Na brudno: cały tekst w notatce, tytułem pierwsza linijka.
    private func saveRough() {
        withDictationDone {
            guard !fullText.isEmpty else { return }
            var n = Note()
            n.color = 3
            n.title = QuickNoteView.title(from: fullText)
            n.body = fullText
            Store.shared.notes.insert(n, at: 0)
            NSSound(named: "Pop")?.play()
            close()
        }
    }

    private func makeTasks() {
        withDictationDone {
            guard !fullText.isEmpty else { return }
            busy = true; error = nil
            Smart.propose(fullText) { r in
                busy = false
                switch r {
                case .success(let p): proposal = p; pick = Set(p.result.tasks.indices)
                case .failure(let e): error = e.localizedDescription
                }
            }
        }
    }

    static func title(from text: String) -> String {
        let first = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        return first.count > 60 ? String(first.prefix(57)) + "…" : first
    }

    // MARK: propozycja

    private func proposalView(_ p: SmartProposal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: p.viaAI ? "sparkles" : "text.badge.checkmark").font(.system(size: 11, weight: .bold))
                Text(p.title.isEmpty ? QuickNoteView.title(from: fullText) : p.title).font(.system(size: 17, weight: .semibold)).lineLimit(1)
            }
            let meta = [p.result.client, p.result.project].filter { !$0.isEmpty }.joined(separator: " · ")
            if !meta.isEmpty || p.result.deadline != nil {
                HStack(spacing: 8) {
                    if !meta.isEmpty { Text(meta.uppercased()).font(.system(size: 10, weight: .bold)).tracking(0.6) }
                    if let d = p.result.deadline {
                        Label(d.formatted(date: .abbreviated, time: p.result.hasTime ? .shortened : .omitted), systemImage: "calendar")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .foregroundStyle(Color.ink.opacity(0.55))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if p.result.tasks.isEmpty {
                        Text(L("Nie znalazłem tu zadań.")).font(.system(size: 13)).foregroundStyle(Color.ink.opacity(0.5))
                    }
                    ForEach(Array(p.result.tasks.enumerated()), id: \.offset) { i, t in
                        Button {
                            if pick.contains(i) { pick.remove(i) } else { pick.insert(i) }
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: pick.contains(i) ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(pick.contains(i) ? Color.ink : Color.ink.opacity(0.4))
                                Text(t).font(.system(size: 13.5)).fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack(spacing: 8) {
                Button { proposal = nil } label: {
                    Text(L("Wstecz")).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.ink.opacity(0.6))
                }
                .buttonStyle(.plain)
                Spacer()
                Button(action: saveRough) {
                    Text(L("Zapisz na brudno")).font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 7).background(Capsule().fill(Color.ink.opacity(0.08)))
                }
                .buttonStyle(.plain)
                Button { save(p) } label: {
                    Text(LF("Dodaj (%d)", pick.count)).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 7).background(Capsule().fill(Color.ink))
                }
                .buttonStyle(.plain).keyboardShortcut(.defaultAction)
            }
        }
    }

    /// Karteczka z propozycji: zadania, klient, projekt, termin; tekst z głowy zostaje w notatce.
    private func save(_ p: SmartProposal) {
        let r = p.result
        var n = Note()
        n.color = 3
        n.title = p.title.isEmpty ? QuickNoteView.title(from: fullText) : p.title
        n.client = r.client; n.project = r.project; n.tags = r.tags
        n.tasks = r.tasks.indices.filter { pick.contains($0) }.map { TaskItem(text: r.tasks[$0]) }
        if let d = r.deadline { n.deadline = d; n.hasTime = r.hasTime }
        n.body = fullText
        Store.shared.notes.insert(n, at: 0)
        Store.shared.ensureTagColors()
        NSSound(named: "Pop")?.play()
        close()
    }
}
