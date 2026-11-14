import SwiftUI

struct BackgroundImage: Equatable {
    let key: String
    let image: UIImage?
    static func == (lhs: BackgroundImage, rhs: BackgroundImage) -> Bool { lhs.key == rhs.key }
}

struct BackgroundGradient: Equatable {
    var top: RGBColor
    var bottom: RGBColor
}

/// Near-black stage with an optional soft album-art wash. A dark scrim sits on top of every
/// style, so white text stays readable no matter how bright the cover is.
struct VinylBackground: View {
    let style: BackgroundStyle
    let blur: Double
    let artwork: ArtworkImage
    let backgroundImage: UIImage?
    let palette: AlbumPalette
    let animated: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Theme.ink
                layer
                LinearGradient(colors: [Color.black.opacity(0.35), Color.black.opacity(0.62)],
                               startPoint: .top, endPoint: .bottom)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }

    @ViewBuilder private var layer: some View {
        switch style {
        case .albumBlur:
            Crossfade(value: BackgroundImage(key: artwork.key, image: backgroundImage), duration: 0.6, animated: animated) { bg in
                if let image = bg.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 18 + 60 * blur)
                        .scaleEffect(1.35)
                        .opacity(0.55)
                } else {
                    Color.clear
                }
            }
        case .adaptiveGradient:
            Crossfade(value: BackgroundGradient(top: palette.backgroundTop, bottom: palette.backgroundBottom),
                      duration: 0.6, animated: animated) { gradient in
                LinearGradient(colors: [gradient.top.color, gradient.bottom.color], startPoint: .top, endPoint: .bottom)
            }
        case .solidDark:
            Color.clear
        }
    }
}
