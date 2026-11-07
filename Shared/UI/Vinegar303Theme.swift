import AppKit
import SwiftUI

enum Vinegar303AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "appearanceMode"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Auto"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var help: String {
        switch self {
        case .system: return "Follow the macOS appearance"
        case .light: return "Use the light appearance"
        case .dark: return "Use the dark appearance"
        }
    }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

private func vinegarNSColor(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
    NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
}

private func vinegarDynamicColor(light: NSColor, dark: NSColor) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
    })
}

private func vinegarDynamicNSColor(light: NSColor, dark: NSColor) -> NSColor {
    NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
    }
}

enum Vinegar303Theme {
    static let background = vinegarDynamicColor(
        light: vinegarNSColor(0.957, 0.949, 0.918),
        dark: vinegarNSColor(0.035, 0.038, 0.047)
    )
    static let backgroundNSColor = vinegarDynamicNSColor(
        light: vinegarNSColor(0.957, 0.949, 0.918),
        dark: vinegarNSColor(0.035, 0.038, 0.047)
    )
    static let panelTop = vinegarDynamicColor(
        light: vinegarNSColor(0.992, 0.988, 0.973),
        dark: vinegarNSColor(0.094, 0.101, 0.118)
    )
    static let panelBottom = vinegarDynamicColor(
        light: vinegarNSColor(0.910, 0.898, 0.855),
        dark: vinegarNSColor(0.060, 0.066, 0.078)
    )
    static let border = vinegarDynamicColor(
        light: NSColor.black.withAlphaComponent(0.12),
        dark: NSColor.white.withAlphaComponent(0.075)
    )
    static let text = vinegarDynamicColor(
        light: vinegarNSColor(0.12, 0.13, 0.15),
        dark: vinegarNSColor(0.91, 0.92, 0.94)
    )
    static let dim = vinegarDynamicColor(
        light: vinegarNSColor(0.36, 0.38, 0.42),
        dark: vinegarNSColor(0.53, 0.56, 0.62)
    )
    static let faint = vinegarDynamicColor(
        light: vinegarNSColor(0.55, 0.57, 0.61),
        dark: vinegarNSColor(0.30, 0.32, 0.37)
    )

    static let acid = vinegarDynamicColor(
        light: vinegarNSColor(0.32, 0.43, 0.02),
        dark: vinegarNSColor(0.80, 0.98, 0.32)
    )
    static let amber = vinegarDynamicColor(
        light: vinegarNSColor(0.68, 0.38, 0.00),
        dark: vinegarNSColor(1.00, 0.70, 0.28)
    )
    static let cyan = vinegarDynamicColor(
        light: vinegarNSColor(0.00, 0.43, 0.52),
        dark: vinegarNSColor(0.38, 0.84, 0.92)
    )

    static let onAccent = vinegarDynamicColor(light: .white, dark: .black)
    static let controlFill = vinegarDynamicColor(
        light: NSColor.black.withAlphaComponent(0.045),
        dark: NSColor.white.withAlphaComponent(0.04)
    )
    static let controlFillHover = vinegarDynamicColor(
        light: NSColor.black.withAlphaComponent(0.08),
        dark: NSColor.white.withAlphaComponent(0.075)
    )
    static let controlFillSubtle = vinegarDynamicColor(
        light: NSColor.black.withAlphaComponent(0.025),
        dark: NSColor.white.withAlphaComponent(0.018)
    )
    static let track = vinegarDynamicColor(
        light: NSColor.black.withAlphaComponent(0.075),
        dark: NSColor.black.withAlphaComponent(0.35)
    )
    static let insetFill = vinegarDynamicColor(
        light: NSColor.black.withAlphaComponent(0.035),
        dark: NSColor.black.withAlphaComponent(0.24)
    )
    static let insetFillSubtle = vinegarDynamicColor(
        light: NSColor.black.withAlphaComponent(0.02),
        dark: NSColor.black.withAlphaComponent(0.10)
    )
    static let insetStrong = vinegarDynamicColor(
        light: NSColor.black.withAlphaComponent(0.08),
        dark: NSColor.black.withAlphaComponent(0.72)
    )
    static let grid = vinegarDynamicColor(
        light: NSColor.black.withAlphaComponent(0.07),
        dark: NSColor.white.withAlphaComponent(0.04)
    )
    static let tickInactive = vinegarDynamicColor(
        light: NSColor.black.withAlphaComponent(0.18),
        dark: NSColor.white.withAlphaComponent(0.08)
    )
    static let hostBar = vinegarDynamicColor(
        light: NSColor.black.withAlphaComponent(0.04),
        dark: NSColor.black.withAlphaComponent(0.28)
    )

    static let mono = Font.system(size: 10, weight: .medium, design: .monospaced)
    static let monoSmall = Font.system(size: 8.5, weight: .medium, design: .monospaced)
    static let label = Font.system(size: 9, weight: .semibold, design: .default)
    static let readout = Font.system(size: 9.5, weight: .semibold, design: .monospaced)
}

