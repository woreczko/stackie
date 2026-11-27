import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple Intelligence (model na urządzeniu): wersja Standard „Zrób zadania”. Prywatnie i bez kosztów,
/// ale tylko na Macu z procesorem Apple, z włączonym Apple Intelligence i w obsługiwanym języku.
enum AppleAI {
    enum State { case ready, notEligible, turnedOff, notReady, language, oldSystem }

    static var state: State {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let m = SystemLanguageModel.default
            // język najpierw: po polsku Apple Intelligence nie zadziała, nawet gdy model jest gotowy
            if !m.supportsLocale(Lang.locale) { return .language }
            switch m.availability {
            case .available: return .ready
            case .unavailable(.deviceNotEligible): return .notEligible
            case .unavailable(.appleIntelligenceNotEnabled): return .turnedOff
            default: return .notReady
            }
        }
        #endif
        return .oldSystem
    }

    static var available: Bool {
        if ProcessInfo.processInfo.environment["STOSIK_NO_APPLE_AI"] != nil { return false }
        return state == .ready
    }

    /// Dlaczego nie działa (do ustawień).
    static var reason: String {
        switch state {
        case .ready: return ""
        case .notEligible: return L("Ten Mac nie obsługuje Apple Intelligence (potrzebny procesor Apple).")
        case .turnedOff: return L("Włącz Apple Intelligence w Ustawieniach systemowych.")
        case .notReady: return L("Apple Intelligence jeszcze się pobiera.")
        case .language: return L("Apple Intelligence nie obsługuje jeszcze tego języka.")
        case .oldSystem: return L("Apple Intelligence wymaga macOS 26.")
        }
    }

    /// Ten sam słownik co odpowiedź Claude (title, client, project, due_date, due_time, tags, tasks); nil przy błędzie.
    static func propose(_ text: String, instructions: String, done: @escaping ([String: Any]?) -> Void) {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            Task {
                do {
                    let session = LanguageModelSession(instructions: instructions)
                    let r = try await session.respond(to: text, generating: AINote.self)
                    let n = r.content
                    done(["title": n.title, "client": n.client, "project": n.project, "due_date": n.due_date,
                          "due_time": n.due_time, "tags": n.tags, "tasks": n.tasks])
                } catch {
                    done(nil)
                }
            }
            return
        }
        #endif
        done(nil)
    }
}

extension AppleAI {
    /// Zwykła odpowiedź tekstowa (przyciski AI w notatce); nil przy błędzie.
    static func rewrite(_ text: String, instructions: String, done: @escaping (String?) -> Void) {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            Task {
                do {
                    let r = try await LanguageModelSession(instructions: instructions).respond(to: text)
                    done(r.content.trimmingCharacters(in: .whitespacesAndNewlines))
                } catch { done(nil) }
            }
            return
        }
        #endif
        done(nil)
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable
struct AINote {
    @Guide(description: "2-5 words naming what the note is about")
    var title: String
    @Guide(description: "client named in the note, or empty")
    var client: String
    @Guide(description: "project named in the note, or empty")
    var project: String
    @Guide(description: "deadline as YYYY-MM-DD, or empty")
    var due_date: String
    @Guide(description: "deadline time as HH:MM, or empty")
    var due_time: String
    @Guide(description: "0-3 short tags", .maximumCount(3))
    var tags: [String]
    @Guide(description: "concrete actions, each starting with a verb", .maximumCount(12))
    var tasks: [String]
}
#endif
