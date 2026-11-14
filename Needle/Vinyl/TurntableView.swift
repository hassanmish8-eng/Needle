import SwiftUI

/// Matte graphite base with a faint speckle texture, so it reads as a physical object.
struct TurntablePlinth: View {
    let side: CGFloat

    var body: some View {
        let corner = side * 0.055
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.075)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(
                Canvas { ctx, size in
                    for i in 0..<700 {
                        let x = CGFloat(Noise.value(i * 2)) * size.width
                        let y = CGFloat(Noise.value(i * 2 + 1)) * size.height
                        let alpha = 0.015 + Noise.value(i + 4000) * 0.045
                        let s = 0.6 + CGFloat(Noise.value(i + 9000)) * 0.8
                        ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: s, height: s)),
                                 with: .color(Color.white.opacity(alpha)))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.16), Color.white.opacity(0.02)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 1)
            )
            .overlay(alignment: .bottomLeading) {
                Text("33⅓")
                    .font(.system(size: max(8, side * 0.032), weight: .medium))
                    .tracking(1.2)
                    .foregroundColor(Color.white.opacity(0.22))
                    .padding(side * 0.045)
                    .accessibilityHidden(true)
            }
            .shadow(color: Color.black.opacity(0.6), radius: side * 0.06, x: 0, y: side * 0.035)
            .frame(width: side, height: side)
    }
}

/// The slightly raised circular platter, with a soft shadow where the record sits.
struct TurntablePlatter: View {
    let diameter: CGFloat

    var body: some View {
        let d = diameter * TurntableMetrics.platterRatio
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.12), Color(white: 0.075), Color(white: 0.10)],
                                     center: .center, startRadius: 0, endRadius: d / 2))
                .frame(width: d, height: d)
            Circle()
                .strokeBorder(AngularGradient(colors: [Color.white.opacity(0.30), Color.white.opacity(0.06),
                                                       Color.white.opacity(0.22), Color.white.opacity(0.05),
                                                       Color.white.opacity(0.30)],
                                              center: .center), lineWidth: max(1, d * 0.006))
                .frame(width: d, height: d)
            Circle()
                .fill(Color.black.opacity(0.55))
                .frame(width: diameter, height: diameter)
                .blur(radius: diameter * 0.02)
                .offset(y: diameter * 0.012)
        }
    }
}

/// Metallic spindle. Stationary: it sits in the hole while the record turns around it.
struct Spindle: View {
    let discDiameter: CGFloat

    var body: some View {
        let d = discDiameter * TurntableMetrics.spindleRatio
        Circle()
            .fill(RadialGradient(colors: [Color(white: 0.96), Color(white: 0.55), Color(white: 0.25)],
                                 center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: d))
            .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 0.5))
            .frame(width: d, height: d)
            .shadow(color: Color.black.opacity(0.5), radius: d * 0.2, x: d * 0.1, y: d * 0.15)
            .accessibilityHidden(true)
    }
}

/// Static stand-in for continuous motion when Reduce Motion is on.
struct PlayingBadge: View {
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "waveform")
            Text("Playing")
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(Theme.secondaryText)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.white.opacity(0.10)))
        .accessibilityHidden(true)
    }
}

/// Plinth, platter, spinning record, spindle and tonearm, composed as separate layers.
@MainActor
struct TurntableView: View {
    let diameter: CGFloat
    let appearance: VinylAppearance
    let artwork: ArtworkImage
    let motion: MotionPolicy
    let showTonearm: Bool
    let track: TrackInfo?
    let isPlaying: Bool
    /// Playback fraction 0...1 at a date; moves the stylus inward over the track.
    let progress: (Date) -> Double

    @State private var cueing = false

    var body: some View {
        let plinth = diameter * TurntableMetrics.plinthRatio
        ZStack {
            TurntablePlinth(side: plinth)
            TurntablePlatter(diameter: diameter)
            SpinningDisc(disc: VinylDiscView(appearance: appearance,
                                             artwork: artwork,
                                             animateTransitions: motion.animatesArtwork),
                         spinning: isPlaying && motion.spinsRecord)
                .frame(width: diameter, height: diameter)
            Spindle(discDiameter: diameter)
            if motion.reduceMotion && isPlaying {
                PlayingBadge()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(plinth * 0.04)
            }
            if showTonearm {
                tonearm
            }
        }
        .frame(width: plinth, height: plinth)
        .onChange(of: track?.uri) { _ in cueIfNeeded() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("vinylRecord")
    }

    // MARK: Tonearm

    private var isLifted: Bool { track != nil && !isPlaying }

    private var tonearm: some View {
        let radius = diameter / 2
        return TimelineView(.animation(minimumInterval: 1.0, paused: !isPlaying)) { timeline in
            let angle = armAngle(progress: progress(timeline.date))
            TonearmView(radius: radius, angle: angle, lifted: isLifted)
                .animation(motion.animatesTonearm ? .easeInOut(duration: 0.9) : nil, value: angle)
        }
        .offset(x: TurntableMetrics.pivot.x * radius, y: TurntableMetrics.pivot.y * radius)
    }

    private func armAngle(progress: Double) -> Double {
        guard track != nil, !cueing else { return TurntableMetrics.restAngle }
        let span = TurntableMetrics.endAngle - TurntableMetrics.startAngle
        let playing = TurntableMetrics.startAngle + span * min(max(progress, 0), 1)
        return isPlaying ? playing : playing - 7       // paused: nudged away from the groove
    }

    /// On a track change the arm swings back to rest, then settles onto the new record.
    private func cueIfNeeded() {
        guard motion.animatesTonearm, isPlaying else { return }
        cueing = true
        Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            cueing = false
        }
    }

    private var accessibilityText: String {
        guard let track else { return "Turntable, empty" }
        return "Vinyl record for \(track.title) by \(track.artist), \(isPlaying ? "spinning" : "stopped")"
    }
}