struct Vinegar303AppearanceSwitcher: View {
    @Binding var selection: Vinegar303AppearanceMode

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Vinegar303AppearanceMode.allCases) { mode in
                Button {
                    selection = mode
                } label: {
                    Image(systemName: mode.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(selection == mode ? Vinegar303Theme.onAccent : Vinegar303Theme.dim)
                        .frame(width: 28, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(selection == mode ? Vinegar303Theme.acid : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(mode.help)
                .accessibilityLabel(Text(mode.title))
                .accessibilityValue(Text(selection == mode ? "Selected" : ""))
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Vinegar303Theme.controlFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Vinegar303Theme.border, lineWidth: 1)
        )
    }
}

// MARK: - Panel chrome

struct Vinegar303Panel<Content: View>: View {
    let title: String
    let accent: Color
    let content: Content

    init(_ title: String, accent: Color, @ViewBuilder content: () -> Content) {
        self.title = title
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Capsule()
                    .fill(accent)
                    .frame(width: 14, height: 2)
                Text(title)
                    .font(Vinegar303Theme.label)
                    .tracking(1.6)
                    .foregroundStyle(Vinegar303Theme.dim)
                Spacer(minLength: 0)
            }

            content
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Vinegar303Theme.panelTop, Vinegar303Theme.panelBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Vinegar303Theme.border, lineWidth: 1)
        )
    }
}

// MARK: - Header controls

struct Vinegar303RunButton: View {
    let isRunning: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isRunning ? "stop.fill" : "play.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isRunning ? Vinegar303Theme.onAccent : Vinegar303Theme.text)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(isRunning ? Vinegar303Theme.acid : Vinegar303Theme.controlFill)
                )
                .overlay(
                    Circle()
                        .stroke(isRunning ? Vinegar303Theme.acid.opacity(0.7) : Vinegar303Theme.border, lineWidth: 1)
                )
                .shadow(color: isRunning ? Vinegar303Theme.acid.opacity(0.35) : .clear, radius: 10)
        }
        .buttonStyle(.plain)
        .help(isRunning ? "Stop the internal sequencer" : "Run the internal sequencer")
    }
}

struct Vinegar303Chip: View {
    let caption: String
    let value: String
    let accent: Color
    var isActive: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                Text(caption)
                    .font(.system(size: 7.5, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(Vinegar303Theme.faint)
                Text(value)
                    .font(Vinegar303Theme.readout)
                    .foregroundStyle(isActive ? accent : Vinegar303Theme.text)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(hovering ? Vinegar303Theme.controlFillHover : Vinegar303Theme.controlFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isActive ? accent.opacity(0.5) : Vinegar303Theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct Vinegar303MenuChip: View {
    let caption: String
    let value: String
    let accent: Color
    let isActive: Bool
    let options: [String]
    let selectedIndex: Int?
    let onSelect: (Int) -> Void

    @State private var hovering = false
    @State private var showingOptions = false
    @Environment(\.colorScheme) private var colorScheme

    init(
        caption: String,
        value: String,
        accent: Color,
        isActive: Bool = false,
        options: [String],
        selectedIndex: Int? = nil,
        onSelect: @escaping (Int) -> Void
    ) {
        self.caption = caption
        self.value = value
        self.accent = accent
        self.isActive = isActive
        self.options = options
        self.selectedIndex = selectedIndex
        self.onSelect = onSelect
    }

    var body: some View {
        Button {
            showingOptions.toggle()
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(caption)
                    .font(.system(size: 7.5, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(Vinegar303Theme.faint)
                HStack(spacing: 3) {
                    Text(value)
                        .font(Vinegar303Theme.readout)
                        .foregroundStyle(isActive ? accent : Vinegar303Theme.text)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundStyle(Vinegar303Theme.faint)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(hovering ? Vinegar303Theme.controlFillHover : Vinegar303Theme.controlFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isActive ? accent.opacity(0.5) : Vinegar303Theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { hovering = $0 }
        .help("\(caption): \(value)")
        .popover(isPresented: $showingOptions, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(options.indices, id: \.self) { index in
                    Button {
                        onSelect(index)
                        showingOptions = false
                    } label: {
                        HStack(spacing: 8) {
                            Text(options[index])
                                .font(Vinegar303Theme.monoSmall)
                            Spacer(minLength: 16)
                            if selectedIndex == index {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8, weight: .bold))
                            }
                        }
                        .foregroundStyle(selectedIndex == index ? accent : Vinegar303Theme.text)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .frame(minWidth: 118, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(selectedIndex == index ? accent.opacity(0.12) : Color.clear)
                    )
                }
            }
            .padding(5)
            .background(Vinegar303Theme.background)
            .preferredColorScheme(colorScheme)
        }
    }
}

struct Vinegar303Stepper: View {
    let value: String
    let onBack: () -> Void
    let onForward: () -> Void
    var accent: Color = Vinegar303Theme.acid

    var body: some View {
        HStack(spacing: 2) {
            stepButton("chevron.left", action: onBack)
            Text(value)
                .font(Vinegar303Theme.readout)
                .foregroundStyle(accent)
                .frame(minWidth: 30)
            stepButton("chevron.right", action: onForward)
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Vinegar303Theme.controlFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Vinegar303Theme.border, lineWidth: 1)
        )
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Vinegar303Theme.dim)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct Vinegar303WaveformSwitch: View {
    let isSaw: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        HStack(spacing: 2) {
            segment(title: "SQR", selected: !isSaw) { onChange(false) }
            segment(title: "SAW", selected: isSaw) { onChange(true) }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Vinegar303Theme.track)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Vinegar303Theme.border, lineWidth: 1)
        )
    }

    private func segment(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Vinegar303Theme.readout)
                .foregroundStyle(selected ? Vinegar303Theme.onAccent : Vinegar303Theme.dim)
                .frame(width: 40, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(selected ? Vinegar303Theme.cyan : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}

struct Vinegar303ToggleDot: View {
    let symbol: String
    let isOn: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(symbol)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(isOn ? Vinegar303Theme.onAccent : Vinegar303Theme.faint)
                .frame(maxWidth: .infinity)
                .frame(height: 15)
                .background(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(isOn ? accent : Vinegar303Theme.controlFill)
                )
        }
        .buttonStyle(.plain)
    }
}
