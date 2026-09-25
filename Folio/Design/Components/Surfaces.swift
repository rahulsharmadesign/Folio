import SwiftUI

/// `grain.png` tiled at 320 pt, like `.grain { background-size: 320px 320px }` in the source.
struct GrainLayer: View {
    var opacity: Double

    var body: some View {
        Image("grain")
            .resizable(resizingMode: .tile)
            .opacity(opacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The theme's paper colour, optionally with grain (the reader and cards use it; Today's canvas doesn't).
struct PaperBackground: View {
    @Environment(Theme.self) private var theme
    var color: Color?
    var grain: Bool = true
    var grainOpacity: Double?

    var body: some View {
        ZStack {
            (color ?? theme.background)
            if grain {
                GrainLayer(opacity: grainOpacity ?? theme.palette.grainOpacity)
            }
        }
        .ignoresSafeArea()
    }
}

/// One watercolour PNG, placed like an absolutely-positioned `<img>` in the source.
struct WashLayer: Sendable {
    enum Edge: Sendable { case leading, trailing }

    var asset: String
    /// Which edge `x` is measured from (CSS `left` or `right`).
    var edge: Edge = .leading
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat
    var opacity: Double

    static func left(_ asset: String, _ x: CGFloat, top y: CGFloat, _ width: CGFloat, _ height: CGFloat, opacity: Double) -> WashLayer {
        WashLayer(asset: asset, edge: .leading, x: x, y: y, width: width, height: height, opacity: opacity)
    }

    static func right(_ asset: String, _ x: CGFloat, top y: CGFloat, _ width: CGFloat, _ height: CGFloat, opacity: Double) -> WashLayer {
        WashLayer(asset: asset, edge: .trailing, x: x, y: y, width: width, height: height, opacity: opacity)
    }
}

/// Layered watercolour washes composited with multiply, then grain, over a ground colour.
struct WashCover: View {
    @Environment(Theme.self) private var theme
    var layers: [WashLayer]
    var ground: Color?
    var grainOpacity: Double = 0.8

    var body: some View {
        (ground ?? theme.coverGround)
            .overlay { WashStack(layers: layers) }
            .overlay { GrainLayer(opacity: grainOpacity) }
            .clipped()
            .accessibilityHidden(true)
    }
}

/// Just the washes, multiplied onto whatever is behind them.
struct WashStack: View {
    var layers: [WashLayer]

    var body: some View {
        GeometryReader { geo in
            ForEach(layers.indices, id: \.self) { i in
                let l = layers[i]
                let originX = l.edge == .leading ? l.x : geo.size.width - l.x - l.width
                Image(l.asset)
                    .resizable()
                    .frame(width: l.width, height: l.height)
                    .opacity(l.opacity)
                    .blendMode(.multiply)
                    .position(x: originX + l.width / 2, y: l.y + l.height / 2)
            }
        }
        .allowsHitTesting(false)
    }
}
