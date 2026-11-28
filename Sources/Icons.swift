import SwiftUI

/// Ikonka pilności: trzy warstwy jak w referencji (żółta, fioletowa, czarna).
/// Kolorowych warstw tyle, ile poziom pilności; reszta przygaszona.
struct PriorityIcon: View {
    var level: Int
    var done = false
    var faint: Color = .ink
    /// Ikona aplikacji: oryginalne barwy z referencji.
    var classic = false

    static let yellow = Color(hex: 0xF6E3A1), purple = Color(hex: 0x9686F0), black = Color(hex: 0x111111)

    /// Barwy warstw (tył, środek, przód) według pilności: niska zielona, średnia pomarańczowa, wysoka czerwona.
    static let tones: [[Color]] = [
        [Color(hex: 0xCDEBB4), Color(hex: 0x7FCB84), Color(hex: 0x2E8A4C)],
        [Color(hex: 0xFBDDB0), Color(hex: 0xF5A55C), Color(hex: 0xD2641C)],
        [Color(hex: 0xF8BDB3), Color(hex: 0xEE6B56), Color(hex: 0xBC2A1C)],
    ]
    private var layers: [Color] {
        if classic { return [Self.yellow, Self.purple, Self.black] }
        return Self.tones[max(0, min(2, level - 1))]
    }

    var body: some View {
        GeometryReader { g in
            let s = g.size.width
            ZStack(alignment: .topLeading) {
                Rectangle().fill(level >= 3 ? layers[0] : faint.opacity(0.13))
                RoundedRectangle(cornerRadius: s * 0.24, style: .continuous)
                    .fill(level >= 2 ? layers[1] : faint.opacity(0.22))
                    .frame(width: s * 1.3, height: s)
                    .rotationEffect(.degrees(5))
                    .offset(x: -s * 0.15, y: s * 0.2)
                RoundedRectangle(cornerRadius: s * 0.24, style: .continuous)
                    .fill(level >= 1 ? layers[2] : faint.opacity(0.32))
                    .frame(width: s * 1.3, height: s)
                    .rotationEffect(.degrees(-5))
                    .offset(x: -s * 0.15, y: s * 0.53)
                if done {
                    Path { p in
                        p.move(to: CGPoint(x: s * 0.24, y: s * 0.74))
                        p.addLine(to: CGPoint(x: s * 0.35, y: s * 0.84))
                        p.addLine(to: CGPoint(x: s * 0.52, y: s * 0.66))
                    }
                    .stroke(.white, style: StrokeStyle(lineWidth: s * 0.08, lineCap: .round, lineJoin: .round))
                }
            }
            .frame(width: s, height: s)
            .clipShape(RoundedRectangle(cornerRadius: s * 0.3, style: .continuous))
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Kółeczko do odhaczania.
struct CheckCircle: View {
    var done: Bool
    var color: Color
    var size: CGFloat = 17
    /// „W trakcie”: lewa połówka kółka wypełniona.
    var doing = false

    var body: some View {
        ZStack {
            Circle().strokeBorder(color.opacity(done ? 0 : 0.75), lineWidth: 1.4)
            if doing && !done {
                Circle().fill(color.opacity(0.75)).padding(size * 0.2)
                    .mask(HStack(spacing: 0) { Rectangle(); Color.clear })
            }
            if done {
                Circle().fill(color)
                Image(systemName: "checkmark").font(.system(size: size * 0.5, weight: .heavy))
                    .foregroundStyle(Theme.dark ? Color(hex: DARK_CARD) : color == .white ? Color.inkFixed : .white)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
    }
}
