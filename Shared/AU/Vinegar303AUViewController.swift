import AppKit
import AudioToolbox
import CoreAudioKit
import SwiftUI

private enum Vinegar303PluginMetrics {
    /// The AUv3 editor uses a 1300×738 canvas so the complete two-row section
    /// layout, footer and status text fit without empty bands or overlap. The
    /// plugin host controls the outer container size; the SwiftUI wrapper
    /// scales this canvas to fit without changing its proportions.
    static let nativeContentSize = NSSize(width: 1_300, height: 738)
}

/// Fixed-canvas SwiftUI wrapper for the AUv3 editor. AU hosts are free to give
/// the view a different aspect ratio while resizing, so the editor is laid out
/// at its design size and uniformly scaled to fit the largest area possible.
private struct Vinegar303PluginView: View {
    let parameterTree: AUParameterTree
    let patterns: PatternStore
    let presets: Vinegar303PresetController
    let playhead: () -> Int

    var body: some View {
        GeometryReader { proxy in
            let design = Vinegar303PluginMetrics.nativeContentSize
            let size = proxy.size
            let scale = size.width > 0 && size.height > 0
                ? min(size.width / design.width, size.height / design.height)
                : 1

            Vinegar303Editor(
                parameterTree: parameterTree,
                patterns: patterns,
                presets: presets,
                playhead: playhead
            )
            .frame(width: design.width, height: design.height)
            .scaleEffect(scale, anchor: .center)
            .frame(width: size.width, height: size.height)
        }
        .background(Vinegar303Theme.background)
        .preferredColorScheme(.dark)
    }
}

/// AUv3 custom view controller. The audio unit is created by the extension
/// factory and its parameter tree drives the same SwiftUI editor that the host
/// app uses.
public final class Vinegar303AUViewController: AUViewController, AUAudioUnitFactory {
    private var audioUnitInstance: Vinegar303AudioUnit?
    private var patternStore: PatternStore?
    private var presetController: Vinegar303PresetController?
    private var hostingView: NSHostingView<Vinegar303PluginView>?

    public func createAudioUnit(with componentDescription: AudioComponentDescription) throws -> AUAudioUnit {
        let unit = try Vinegar303AudioUnit(componentDescription: componentDescription)
        audioUnitInstance = unit
        installEditorIfPossible()
        return unit
    }

    public override func loadView() {
        let size = Vinegar303PluginMetrics.nativeContentSize
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(red: 0.035, green: 0.038, blue: 0.047, alpha: 1).cgColor
        view = container
        preferredContentSize = size
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        installEditorIfPossible()
    }

    public override func viewWillAppear() {
        super.viewWillAppear()
        installEditorIfPossible()
        configureHostWindowAspect()
    }

    public override func viewDidAppear() {
        super.viewDidAppear()
        configureHostWindowAspect()
    }

    private func installEditorIfPossible() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.installEditorIfPossible()
            }
            return
        }
        guard let unit = audioUnitInstance, hostingView == nil else { return }

        let store = PatternStore(patterns: unit.patterns) { [weak unit] patterns in
            unit?.patterns = patterns
        }
        patternStore = store
        let presets = Vinegar303PresetController(
            library: Vinegar303PresetLibrary(),
            parameterTree: unit.editorParameterTree,
            patterns: store
        )
        presetController = presets

        let pluginView = Vinegar303PluginView(
            parameterTree: unit.editorParameterTree,
            patterns: store,
            presets: presets,
            playhead: { [weak unit] in unit?.playheadStep ?? -1 }
        )
        let hosting = NSHostingView(rootView: pluginView)
        // Publish before touching `view`, which may synchronously trigger
        // viewDidLoad and re-enter this method.
        hostingView = hosting
        hosting.frame = view.bounds
        hosting.autoresizingMask = [.width, .height]
        view.addSubview(hosting)
    }

    private func configureHostWindowAspect() {
        guard let window = view.window else { return }
        window.contentAspectRatio = Vinegar303PluginMetrics.nativeContentSize
    }
}
