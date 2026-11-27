import Foundation
import Security
import CryptoKit
import CommonCrypto

// MARK: - Zadania z notatki: Claude (Haiku 5.5) porządkuje chaotyczny tekst w zadania.
// Bez klucza: zwykłe dzielenie po czasownikach (to samo, co przy dyktowaniu).

/// Klucz do Claude. Dwie drogi: własny klucz (wklejony) albo klucz Stackie wbudowany w apkę,
/// zaszyfrowany hasłem (bez hasła nie da się go wyciągnąć). Oba po zapisaniu leżą w pęku kluczy macOS.
enum ClaudeKey {
    private static let service = "Stosik.claude"
    private static let ownAccount = "anthropic-api-key"
    private static let sharedAccount = "stackie-shared-key"

    static var value: String? {
        // test: klucz z otoczenia (np. fałszywy, żeby sprawdzić odpowiedź serwera), bez dotykania pęku kluczy
        if let k = ProcessInfo.processInfo.environment["STOSIK_CLAUDE_KEY"] { return k.isEmpty ? nil : k }
        return own ?? shared
    }

    // pęk kluczy czytany raz (edytor pyta o klucz przy każdym przerysowaniu); zapis i usunięcie odświeżają
    private static var cache: (own: String?, shared: String?)?
    private static var own: String? { load().own }
    private static var shared: String? { load().shared }
    private static func load() -> (own: String?, shared: String?) {
        if let cache { return cache }
        let c = (read(ownAccount), read(sharedAccount)); cache = c; return c
    }

    static var isSet: Bool { value != nil }
    /// Własny klucz (ma pierwszeństwo przed kluczem Stackie).
    static var isOwn: Bool { own != nil }
    /// Klucz Stackie odblokowany hasłem na tym Macu.
    static var isShared: Bool { shared != nil }
    /// W apce jest zaszyfrowany klucz Stackie (do odblokowania hasłem).
    static var hasBuiltIn: Bool { sealed != nil }

    static func save(_ key: String) { write(ownAccount, key) }
    static func delete() { write(ownAccount, nil); write(sharedAccount, nil) }

    /// Hasło pasuje: klucz Stackie zostaje zapisany na tym Macu. Złe hasło: false.
    static func unlock(_ password: String) -> Bool {
        guard let sealed, let k = KeyBox.open(sealed, password: password), k.hasPrefix("sk-ant-") else { return false }
        write(sharedAccount, k)
        return true
    }

    private static let sealed: Data? = {
        guard let u = Bundle.main.url(forResource: "k", withExtension: "bin"), let d = try? Data(contentsOf: u), !d.isEmpty else { return nil }
        return d
    }()

    private static func read(_ account: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data,
              let s = String(data: d, encoding: .utf8), !s.isEmpty else { return nil }
        return s
    }

    private static func write(_ account: String, _ value: String?) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        cache = nil
        guard let v = value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return }
        var q = base; q[kSecValueData as String] = Data(v.utf8)
        SecItemAdd(q as CFDictionary, nil)
        cache = nil
    }
}

/// Szyfrowanie klucza hasłem: PBKDF2-SHA256 (200 000 rund, losowa sól) i AES-GCM.
/// Plik: 16 bajtów soli + zaszyfrowane dane (nonce, szyfrogram, znacznik).
enum KeyBox {
    static func seal(_ text: String, password: String) -> Data? {
        var salt = Data(count: 16)
        guard salt.withUnsafeMutableBytes({ SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }) == errSecSuccess,
              let key = derive(password, salt),
              let box = try? AES.GCM.seal(Data(text.utf8), using: key), let c = box.combined else { return nil }
        return salt + c
    }

    static func open(_ data: Data, password: String) -> String? {
        guard data.count > 16 + 28, let key = derive(password, data.prefix(16)),
              let box = try? AES.GCM.SealedBox(combined: data.dropFirst(16)),
              let plain = try? AES.GCM.open(box, using: key) else { return nil }
        return String(data: plain, encoding: .utf8)
    }

    private static func derive(_ password: String, _ salt: Data) -> SymmetricKey? {
        var out = [UInt8](repeating: 0, count: 32)
        let pw = Array(password.utf8)
        let salt = Array(salt)
        let r = CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), password, pw.count, salt, salt.count,
                                     CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 200_000, &out, out.count)
        return r == kCCSuccess ? SymmetricKey(data: out) : nil
    }
}

/// Propozycja z notatki: tytuł, klient, projekt, termin, tagi i zadania. `viaAI`: czy to Claude, czy dzielenie po czasownikach.
struct SmartProposal {
    var title = ""
    var result = DictationResult()
    var viaAI = false
}

enum SmartError: LocalizedError {
    case badKey, network, refused, other(String)
    var errorDescription: String? {
        switch self {
        case .badKey: return L("Klucz Claude jest nieprawidłowy. Sprawdź go w ustawieniach.")
        case .network: return L("Brak połączenia z internetem.")
        case .refused: return L("Claude nie przetworzył tej notatki.")
        case .other(let s): return s
        }
    }
}

enum Smart {
    static let model = "claude-haiku-5-5"

