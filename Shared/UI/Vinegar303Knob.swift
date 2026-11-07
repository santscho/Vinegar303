import AppKit
import SwiftUI

/// Custom vector rotary control.
///
/// - Vertical drag edits the value (Shift = fine adjustment).
/// - Double-click returns to the default.
/// - The readout always shows the host-visible parameter value.
/// - Bipolar parameters draw their arc from the 12 o'clock position.
struct Vinegar303Knob: View {
    let label: String
    let valueText: String
    let normalized: Binding<Double>
    let defaultNormalized: Double
    var accent: Color = Vinegar303Theme.acid
    var isBipolar: Bool = false
    var size: CGFloat = 58
    var showsReadout: Bool = true
    var labelOverride: String? = nil
    var onEditingChanged: ((Bool) -> Void)? = nil

    @State private var dragOrigin: Double?
    @State private var hovering = false

    private let startAngle: Double = 135
    private let sweepAngle: Double = 270

    var body: some View {
        VStack(spacing: 3) {
            knobCanvas
                .frame(width: size, height: size)
                .contentShape(Rectangle())
                .gesture(dragGesture)
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        onEditingChanged?(true)
                        normalized.wrappedValue = defaultNormalized
                        onEditingChanged?(false)
                    }
                )
                .onHover { hovering = $0 }
                .accessibilityElement()
                .accessibilityLabel(label)
                .accessibilityValue(valueText)
                .accessibilityAdjustableAction { direction in
                    let step = 0.01
                    onEditingChanged?(true)
                    switch direction {
                    case .increment:
                        normalized.wrappedValue = min(normalized.wrappedValue + step, 1)
                    case .decrement:
                        normalized.wrappedValue = max(normalized.wrappedValue - step, 0)
                    @unknown default:
                        break
                    }
                    onEditingChanged?(false)
                }

            Text(label)
                .font(Vinegar303Theme.monoSmall)
                .tracking(1.0)
                .foregroundStyle(Vinegar303Theme.dim)
                .lineLimit(1)

