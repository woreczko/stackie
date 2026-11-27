import AppKit

/// Połączenie z Claude (MCP): `Stosik --mcp` to serwer MCP na stdin/stdout dla Claude Code, Claude Desktop i innych.
/// Czyta karteczki z pliku. Zmiany wysyła do działającej apki (powiadomienie systemowe), żeby nie nadpisać tego,
/// co właśnie piszesz; gdy apka jest zamknięta, zapisuje plik sam.
enum MCP {
    /// Osobny kanał dla osobnego folderu danych (testy nie trafią do prawdziwej apki).
    private static var channel: String {
        ProcessInfo.processInfo.environment["STOSIK_DIR"].map { "." + $0.replacingOccurrences(of: "/", with: "_") } ?? ""
    }
    static var requestName: Notification.Name { Notification.Name("pl.stosik.mcp.request" + channel) }
    static var replyName: Notification.Name { Notification.Name("pl.stosik.mcp.reply" + channel) }

    static var dataDir: URL {
        if let p = ProcessInfo.processInfo.environment["STOSIK_DIR"] { return URL(fileURLWithPath: p) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Stosik")
    }
    static var file: URL { dataDir.appendingPathComponent("karteczki.json") }

    static func loadNotes() -> [Note] {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        guard let d = try? Data(contentsOf: file), let n = try? dec.decode([Note].self, from: d) else { return [] }
        return n
    }

    static func saveNotes(_ notes: [Note]) {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted]
        if let d = try? enc.encode(notes) { try? d.write(to: file, options: .atomic) }
    }

    // MARK: serwer (stdin/stdout, JSON-RPC po jednej linijce)

    static func serve() -> Never {
        Lang.resolve()
        setvbuf(stdout, nil, _IOLBF, 0)
        DispatchQueue.global().async {
            while let line = readLine(strippingNewline: true) {
                guard let d = line.data(using: .utf8), let msg = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { continue }
                DispatchQueue.main.async { handle(msg) }
            }
            // koniec wejścia: najpierw dokończ wszystko, co już czeka w kolejce
            DispatchQueue.main.async { exit(0) }
        }
        RunLoop.main.run()
        exit(0)
    }

    private static func send(_ o: [String: Any]) {
        guard let d = try? JSONSerialization.data(withJSONObject: o), let s = String(data: d, encoding: .utf8) else { return }
        FileHandle.standardOutput.write(Data((s + "\n").utf8))
    }

