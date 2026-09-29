import SwiftUI

/// Measured microphone RMS drives wave amplitude and the central bars.
struct VoiceArtwork: View {
    let level: Float
    let listening: Bool
    var homeIcon = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var strength: Double { listening ? min(1, max(0, Double(level) * 16)) : 0 }
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !listening || reduceMotion)) { timeline in
            let phase = listening && !reduceMotion && strength > 0.025 ? timeline.date.timeIntervalSinceReferenceDate * 1.8 : 0
            GeometryReader { geometry in
                ZStack {
                    RadialGradient(colors: [MintTheme.mint.opacity(0.24 + strength * 0.15), .clear], center: .center, startRadius: 5, endRadius: geometry.size.height * 0.5)
                    Canvas { context, size in
                        for line in 0..<18 {
                            var path = Path()
                            for x in stride(from: 0.0, through: size.width, by: 3) {
                                let fraction = x / size.width
                                let envelope = sin(fraction * .pi)
                                let amplitude = (8 + strength * 25 + Double(line) * 0.8) * envelope
                                let y = size.height * 0.52 + sin(fraction * .pi * 3.3 + phase + Double(line) * 0.11) * amplitude
                                if x == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                            }
                            context.stroke(path, with: .color(MintTheme.mint.opacity(0.08 + Double(line) * 0.011)), lineWidth: 0.65)
                        }
                    }
                    RoundedRectangle(cornerRadius: homeIcon ? geometry.size.height * 0.2 : geometry.size.height, style: .continuous)
                        .fill(LinearGradient(colors: [MintTheme.teal.opacity(0.8), MintTheme.background], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(RoundedRectangle(cornerRadius: homeIcon ? geometry.size.height * 0.2 : geometry.size.height, style: .continuous).stroke(MintTheme.mint.opacity(0.65), lineWidth: 1))
                        .shadow(color: MintTheme.mint.opacity(0.3 + strength * 0.2), radius: 10)
                        .frame(width: geometry.size.height * 0.82, height: geometry.size.height * 0.82)
                    HStack(spacing: 5) {
                        ForEach(0..<5) { index in
                            let base = [14.0, 30.0, 44.0, 30.0, 14.0][index]
                            Capsule().fill(MintTheme.mint)
                                .frame(width: 4, height: base * (0.6 + strength * (0.4 + abs(sin(phase + Double(index))) * 0.5)))
                        }
                    }
                }
            }
        }.accessibilityHidden(true)
    }
}

struct MintPanel: ViewModifier {
    var highlight = false
    func body(content: Content) -> some View {
        content.background(LinearGradient(colors: [MintTheme.card.opacity(0.75), MintTheme.background], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(MintTheme.mint.opacity(highlight ? 0.45 : 0.2), lineWidth: 0.8))
    }
}
extension View { func glowPanel(highlight: Bool = false) -> some View { modifier(MintPanel(highlight: highlight)) } }

struct MintActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 17, weight: .semibold)).foregroundStyle(MintTheme.background)
            .padding(.horizontal, 22).frame(minHeight: 56)
            .background(LinearGradient(colors: [MintTheme.mint, Color(red: 0, green: 0.85, blue: 0.76)], startPoint: .leading, endPoint: .trailing), in: Capsule())
            .overlay(Capsule().stroke(MintTheme.mint.opacity(0.7)))
            .shadow(color: MintTheme.mint.opacity(0.15), radius: 14, y: 2)
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
struct MintRoundStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
            .background(MintTheme.teal.opacity(0.3), in: Circle())
            .overlay(Circle().stroke(MintTheme.mint.opacity(0.35)))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