            if showsReadout {
                Text(valueText)
                    .font(Vinegar303Theme.readout)
                    .foregroundStyle(hovering ? accent : Vinegar303Theme.text)
                    .lineLimit(1)
            }
        }
        .frame(width: max(size + 18, 74))
        .help("\(label): \(valueText)\nDrag vertically · Shift for fine · Double-click to reset")
    }

    // MARK: Gesture

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { gesture in
                if dragOrigin == nil {
                    dragOrigin = normalized.wrappedValue
                    onEditingChanged?(true)
                }
                let fine = NSEvent.modifierFlags.contains(.shift)
                let sensitivity = fine ? 0.0011 : 0.0052
                let proposed = (dragOrigin ?? normalized.wrappedValue)
                    - Double(gesture.translation.height) * sensitivity
                normalized.wrappedValue = min(max(proposed, 0), 1)
            }
            .onEnded { _ in
                dragOrigin = nil
                onEditingChanged?(false)
            }
    }

    // MARK: Drawing

    private var knobCanvas: some View {
        Canvas { context, canvasSize in
            let rect = CGRect(origin: .zero, size: canvasSize)
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius = min(rect.width, rect.height) / 2 - 7
            let value = min(max(normalized.wrappedValue, 0), 1)

            // Tick ring.
            for tick in 0...10 {
                let angle = startAngle + sweepAngle * Double(tick) / 10
                let inner = point(center: center, radius: radius + 2, angle: angle)
                let outer = point(center: center, radius: radius + 5, angle: angle)
                var tickPath = Path()
                tickPath.move(to: inner)
                tickPath.addLine(to: outer)
                let isLit = isBipolar
                    ? abs(angle - 270) <= abs(valueAngle(value) - 270) + 0.1
                    : angle <= valueAngle(value) + 0.1
                context.stroke(
                    tickPath,
                    with: .color(isLit ? accent.opacity(hovering ? 0.85 : 0.6) : Vinegar303Theme.tickInactive),
                    style: StrokeStyle(lineWidth: 1, lineCap: .round)
                )
            }

            // Track.
            let track = arc(center: center, radius: radius, from: startAngle, to: startAngle + sweepAngle)
            context.stroke(
                track,
                with: .color(Vinegar303Theme.track),
                style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
            )

            // Value arc.
            let angle = valueAngle(value)
            let arcStart = isBipolar ? 270 : startAngle
            if abs(angle - arcStart) > 0.5 {
                let valuePath = arc(
                    center: center,
                    radius: radius,
                    from: min(arcStart, angle),
                    to: max(arcStart, angle)
                )
                context.stroke(
                    valuePath,
                    with: .linearGradient(
                        Gradient(colors: [accent.opacity(0.45), accent]),
                        startPoint: CGPoint(x: rect.minX, y: rect.maxY),
                        endPoint: CGPoint(x: rect.maxX, y: rect.minY)
                    ),
                    style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                )
            }

            // Body.
            let bodyRadius = radius * 0.72
            let bodyRect = CGRect(
                x: center.x - bodyRadius,
                y: center.y - bodyRadius,
                width: bodyRadius * 2,
                height: bodyRadius * 2
            )
            context.fill(
                Path(ellipseIn: bodyRect),
                with: .radialGradient(
                    Gradient(colors: [
                        Color(red: 0.17, green: 0.18, blue: 0.21),
                        Color(red: 0.07, green: 0.075, blue: 0.09),
                        Color(red: 0.035, green: 0.038, blue: 0.045),
                    ]),
                    center: CGPoint(x: center.x - bodyRadius * 0.35, y: center.y - bodyRadius * 0.45),
                    startRadius: 1,
                    endRadius: bodyRadius * 1.25
                )
            )
            context.stroke(
                Path(ellipseIn: bodyRect),
                with: .color(Color.white.opacity(0.12)),
                lineWidth: 1
            )
            context.stroke(
                Path(ellipseIn: bodyRect.insetBy(dx: 2.5, dy: 2.5)),
                with: .color(Color.black.opacity(0.45)),
                lineWidth: 1
            )

            // Pointer.
            var pointer = Path()
            pointer.move(to: point(center: center, radius: bodyRadius * 0.34, angle: angle))
            pointer.addLine(to: point(center: center, radius: bodyRadius * 0.86, angle: angle))
            context.stroke(
                pointer,
                with: .color(accent),
                style: StrokeStyle(lineWidth: 2, lineCap: .round)
            )

            // Centre pip.
            let pip = CGRect(x: center.x - 1.4, y: center.y - 1.4, width: 2.8, height: 2.8)
            context.fill(Path(ellipseIn: pip), with: .color(accent.opacity(0.65)))
        }
        .shadow(color: hovering ? accent.opacity(0.18) : .clear, radius: 12)
    }

    private func valueAngle(_ value: Double) -> Double {
        if isBipolar {
            return 270 + (value - 0.5) * sweepAngle
        }
        return startAngle + value * sweepAngle
    }

    private func point(center: CGPoint, radius: CGFloat, angle: Double) -> CGPoint {
        let radians = angle * .pi / 180
        return CGPoint(
            x: center.x + radius * CGFloat(cos(radians)),
            y: center.y + radius * CGFloat(sin(radians))
        )
    }

    private func arc(center: CGPoint, radius: CGFloat, from: Double, to: Double) -> Path {
        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(from),
            endAngle: .degrees(to),
            clockwise: false
        )
        return path
    }
}

/// A knob wired directly to an AU parameter address.
struct Vinegar303ParameterKnob: View {
    @ObservedObject var model: ParameterModel
    @Environment(\.vinegar303MIDIController) private var midi

    let id: Vinegar303Parameter
    var accent: Color = Vinegar303Theme.acid
    var size: CGFloat = 54
    var showsReadout: Bool = true
    var labelOverride: String? = nil

    var body: some View {
        let spec = Vinegar303ParameterCatalog.spec(id)
        Vinegar303Knob(
            label: labelOverride ?? spec.name.uppercased(),
            valueText: model.displayValue(id),
            normalized: Binding(
                get: { model.normalized(id) },
                set: { model.setNormalized($0, for: id) }
            ),
            defaultNormalized: spec.normalized(spec.defaultValue),
            accent: accent,
            isBipolar: spec.isBipolar,
            size: size,
            showsReadout: showsReadout,
            onEditingChanged: { editing in
                if editing {
                    model.beginGesture(id)
                } else {
                    model.endGesture(id)
                }
            }
        )
        .vinegar303LearnBadge(for: id, midi: midi)
    }
}
