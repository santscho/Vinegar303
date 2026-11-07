import SwiftUI

enum Vinegar303Theme {
    static let background = Color(red: 0.035, green: 0.038, blue: 0.047)
    static let panelTop = Color(red: 0.094, green: 0.101, blue: 0.118)
    static let panelBottom = Color(red: 0.060, green: 0.066, blue: 0.078)
    static let border = Color.white.opacity(0.075)
    static let text = Color(red: 0.91, green: 0.92, blue: 0.94)
    static let dim = Color(red: 0.53, green: 0.56, blue: 0.62)
    static let faint = Color(red: 0.30, green: 0.32, blue: 0.37)

    static let acid = Color(red: 0.80, green: 0.98, blue: 0.32)
    static let amber = Color(red: 1.00, green: 0.70, blue: 0.28)
    static let cyan = Color(red: 0.38, green: 0.84, blue: 0.92)

    static let mono = Font.system(size: 10, weight: .medium, design: .monospaced)
    static let monoSmall = Font.system(size: 8.5, weight: .medium, design: .monospaced)
    static let label = Font.system(size: 9, weight: .semibold, design: .default)
    static let readout = Font.system(size: 9.5, weight: .semibold, design: .monospaced)
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
                .foregroundStyle(isRunning ? Color.black : Vinegar303Theme.text)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(isRunning ? Vinegar303Theme.acid : Color.white.opacity(0.06))
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
                    .fill(Color.white.opacity(hovering ? 0.075 : 0.04))
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
                    .fill(Color.white.opacity(hovering ? 0.075 : 0.04))
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
            .preferredColorScheme(.dark)
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
                .fill(Color.white.opacity(0.04))
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
                .fill(Color.black.opacity(0.35))
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
                .foregroundStyle(selected ? Color.black : Vinegar303Theme.dim)
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
                .foregroundStyle(isOn ? Color.black : Vinegar303Theme.faint)
                .frame(maxWidth: .infinity)
                .frame(height: 15)
                .background(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(isOn ? accent : Color.white.opacity(0.05))
                )
        }
        .buttonStyle(.plain)
    }
}
