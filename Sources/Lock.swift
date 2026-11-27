import SwiftUI
import LocalAuthentication

/// Karteczki pod Touch ID: zablokowana jest zasłonięta w stosie; otwiera się po Touch ID (albo haśle do Maca)
/// i zamyka znowu, gdy zamkniesz edytor albo Mac się uśpi.
final class Locker: ObservableObject {
    static let shared = Locker()
    @Published private(set) var open: Set<UUID> = []

    init() {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.open = []
        }
    }

    func isOpen(_ id: UUID) -> Bool { open.contains(id) }
    func lock(_ id: UUID) { if open.contains(id) { open.remove(id) } }
    /// Po świeżym zablokowaniu karteczka zostaje otwarta, dopóki edytor jest otwarty.
    func keepOpen(_ id: UUID) { open.insert(id) }

    func unlock(_ id: UUID, done: @escaping (Bool) -> Void) {
        if open.contains(id) { return done(true) }
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { return done(false) }
        NSApp.activate(ignoringOtherApps: true)
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: L("otworzyć zablokowaną karteczkę")) { ok, _ in
            DispatchQueue.main.async {
                if ok { self.open.insert(id) }
                done(ok)
            }
        }
    }
}

/// Zasłona na zablokowanej karteczce: rozmyte „linijki”, kłódka. Nic z treści nie przecieka.
struct LockCover: View {
    var bg: Color
    var fg: Color
    var corner: CGFloat
    var mini = false
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous).fill(bg)
            VStack(alignment: .leading, spacing: mini ? 6 : 9) {
                ForEach([0.55, 0.8, 0.65, 0.4], id: \.self) { w in
                    Capsule().fill(fg.opacity(0.22)).frame(width: (mini ? 120 : 170) * w, height: mini ? 6 : 8)
                }
            }
            .blur(radius: mini ? 3 : 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(mini ? 14 : 20).padding(.top, mini ? 6 : 26)
            VStack(spacing: 6) {
                Image(systemName: "lock.fill").font(.system(size: mini ? 16 : 24, weight: .semibold))
                if !mini { Text(L("Zablokowana")).font(.system(size: 11, weight: .semibold)).tracking(0.4) }
            }
            .foregroundStyle(fg.opacity(0.65))
            .padding(.top, mini ? 58 : 40)
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}
