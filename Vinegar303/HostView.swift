import AppKit
import SwiftUI

enum Vinegar303WindowMetrics {
    /// The editor's width is fixed at 1300 px. Height is content-driven: the
    /// window is initially sized from the SwiftUI layout and can grow
    /// vertically without changing the horizontal canvas.
    static let nativeWidth: CGFloat = 1_300
    static let initialContentHeight: CGFloat = 900
    /// The editor's top strip, including 15 px of additional breathing room
    /// below the native traffic lights.
    static let titlebarInset: CGFloat = 39
}

struct Vinegar303HostView: View {
    @ObservedObject var host: Vinegar303Host
    @AppStorage(Vinegar303AppearanceMode.storageKey)
    private var appearanceRawValue = Vinegar303AppearanceMode.system.rawValue

    private var appearanceMode: Vinegar303AppearanceMode {
        Vinegar303AppearanceMode(rawValue: appearanceRawValue) ?? .system
    }

    var body: some View {
        hostContent
            .frame(width: Vinegar303WindowMetrics.nativeWidth)
            .background(Vinegar303Theme.background)
            .background(Vinegar303WindowConfigurator(appearance: appearanceMode))
            .background(Vinegar303SpacebarMonitor(action: host.toggleRun))
            .preferredColorScheme(appearanceMode.colorScheme)
    }

    private var hostContent: some View {
        let unit = host.audioUnit
        return VStack(spacing: 0) {
            Color.clear
                .frame(height: Vinegar303WindowMetrics.titlebarInset)

            Vinegar303Editor(
                parameterTree: unit.editorParameterTree,
                patterns: host.patterns,
                presets: host.presets,
                playhead: { unit.playheadStep },
                midi: host.midi
            )
            .fixedSize(horizontal: false, vertical: true)

            hostBar
        }
        .frame(width: Vinegar303WindowMetrics.nativeWidth)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var hostBar: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(host.status == "AUDIO RUNNING" ? Vinegar303Theme.acid : Vinegar303Theme.amber)
                .frame(width: 5, height: 5)

            Text(host.status)
                .font(Vinegar303Theme.monoSmall)
                .tracking(1.1)
                .foregroundStyle(Vinegar303Theme.dim)

            if host.sampleRate > 0 {
                Text("· \(Int(host.sampleRate)) Hz")
                    .font(Vinegar303Theme.monoSmall)
                    .foregroundStyle(Vinegar303Theme.faint)
            }

            Text("· LIVE AUv3 KERNEL")
                .font(Vinegar303Theme.monoSmall)
                .foregroundStyle(Vinegar303Theme.faint)

            Spacer(minLength: 10)

            Text("Embedded AUv3: select “Vinegar303” in your DAW’s instrument list.")
                .font(Vinegar303Theme.monoSmall)
                .foregroundStyle(Vinegar303Theme.faint)

            Vinegar303AuditionPad(onPress: { host.auditionOn() }, onRelease: { host.auditionOff() })
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(Vinegar303Theme.hostBar)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Vinegar303Theme.border)
                .frame(height: 1)
        }
    }
}

/// Handles the standalone transport shortcut without taking focus away from
/// SwiftUI controls. The AUv3 editor does not install this monitor because the
/// host application owns keyboard transport shortcuts.
private struct Vinegar303SpacebarMonitor: NSViewRepresentable {
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.start()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.action = action
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        var action: () -> Void
        private var monitor: Any?

        init(action: @escaping () -> Void) {
            self.action = action
        }

        deinit {
            stop()
        }

        func start() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                let disallowedModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
                guard event.keyCode == 49,
                      event.charactersIgnoringModifiers == " ",
                      !event.isARepeat,
                      event.window?.isKeyWindow == true,
                      event.modifierFlags.intersection(disallowedModifiers).isEmpty,
                      !(event.window?.firstResponder is NSTextView)
                else {
                    return event
                }

                self.action()
                return nil
            }
        }

        func stop() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }
    }
}

/// Applies the height-flexible window policy to the SwiftUI-created NSWindow
/// without replacing its delegate.
private struct Vinegar303WindowConfigurator: NSViewRepresentable {
    let appearance: Vinegar303AppearanceMode