    /// Czym „Zrób zadania” liczy: Pro (Claude, z kluczem), Standard z Apple Intelligence (na urządzeniu)
    /// albo Standard bez AI (dzielenie po czasownikach), gdy Apple Intelligence tu nie działa.
    enum Engine { case claude, apple, basic }
    static var engine: Engine { ClaudeKey.value != nil ? .claude : AppleAI.available ? .apple : .basic }

    static func propose(_ text: String, completion: @escaping (Result<SmartProposal, SmartError>) -> Void) {
        guard let key = ClaudeKey.value else {
            let basic = SmartProposal(result: parseDictation(text), viaAI: false)
            if AppleAI.available {
                // błąd modelu na urządzeniu: zostaje proste dzielenie, bez komunikatu
                AppleAI.propose(text, instructions: systemPrompt()) { o in
                    DispatchQueue.main.async { completion(.success(o.map(proposal(from:)) ?? basic)) }
                }
            } else {
                completion(.success(basic))
            }
            return
        }
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4000,
            "system": systemPrompt(),
            "messages": [["role": "user", "content": text]],
            "output_config": ["effort": "low", "format": ["type": "json_schema", "schema": schema]],
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req) { data, resp, err in
            let finish: (Result<SmartProposal, SmartError>) -> Void = { r in DispatchQueue.main.async { completion(r) } }
            if err != nil { return finish(.failure(.network)) }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 || code == 403 { return finish(.failure(.badKey)) }
            guard let data, let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return finish(.failure(.other(LF("Błąd Claude (%d).", code))))
            }
            guard code == 200 else {
                let msg = ((j["error"] as? [String: Any])?["message"] as? String) ?? LF("Błąd Claude (%d).", code)
                return finish(.failure(.other(msg)))
            }
            if (j["stop_reason"] as? String) == "refusal" { return finish(.failure(.refused)) }
            // odpowiedź: blok tekstu z JSON-em według schematu (bloki myślenia pomijamy)
            let blocks = j["content"] as? [[String: Any]] ?? []
            guard let txt = blocks.first(where: { $0["type"] as? String == "text" })?["text"] as? String,
                  let o = try? JSONSerialization.jsonObject(with: Data(txt.utf8)) as? [String: Any] else {
                return finish(.failure(.other(L("Claude odpowiedział w nieoczekiwany sposób."))))
            }
            finish(.success(proposal(from: o)))
        }.resume()
    }

    static func proposal(from o: [String: Any]) -> SmartProposal {
        var p = SmartProposal(viaAI: true)
        p.title = (o["title"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        p.result.client = (o["client"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        p.result.project = (o["project"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        p.result.tags = (o["tags"] as? [String] ?? []).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        p.result.tasks = (o["tasks"] as? [String] ?? []).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let day = o["due_date"] as? String ?? "", time = o["due_time"] as? String ?? ""
        let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX"); df.dateFormat = "yyyy-MM-dd"
        if var d = df.date(from: day) {
            let hm = time.split(separator: ":").compactMap { Int($0) }
            if hm.count == 2, let t = Calendar.current.date(bySettingHour: hm[0], minute: hm[1], second: 0, of: d) {
                d = t; p.result.hasTime = true
            }
            p.result.deadline = d
        }
        return p
    }

    private static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "title": ["type": "string"],
            "client": ["type": "string"],
            "project": ["type": "string"],
            "due_date": ["type": "string"],
            "due_time": ["type": "string"],
            "tags": ["type": "array", "items": ["type": "string"]],
            "tasks": ["type": "array", "items": ["type": "string"]],
        ],
        "required": ["title", "client", "project", "due_date", "due_time", "tags", "tasks"],
        "additionalProperties": false,
    ]

    static func systemPrompt() -> String {
        let df = DateFormatter(); df.locale = Locale(identifier: "pl_PL"); df.dateFormat = "EEEE, yyyy-MM-dd, HH:mm"
        let clients = Array(Set(Store.shared.notes.map(\.client).filter { !$0.isEmpty })).sorted().prefix(40)
        let projects = Array(Set(Store.shared.notes.map(\.project).filter { !$0.isEmpty })).sorted().prefix(40)
        return """
        You turn a quick, messy note (often typed during a phone call) into a clear to-do list for a sticky-notes app.
        Now: \(df.string(from: Date())). Resolve relative dates like "jutro", "w piątek", "do dwunastej" from this.

        Return:
        - title: 2-5 words naming what the note is about.
        - client, project: only if the note names them (prefer the spelling from the known lists below); otherwise "".
        - due_date (YYYY-MM-DD) and due_time (HH:MM): only if the note gives a deadline; otherwise "".
        - tags: 0-3 short words, only if clearly useful (e.g. "pilne", "faktura").
        - tasks: concrete actions found in the note, each starting with a verb, short (under ~8 words), in the note's language, \
        no duplicates, at most 12. Keep names, amounts and details that matter. Do not invent tasks the note doesn't imply.
        Write everything in the same language as the note.

        Known clients: \(clients.joined(separator: ", "))
        Known projects: \(projects.joined(separator: ", "))
        """
    }
}