    private static func handle(_ msg: [String: Any]) {
        let id = msg["id"]
        let method = msg["method"] as? String ?? ""
        let params = msg["params"] as? [String: Any] ?? [:]
        func reply(_ result: [String: Any]) { if let id { send(["jsonrpc": "2.0", "id": id, "result": result]) } }
        switch method {
        case "initialize":
            reply(["protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
                   "capabilities": ["tools": [:]],
                   "serverInfo": ["name": "stackie", "version": APP_VERSION],
                   "instructions": "Stackie is the user's sticky-notes app: each note is a project (title, client, project, tags, deadline, tasks). Use these tools to read and update their notes and tasks."])
        case "ping": reply([:])
        case "tools/list": reply(["tools": tools])
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let args = params["arguments"] as? [String: Any] ?? [:]
            call(name, args) { text, isError in
                reply(["content": [["type": "text", "text": text]], "isError": isError])
            }
        default:
            if let id { send(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Unknown method \(method)"]]) }
        }
    }

    // MARK: narzędzia

    private static let noteArg: [String: Any] = ["type": "string", "description": "Note id, or a word from its title or client"]
    static let tools: [[String: Any]] = [
        ["name": "list_notes",
         "description": "List the user's notes (newest first) with client, project, deadline and tasks. Task marks: [ ] open, [~] in progress, [x] done.",
         "inputSchema": ["type": "object", "properties": [
            "query": ["type": "string", "description": "Only notes whose title, client, project, tags or tasks contain this"],
            "include_archived": ["type": "boolean"]]]],
        ["name": "today",
         "description": "What is due today and overdue: notes with a deadline today or earlier and their open tasks.",
         "inputSchema": ["type": "object", "properties": [:]]],
        ["name": "add_note",
         "description": "Create a new note (a project card) with optional tasks and deadline.",
         "inputSchema": ["type": "object", "required": ["title"], "properties": [
            "title": ["type": "string"], "client": ["type": "string"], "project": ["type": "string"],
            "tags": ["type": "array", "items": ["type": "string"]],
            "tasks": ["type": "array", "items": ["type": "string"]],
            "due_date": ["type": "string", "description": "YYYY-MM-DD"], "due_time": ["type": "string", "description": "HH:MM"],
            "body": ["type": "string", "description": "Free text note"]]]],
        ["name": "add_tasks",
         "description": "Add tasks to the end of an existing note.",
         "inputSchema": ["type": "object", "required": ["note", "tasks"], "properties": [
            "note": noteArg, "tasks": ["type": "array", "items": ["type": "string"]]]]],
        ["name": "set_task",
         "description": "Mark a task as done, open or in progress.",
         "inputSchema": ["type": "object", "required": ["note", "task", "state"], "properties": [
            "note": noteArg,
            "task": ["type": "string", "description": "Task number (1 = first) or a word from its text"],
            "state": ["type": "string", "enum": ["done", "open", "doing"]]]]],
    ]

    private static func call(_ name: String, _ args: [String: Any], done: @escaping (String, Bool) -> Void) {
        switch name {
        case "list_notes":
            var notes = loadNotes().filter { $0.deletedAt == nil }
            if (args["include_archived"] as? Bool) != true { notes = notes.filter { !$0.archived } }
            if let q = (args["query"] as? String)?.trimmingCharacters(in: .whitespaces), !q.isEmpty {
                notes = notes.filter { matches($0, q) }
            }
            done(notes.isEmpty ? "No notes." : notes.map(describe).joined(separator: "\n\n"), false)
        case "today":
            let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))!
            let due = loadNotes().filter { !$0.archived && $0.deletedAt == nil && ($0.deadline.map { $0 < end } ?? false) }
                .sorted { ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) }
            done(due.isEmpty ? "Nothing due today." : due.map(describe).joined(separator: "\n\n"), false)
        case "add_note", "add_tasks", "set_task":
            change(["tool": name, "args": args], done: done)
        default:
            done("Unknown tool \(name)", true)
        }
    }

    private static func matches(_ n: Note, _ q: String) -> Bool {
        ([n.title, n.client, n.project, n.body] + n.tags + n.tasks.map(\.text)).contains {
            $0.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    static func describe(_ n: Note) -> String {
        if n.locked { return "(locked note — the user keeps it private)\nid: \(n.id.uuidString)" }
        var head = n.title.isEmpty ? "(untitled)" : n.title
        let meta = [n.client, n.project].filter { !$0.isEmpty }.joined(separator: " / ")
        if !meta.isEmpty { head += " — " + meta }
        if let d = n.deadline {
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = n.hasTime ? "yyyy-MM-dd HH:mm" : "yyyy-MM-dd"
            head += " · due " + f.string(from: d)
        }
        if !n.tags.isEmpty { head += " · #" + n.tags.joined(separator: " #") }
        if n.archived { head += " · archived" }
        var lines = [head, "id: \(n.id.uuidString)"]
        for (i, t) in n.tasks.enumerated() where !t.text.isEmpty {
            lines.append("\(i + 1). [\(t.done ? "x" : t.doing ? "~" : " ")] \(t.text)")
        }
        let body = n.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty { lines.append("note: " + (body.count > 400 ? String(body.prefix(400)) + "…" : body)) }
        return lines.joined(separator: "\n")
    }

    // MARK: zmiany: przez apkę, gdy działa, inaczej wprost w pliku

    private static var appRunning: Bool {
        let env = ProcessInfo.processInfo.environment
        if env["STOSIK_MCP_VIA_APP"] != nil { return true }   // test: wymuś drogę przez apkę
        return env["STOSIK_DIR"] == nil && !NSRunningApplication.runningApplications(withBundleIdentifier: "pl.stosik.app").isEmpty
    }

    private static func change(_ cmd: [String: Any], done: @escaping (String, Bool) -> Void) {
        guard appRunning else {
            var notes = loadNotes()
            let (text, err) = apply(cmd, to: &notes)
            if !err { saveNotes(notes) }
            return done(text, err)
        }
        let rid = UUID().uuidString
        var c = cmd; c["rid"] = rid
        guard let d = try? JSONSerialization.data(withJSONObject: c), let s = String(data: d, encoding: .utf8) else {
            return done("Could not encode the request.", true)
        }
        let center = DistributedNotificationCenter.default()
        var token: NSObjectProtocol?
        var finished = false
        token = center.addObserver(forName: replyName, object: nil, queue: .main) { n in
            guard let str = n.object as? String, let rd = str.data(using: .utf8),
                  let r = try? JSONSerialization.jsonObject(with: rd) as? [String: Any], r["rid"] as? String == rid else { return }
            finished = true
            if let token { center.removeObserver(token) }
            done(r["text"] as? String ?? "", r["error"] as? Bool ?? false)
        }
        center.postNotificationName(requestName, object: s, userInfo: nil, deliverImmediately: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            guard !finished else { return }
            if let token { center.removeObserver(token) }
            done("Stackie is running but did not answer. Try again.", true)
        }
    }

    /// Po stronie apki: wykonuje zmianę na karteczkach w pamięci i odpowiada.
    static func listen(store: Store) {
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: requestName, object: nil, queue: .main) { n in
            guard let str = n.object as? String, let d = str.data(using: .utf8),
                  let cmd = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let rid = cmd["rid"] as? String else { return }
            var notes = store.notes
            let (text, err) = apply(cmd, to: &notes)
            if !err { store.notes = notes; store.ensureTagColors() }
            let r: [String: Any] = ["rid": rid, "text": text, "error": err]
            if let rd = try? JSONSerialization.data(withJSONObject: r), let rs = String(data: rd, encoding: .utf8) {
                center.postNotificationName(replyName, object: rs, userInfo: nil, deliverImmediately: true)
            }
        }
    }

    static func apply(_ cmd: [String: Any], to notes: inout [Note]) -> (String, Bool) {
        let args = cmd["args"] as? [String: Any] ?? [:]
        func strings(_ k: String) -> [String] {
            (args[k] as? [String] ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        switch cmd["tool"] as? String {
        case "add_note":
            var n = Note()
            n.title = (args["title"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            n.client = args["client"] as? String ?? ""
            n.project = args["project"] as? String ?? ""
            n.tags = strings("tags")
            n.body = args["body"] as? String ?? ""
            n.tasks = strings("tasks").map { TaskItem(text: $0) }
            n.color = 3
            if let day = args["due_date"] as? String, !day.isEmpty {
                let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
                if var d = f.date(from: day) {
                    let hm = (args["due_time"] as? String ?? "").split(separator: ":").compactMap { Int($0) }
                    if hm.count == 2, let t = Calendar.current.date(bySettingHour: hm[0], minute: hm[1], second: 0, of: d) {
                        d = t; n.hasTime = true
                    }
                    n.deadline = d
                }
            }
            notes.insert(n, at: 0)
            return ("Created note \"\(n.title)\" (id \(n.id.uuidString)) with \(n.tasks.count) tasks.", false)
        case "add_tasks":
            switch find(args["note"] as? String ?? "", in: notes) {
            case .failure(let e): return (e.text, true)
            case .success(let i):
                let new = strings("tasks")
                guard !new.isEmpty else { return ("No tasks given.", true) }
                while let last = notes[i].tasks.last, last.text.trimmingCharacters(in: .whitespaces).isEmpty { notes[i].tasks.removeLast() }
                notes[i].tasks += new.map { TaskItem(text: $0) }
                return ("Added \(new.count) tasks to \"\(notes[i].title)\".\n\n" + describe(notes[i]), false)
            }
        case "set_task":
            switch find(args["note"] as? String ?? "", in: notes) {
            case .failure(let e): return (e.text, true)
            case .success(let i):
                let q = (args["task"] as? String ?? "").trimmingCharacters(in: .whitespaces)
                let tasks = notes[i].tasks
                var k: Int? = Int(q).flatMap { $0 >= 1 && $0 <= tasks.count ? $0 - 1 : nil }
                if k == nil {
                    let hits = tasks.indices.filter { tasks[$0].text.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
                    if hits.count > 1 { return ("Several tasks match \"\(q)\"; use the task number.\n\n" + describe(notes[i]), true) }
                    k = hits.first
                }
                guard let k else { return ("No task matches \"\(q)\".\n\n" + describe(notes[i]), true) }
                switch args["state"] as? String {
                case "done": notes[i].tasks[k].done = true; if notes[i].tasks[k].doneAt == nil { notes[i].tasks[k].doneAt = Date() }
                case "doing": notes[i].tasks[k].done = false; notes[i].tasks[k].doneAt = nil; notes[i].tasks[k].doing = true
                default: notes[i].tasks[k].done = false; notes[i].tasks[k].doneAt = nil; notes[i].tasks[k].doing = false
                }
                return ("Updated.\n\n" + describe(notes[i]), false)
            }
        default:
            return ("Unknown change.", true)
        }
    }

    struct FindError: Error { let text: String }

    /// Karteczka po id albo po słowie z tytułu lub klienta (dokładny tytuł wygrywa).
    static func find(_ q: String, in notes: [Note]) -> Result<Int, FindError> {
        let q = q.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return .failure(FindError(text: "Say which note.")) }
        let live = notes.indices.filter { !notes[$0].archived && notes[$0].deletedAt == nil }
        if let i = notes.firstIndex(where: { $0.id.uuidString.caseInsensitiveCompare(q) == .orderedSame }) { return .success(i) }
        if let i = live.first(where: { notes[$0].title.caseInsensitiveCompare(q) == .orderedSame }) { return .success(i) }
        let hits = live.filter { i in
            [notes[i].title, notes[i].client, notes[i].project].contains { $0.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
        if hits.count == 1 { return .success(hits[0]) }
        if hits.isEmpty { return .failure(FindError(text: "No note matches \"\(q)\". Use list_notes to see them.")) }
        return .failure(FindError(text: "Several notes match \"\(q)\":\n" + hits.map { "- \(notes[$0].title) (id \(notes[$0].id.uuidString))" }.joined(separator: "\n") + "\nUse the id."))
    }
}
