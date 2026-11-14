import SwiftUI
import UIKit
import CryptoKit

extension String {
    var sha256Hex: String {
        SHA256.hash(data: Data(utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

extension UIImage {
    /// Down-scaled copy (never enlarges). Used for the blurred background so we don't blur a 640px bitmap.
    func downscaled(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension, longest > 0 else { return self }
        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

/// Deterministic pseudo-random values (no visible repetition, identical on every launch).
enum Noise {
    static func value(_ i: Int) -> Double {
        let x = sin(Double(i) * 12.9898 + 78.233) * 43758.5453
        return x - floor(x)
    }
}

enum CacheDirectory {
    static func caches(_ name: String) -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Deletes the oldest files so at most `keep` remain.
    static func prune(_ directory: URL, keep: Int) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]),
              files.count > keep else { return }
        func date(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        let sorted = files.sorted { date($0) < date($1) }
        for file in sorted.prefix(files.count - keep) { try? fm.removeItem(at: file) }
    }
}

@MainActor
enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func confirm() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}

enum Theme {
    static let ink = Color(red: 0.035, green: 0.035, blue: 0.04)
    static let primaryText = Color.white.opacity(0.96)
    static let secondaryText = Color.white.opacity(0.70)
    static let tertiaryText = Color.white.opacity(0.54)
    static let hairline = Color.white.opacity(0.10)
    static let spotifyGreen = Color(red: 0.12, green: 0.73, blue: 0.33)
}

/// Fades between two values of anything Equatable (palettes, artwork, backgrounds) without a flash.
struct Crossfade<Value: Equatable, Content: View>: View {
    let value: Value
    var duration: Double
    var animated: Bool
    let content: (Value) -> Content

    @State private var current: Value
    @State private var outgoing: Value?
    @State private var progress: Double = 1

    init(value: Value, duration: Double = 0.45, animated: Bool = true,
         @ViewBuilder content: @escaping (Value) -> Content) {
        self.value = value
        self.duration = duration
        self.animated = animated
        self.content = content
        _current = State(initialValue: value)
    }

    var body: some View {
        ZStack {
            if let outgoing {
                content(outgoing)
            }
            content(current).opacity(progress)
        }
        .onChange(of: value) { newValue in transition(to: newValue) }
    }

    private func transition(to newValue: Value) {
        guard newValue != current else { return }
        guard animated else {
            current = newValue
            outgoing = nil
            progress = 1
            return
        }
        outgoing = current
        current = newValue
        progress = 0
        let fade = duration
        // Hop one runloop turn so the 0-opacity frame is committed before animating to 1.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            withAnimation(.easeInOut(duration: fade)) { progress = 1 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + fade + 0.08) {
            if current == newValue { outgoing = nil }
        }
    }
}
