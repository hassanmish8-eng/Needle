import UIKit
import CoreGraphics

/// Deterministic album-art analysis: downsample, bucket, cluster, rank, build palette.
enum ColorExtractor {
    static let analysisSize = 64
    static let mergeThreshold = 0.30
    static let maxClusters = 12

    /// Returns nil when the image is unusable (no CGImage, tiny, or fully transparent).
    static func extract(from image: UIImage) -> AlbumPalette? {
        guard let cg = image.cgImage, cg.width >= 8, cg.height >= 8,
              let pixels = rasterize(cg, side: analysisSize) else { return nil }
        return palette(fromRGBA: pixels)
    }

    /// Renders a center-cropped `side x side` RGBA (premultiplied) copy.
    static func rasterize(_ image: CGImage, side: Int) -> [UInt8]? {
        let bytesPerRow = side * 4
        var data = [UInt8](repeating: 0, count: side * bytesPerRow)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        let ok: Bool = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: side, height: side,
                                      bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                      space: space, bitmapInfo: info) else { return false }
            ctx.interpolationQuality = .medium
            let w = CGFloat(image.width), h = CGFloat(image.height)
            let s = CGFloat(side)
            let scale = max(s / w, s / h)
            let dw = w * scale, dh = h * scale
            ctx.draw(image, in: CGRect(x: (s - dw) / 2, y: (s - dh) / 2, width: dw, height: dh))
            return true
        }
        return ok ? data : nil
    }

    /// Core algorithm, separated from UIKit so tests can feed raw pixels.
    static func palette(fromRGBA data: [UInt8]) -> AlbumPalette? {
        struct Bucket { var weight = 0.0, r = 0.0, g = 0.0, b = 0.0 }
        var buckets: [Int: Bucket] = [:]
        var opaque = 0
        var colorful = 0
        var lightnessSum = 0.0
        var totalWeight = 0.0

        let pixelCount = data.count / 4
        for i in 0..<pixelCount {
            let o = i * 4
            let a = Int(data[o + 3])
            if a < 128 { continue }                       // ignore (mostly) transparent pixels
            let rr = min(255, Int(data[o]) * 255 / a)     // un-premultiply
            let gg = min(255, Int(data[o + 1]) * 255 / a)
            let bb = min(255, Int(data[o + 2]) * 255 / a)
            let color = RGBColor(Double(rr) / 255, Double(gg) / 255, Double(bb) / 255)
            let hsl = color.hsl

            opaque += 1
            lightnessSum += hsl.l
            if hsl.s >= 0.2 && hsl.l >= 0.12 && hsl.l <= 0.92 { colorful += 1 }

            // Less weight for near-white highlights, near-black shadows and neutral backgrounds.
            var w = 0.6 + 0.8 * hsl.s
            if hsl.l > 0.93 && hsl.s < 0.25 {
                w *= 0.15
            } else if hsl.l < 0.10 {
                w *= 0.25
            } else if hsl.s < 0.12 {
                w *= 0.45
            }

            let key = ((rr >> 4) << 8) | ((gg >> 4) << 4) | (bb >> 4)
            var bucket = buckets[key] ?? Bucket()
            bucket.weight += w
            bucket.r += w * color.r
            bucket.g += w * color.g
            bucket.b += w * color.b
            buckets[key] = bucket
            totalWeight += w
        }
        guard opaque > 0, totalWeight > 0 else { return nil }

        // Heaviest first; key order breaks ties so the result never depends on dictionary order.
        let ordered = buckets.sorted { a, b in
            a.value.weight != b.value.weight ? a.value.weight > b.value.weight : a.key < b.key
        }

        var accum: [(r: Double, g: Double, b: Double, w: Double)] = []
        for (_, bucket) in ordered {
            let mean = RGBColor(bucket.r / bucket.weight, bucket.g / bucket.weight, bucket.b / bucket.weight)
            var best = -1
            var bestDistance = Double.infinity
            for (index, c) in accum.enumerated() {
                let d = RGBColor.distance(mean, RGBColor(c.r / c.w, c.g / c.w, c.b / c.w))
                if d < bestDistance { bestDistance = d; best = index }
            }
            if best >= 0 && (bestDistance < mergeThreshold || accum.count >= maxClusters) {
                accum[best].r += bucket.r
                accum[best].g += bucket.g
                accum[best].b += bucket.b
                accum[best].w += bucket.weight
            } else {
                accum.append((r: bucket.r, g: bucket.g, b: bucket.b, w: bucket.weight))
            }
        }

        let clusters = accum.map {
            ColorCluster(color: RGBColor($0.r / $0.w, $0.g / $0.w, $0.b / $0.w), weight: $0.w / totalWeight)
        }
        return PaletteBuilder.build(clusters: clusters,
                                    meanLightness: lightnessSum / Double(opaque),
                                    colorfulFraction: Double(colorful) / Double(opaque))
    }
}
