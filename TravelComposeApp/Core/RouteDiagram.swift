import SwiftUI

// MARK: - Abstract Route Diagram
//
// SwiftUI port of the `RouteDiagram` SVG component from
// `car-pool/project/tokens.jsx`. A stylised, non-map "route" visual
// for use on Ride Detail and Live Tracking. The codebase already has
// `MapPlaceholder` (Polished.swift) for the picker/preview surfaces;
// this component is the *narrative* version — a curving polyline
// through 4 anchor points over a faint city grid + abstract land/water
// shapes — meant for hero cards, not for picking a location.
//
// Renders the same visual whether 2 or N stops are passed; intermediate
// stops snap to the nearest anchor. Callers pass `dark: true` for the
// tracking screen's full-bleed dark variant.

struct RouteStop: Hashable {
    let label: String
    let kind: Kind
    enum Kind { case origin, stop, dest }
}

struct VRouteDiagram: View {
    var stops: [RouteStop]
    var height: CGFloat = 200
    var accent: Color = VPalette.success
    var dark: Bool = false

    private var landColor: Color {
        dark ? Color(hex: 0x0B2238) : Color(hex: 0xEEF2F1)
    }
    private var waterColor: Color {
        dark ? Color(hex: 0x0F2A45) : Color(hex: 0xDCE8EE)
    }
    private var gridColor: Color {
        dark ? Color.white.opacity(0.06) : VPalette.text.opacity(0.05)
    }
    private var blockColor: Color {
        dark ? Color(hex: 0x143654) : Color(hex: 0xE2E8E2)
    }
    private var pinFill: Color {
        dark ? Color(hex: 0x0E1B2C) : .white
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = height
            let pts: [CGPoint] = [
                CGPoint(x: 40,         y: h - 36),
                CGPoint(x: w * 0.32,   y: h * 0.36),
                CGPoint(x: w * 0.66,   y: h * 0.66),
                CGPoint(x: w - 40,     y: 36)
            ]

            ZStack {
                landColor

                // Land/water blobs
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h * 0.6))
                    p.addQuadCurve(to: CGPoint(x: w * 0.55, y: h * 0.62),
                                   control: CGPoint(x: w * 0.3, y: h * 0.5))
                    p.addQuadCurve(to: CGPoint(x: w, y: h * 0.55),
                                   control: CGPoint(x: w * 0.78, y: h * 0.7))
                    p.addLine(to: CGPoint(x: w, y: h))
                    p.addLine(to: CGPoint(x: 0, y: h))
                    p.closeSubpath()
                }
                .fill(waterColor.opacity(dark ? 0.4 : 0.55))

                Path { p in
                    p.move(to: CGPoint(x: w * 0.05, y: h * 0.18))
                    p.addQuadCurve(to: CGPoint(x: w * 0.35, y: h * 0.2),
                                   control: CGPoint(x: w * 0.2, y: h * 0.1))
                    p.addLine(to: CGPoint(x: w * 0.32, y: h * 0.32))
                    p.addQuadCurve(to: CGPoint(x: w * 0.05, y: h * 0.3),
                                   control: CGPoint(x: w * 0.18, y: h * 0.28))
                    p.closeSubpath()
                }
                .fill(waterColor.opacity(dark ? 0.3 : 0.4))

                // Grid
                Path { p in
                    let cols = 8, rows = 5
                    for i in 0...cols {
                        let x = w * CGFloat(i) / CGFloat(cols)
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x, y: h))
                    }
                    for i in 0...rows {
                        let y = h * CGFloat(i) / CGFloat(rows)
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: w, y: y))
                    }
                }
                .stroke(gridColor, lineWidth: 1)

                // Block buildings
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(blockColor)
                    .frame(width: 40, height: 28)
                    .position(x: w * 0.1 + 20, y: h * 0.7 + 14)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(blockColor)
                    .frame(width: 28, height: 44)
                    .position(x: w * 0.46 + 14, y: h * 0.18 + 22)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(blockColor)
                    .frame(width: 36, height: 22)
                    .position(x: w * 0.76 + 18, y: h * 0.55 + 11)

                // Route shadow + path
                routePath(points: pts)
                    .stroke(
                        dark ? Color.white.opacity(0.15) : Color.black.opacity(0.08),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .offset(y: 2)
                routePath(points: pts)
                    .stroke(accent, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))

                // Stop dots
                ForEach(Array(stops.enumerated()), id: \.offset) { i, stop in
                    let denom = max(1, stops.count - 1)
                    let idx = Int((Double(i) / Double(denom)) * Double(pts.count - 1) + 0.5)
                    let center = pts[min(idx, pts.count - 1)]
                    stopDot(stop: stop)
                        .position(center)
                }
            }
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .frame(height: height)
    }

    @ViewBuilder
    private func stopDot(stop: RouteStop) -> some View {
        let outline: Color = {
            switch stop.kind {
            case .origin: return VPalette.primary
            case .dest:   return accent
            case .stop:   return VPalette.textHint
            }
        }()
        let inner: Color = {
            switch stop.kind {
            case .origin: return VPalette.primary
            case .dest:   return accent
            case .stop:   return VPalette.textHint
            }
        }()
        ZStack {
            Circle().fill(pinFill)
            Circle().stroke(outline, lineWidth: 2.5)
            Circle().fill(inner).frame(width: stop.kind == .stop ? 6 : 8, height: stop.kind == .stop ? 6 : 8)
        }
        .frame(width: 22, height: 22)
    }

    /// Smooth cubic curve through the 4 anchor points. Mirrors the JS
    /// path string `M… C…  S… S…` from the source component, which
    /// gives the diagram its characteristic gentle "S" sweep.
    private func routePath(points pts: [CGPoint]) -> Path {
        var p = Path()
        guard pts.count >= 4 else {
            if let first = pts.first { p.move(to: first) }
            for pt in pts.dropFirst() { p.addLine(to: pt) }
            return p
        }
        p.move(to: pts[0])
        p.addCurve(
            to: pts[1],
            control1: CGPoint(x: pts[0].x + 60, y: pts[0].y - 80),
            control2: CGPoint(x: pts[1].x - 50, y: pts[1].y + 40)
        )
        // Reflect the last control around pts[1] for a smooth "S" join.
        let r1 = reflect(CGPoint(x: pts[1].x - 50, y: pts[1].y + 40), through: pts[1])
        p.addCurve(
            to: pts[2],
            control1: r1,
            control2: CGPoint(x: pts[2].x + 10, y: pts[2].y - 40)
        )
        let r2 = reflect(CGPoint(x: pts[2].x + 10, y: pts[2].y - 40), through: pts[2])
        p.addCurve(
            to: pts[3],
            control1: r2,
            control2: CGPoint(x: pts[3].x - 30, y: pts[3].y + 60)
        )
        return p
    }

    private func reflect(_ pt: CGPoint, through pivot: CGPoint) -> CGPoint {
        CGPoint(x: 2 * pivot.x - pt.x, y: 2 * pivot.y - pt.y)
    }
}

#Preview("Route diagram — light") {
    VRouteDiagram(
        stops: [
            .init(label: "Subang Jaya", kind: .origin),
            .init(label: "USJ 9 LRT",   kind: .stop),
            .init(label: "Bangsar",     kind: .stop),
            .init(label: "KLCC",        kind: .dest)
        ]
    )
    .padding()
    .background(VPalette.bg)
}

#Preview("Route diagram — dark") {
    VRouteDiagram(
        stops: [
            .init(label: "Subang Jaya", kind: .origin),
            .init(label: "KLCC",        kind: .dest)
        ],
        dark: true
    )
    .padding()
    .background(Color.black)
}
