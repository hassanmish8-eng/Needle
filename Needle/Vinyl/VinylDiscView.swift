import SwiftUI

/// The record body as a Canvas (vector, crisp on every density).
struct VinylSurfaceCanvas: View {
    let surface: VinylSurface

    var body: some View {
        Canvas { context, size in
            VinylPainter.paint(&context, size: size, surface: surface)
        }
    }
}

/// Center label: the real album art, circle-clipped (never stretched), or a clearly
/// different placeholder when there is no artwork.
struct VinylLabel: View {
    let artwork: ArtworkImage
    let diameter: CGFloat

    var body: some View {
        ZStack {
            if let image = artwork.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: diameter, height: diameter)
                    .clipShape(Circle())
                Circle().fill(RadialGradient(colors: [Color.clear, Color.black.opacity(0.18)],
                                             center: .center,
                                             startRadius: diameter * 0.30,
                                             endRadius: diameter * 0.50))
            } else {
                PlaceholderLabel(diameter: diameter)
            }
            Circle().strokeBorder(Color.black.opacity(0.55), lineWidth: max(0.75, diameter * 0.006))
            Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5).padding(diameter * 0.007)
        }
        .frame(width: diameter, height: diameter)
    }
}

struct PlaceholderLabel: View {
    let diameter: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(white: 0.20), Color(white: 0.10)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            ForEach([0.82, 0.62], id: \.self) { fraction in
                Circle()
                    .stroke(Color.white.opacity(0.07), lineWidth: 0.6)
                    .frame(width: diameter * fraction, height: diameter * fraction)
            }
            Text("NEEDLE")
                .font(.system(size: diameter * 0.095, weight: .semibold))
                .tracking(diameter * 0.02)
                .foregroundColor(Color.white.opacity(0.42))
                .offset(y: -diameter * 0.16)
        }
        .frame(width: diameter, height: diameter)
    }
}

/// A dark opening, slightly larger than the spindle so a thin shadow ring shows around it.
struct VinylHole: View {
    let diameter: CGFloat

    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [Color.black, Color(white: 0.05)],
                                 center: .center, startRadius: 0, endRadius: diameter / 2))
            .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
            .frame(width: diameter, height: diameter)
    }
}

/// Everything that rotates, as one flattened layer: body, grooves, highlights and label.
/// The tonearm, spindle and platter are separate and never rotate.
struct VinylDiscView: View, Equatable {
    let appearance: VinylAppearance
    let artwork: ArtworkImage
    let animateTransitions: Bool

    static func == (lhs: VinylDiscView, rhs: VinylDiscView) -> Bool {
        lhs.appearance == rhs.appearance && lhs.artwork == rhs.artwork && lhs.animateTransitions == rhs.animateTransitions
    }

    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            ZStack {
                Crossfade(value: appearance.surface, duration: 0.45, animated: animateTransitions) { surface in
                    VinylSurfaceCanvas(surface: surface)
                }
                Crossfade(value: artwork, duration: 0.45, animated: animateTransitions) { art in
                    VinylLabel(artwork: art, diameter: d * TurntableMetrics.labelRatio)
                }
                VinylHole(diameter: d * TurntableMetrics.holeRatio)
            }
            .frame(width: d, height: d)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .drawingGroup()      // rasterize once; rotation then only transforms a texture
    }
}

/// Integrates angle over time with spin-up / spin-down ramps, so pausing coasts to a stop
/// and resuming continues from the same angle. Linear speed at full rate: one turn in 1.8 s.
final class SpinDriver: ObservableObject {
    static let fullSpeed: Double = 360.0 / 1.8       // 33⅓ RPM visual simulation, degrees per second
    let spinUpTime = 0.9
    let spinDownTime = 1.4

    private(set) var angle: Double = 0
    private(set) var velocity: Double = 0
    var targetVelocity: Double = 0
    private var lastTick: Date?

    func resetClock() { lastTick = nil }

    func advance(to date: Date) -> Double {
        defer { lastTick = date }
        guard let last = lastTick else { return angle }
        step(dt: min(max(date.timeIntervalSince(last), 0), 0.25))
        return angle
    }

    func step(dt: Double) {
        let accel = SpinDriver.fullSpeed / spinUpTime
        let decel = SpinDriver.fullSpeed / spinDownTime
        if velocity < targetVelocity {
            velocity = min(targetVelocity, velocity + accel * dt)
        } else if velocity > targetVelocity {
            velocity = max(targetVelocity, velocity - decel * dt)
        }
        angle = (angle + velocity * dt).truncatingRemainder(dividingBy: 360)
    }

    var coastDuration: Double { velocity / (SpinDriver.fullSpeed / spinDownTime) }
}

/// Rotates the flattened disc with a single animation loop (not one per groove).
/// The loop only runs while spinning or coasting to a stop, so an idle record costs nothing.
struct SpinningDisc: View {
    let disc: VinylDiscView
    let spinning: Bool

    @StateObject private var driver = SpinDriver()
    @State private var running = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !running)) { timeline in
            let angle = driver.advance(to: timeline.date)
            disc.equatable().rotationEffect(.degrees(angle))
        }
        .onAppear { update() }
        .onChange(of: spinning) { _ in update() }
    }

    private func update() {
        driver.targetVelocity = spinning ? SpinDriver.fullSpeed : 0
        if spinning {
            if !running {
                driver.resetClock()
                running = true
            }
        } else if running {
            let wait = driver.coastDuration + 0.15
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
                if driver.targetVelocity == 0 { running = false }
            }
        }
    }
}