    final class Coordinator {
        weak var window: NSWindow?
        var isConfigured = false
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { [weak view, weak coordinator = context.coordinator] in
            guard let view else { return }
            configure(window: view.window, coordinator: coordinator)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        applyAppearance(window: nsView.window)
        DispatchQueue.main.async { [weak nsView, weak coordinator = context.coordinator] in
            guard let nsView else { return }
            configure(window: nsView.window, coordinator: coordinator)
        }
    }

    private func applyAppearance(window: NSWindow?) {
        guard let window else { return }
        let desired = appearance.nsAppearance
        if window.appearance?.name != desired?.name {
            window.appearance = desired
        }
    }

    private func configure(window: NSWindow?, coordinator: Coordinator?) {
        guard let window, let coordinator else { return }

        if coordinator.window !== window {
            coordinator.window = window
            coordinator.isConfigured = false
        }
        guard !coordinator.isConfigured else { return }

        // Match the native titlebar and traffic lights to the selected mode.
        // A standard titlebar also keeps the editor out from under the window
        // chrome.
        applyAppearance(window: window)

        // Keep the native traffic lights over the custom titlebar strip. The
        // editor content begins below that strip, so the chrome no longer
        // overlays the interface.
        window.styleMask.insert(.fullSizeContentView)
        window.styleMask.insert(.resizable)
        window.isMovableByWindowBackground = true

        // The editor canvas is width-locked but height-flexible. The initial
        // content height includes the new SCALE AWARE section and the host
        // status bar; resizing vertically gives the editor more room rather
        // than cropping its header or footer.
        window.collectionBehavior.remove(.fullScreenPrimary)
        window.collectionBehavior.remove(.fullScreenAuxiliary)
        window.collectionBehavior.insert(.fullScreenNone)
        window.standardWindowButton(.zoomButton)?.isHidden = true
        // Measure the actual SwiftUI canvas instead of hard-coding a height.
        // Adding a section changes the ideal height; the standalone window
        // follows it while keeping the 1300 px width fixed.
        window.contentView?.layoutSubtreeIfNeeded()
        let fittingHeight = window.contentView?.fittingSize.height ?? 0
        let contentHeight = max(
            fittingHeight > 0 ? fittingHeight : Vinegar303WindowMetrics.initialContentHeight,
            640
        )
        window.contentMinSize = NSSize(width: Vinegar303WindowMetrics.nativeWidth, height: contentHeight)
        window.contentMaxSize = NSSize(
            width: Vinegar303WindowMetrics.nativeWidth,
            height: 2_000
        )
        window.setContentSize(NSSize(width: Vinegar303WindowMetrics.nativeWidth, height: contentHeight))
        placeWindowOnScreen(window)
        coordinator.isConfigured = true
    }

    private func placeWindowOnScreen(_ window: NSWindow) {
        window.center()
        guard let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame

        var frame = window.frame
        let maxX = visible.maxX - frame.width
        let minY = visible.minY
        let maxY = visible.maxY - frame.height
        frame.origin.x = min(max(frame.minX, visible.minX), maxX)
        frame.origin.y = min(max(frame.minY, minY), maxY)
        window.setFrameOrigin(frame.origin)
    }
}

private struct Vinegar303AuditionPad: View {
    let onPress: () -> Void
    let onRelease: () -> Void

    @State private var isDown = false

    var body: some View {
        Text(isDown ? "C3 ON" : "HOLD C3")
            .font(Vinegar303Theme.monoSmall)
            .tracking(1.0)
            .foregroundStyle(isDown ? Vinegar303Theme.onAccent : Vinegar303Theme.acid)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isDown ? Vinegar303Theme.acid : Vinegar303Theme.controlFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(Vinegar303Theme.acid.opacity(0.4), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isDown else { return }
                        isDown = true
                        onPress()
                    }
                    .onEnded { _ in
                        guard isDown else { return }
                        isDown = false
                        onRelease()
                    }
            )
            .onDisappear {
                if isDown {
                    isDown = false
                    onRelease()
                }
            }
            .help("Hold to send a MIDI note to the audio unit")
    }
}
