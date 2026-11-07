# Vinegar303

A clean-room, open-source acid bassline instrument for macOS, built in Swift as
an **AUv3** audio unit with a native SwiftUI editor.

Vinegar303 is fully unlocked: there is no serial number, license activation,
demo timer, telemetry, networking or phone-home code anywhere in the project.

## Features

- Monophonic 303-style voice: PolyBLEP saw/square oscillator, four-pole
  saturating ladder filter, decay envelope, VCA, drive and post-filter
  distortion.
- 16-step sequencer with per-step note, gate, accent and slide, host tempo sync
  and a free-running mode.
- Scale-aware pitch quantization with seven modes, key selection and a global
  transpose bypass.
- 16 patterns stored with the plug-in state, so patterns travel with the session;
  every pattern carries its own 1–16 step length. The built-in factory bank
  ships with all 16 pattern slots filled.
- File-backed presets with categories, fast browsing in the sequencer header,
  pattern-only or full sound/scale capture, and pattern copying between presets.
- AUv3 instrument (`aumu`, subtype `Vg03`) with a full parameter tree for
  automation and a custom SwiftUI editor.
- Standalone CoreMIDI input with hot-plug discovery, a global Omni/1–16 channel
  filter, MIDI Learn on every knob, and JSON controller profiles.
- Host app wrapper that runs the same audio unit through an `AVAudioEngine`
  source node, so the kernel can be auditioned without a DAW.
- Custom vector rotary knobs with vertical drag, Shift for fine adjustment,
  double-click reset and live value readouts.

## Clean-room provenance

Vinegar303 is an independent implementation.

- No proprietary source was decompiled or translated.
- No skins, bitmap assets, presets, factory patterns or other content were
  copied; the default pattern bank in this repository is original.
- All DSP and UI code is original and implemented from scratch in Swift.
- Vinegar303 contains no registration, license-checking, telemetry or
  phone-home path.

## Requirements

- macOS 13 Ventura or newer
- Xcode 15 or newer (Xcode 16 recommended)
- A host that supports AUv3 instruments (Logic Pro, GarageBand, AUM, etc.)

## Build and run

1. Open `Vinegar303.xcodeproj`.
2. Select the **Vinegar303** scheme.
3. If Xcode asks for signing, either choose your development team or keep the
   default ad-hoc “Sign to Run Locally” configuration.
4. Build and run. The host app starts audio with the sequencer stopped; press the
   play button to start the internal transport.

### Installing the AUv3

The app embeds `Vinegar303Extension.appex`. Run the app once so PlugInKit
registers it, then restart the host if the plug-in list was already open.

```sh
# Look up the component
auval -v aumu Vg03 Vngr

# Check registration
pluginkit -m | grep dev.vinegar303
```

If the unit does not appear in a DAW, verify that Audio Units are enabled for
third-party plug-ins in that host.

## Project layout

```
Vinegar303.xcodeproj        Host app + AUv3 extension targets
Vinegar303/                 SwiftUI host wrapper and audio-engine bridge
Shared/
  DSP/                      Oscillator, ladder filter, envelope, sequencer engine
  AU/                       AUv3 kernel, parameter catalog, parameter bridge, AU view controller
  Presets/                  Preset schema, file library and live preset controller
  UI/                       Theme, vector knob, sequencer editor, main editor, preset UI
Content/
  Presets/                  Goodie presets bundled into the app
  MIDI/Profiles/            Goodie MIDI profiles bundled into the app
Vinegar303Extension/        AUv3 Info.plist + sandbox entitlements
Tests/                      SwiftPM DSP and state tests
```

## Parameter tree

All parameters are address-stable and exposed through `AUParameterTree`.

| Address | Parameter | Range | Default |
| --- | --- | --- | --- |
| 1 | Cutoff | 200 Hz – 2 kHz | 520 Hz |
| 2 | Resonance | 0 – 100 % | 28 % |
| 3 | Envmod | 0 – 100 % | 45 % |
| 4 | Decay | 40 ms – 1.6 s | 300 ms |
| 5 | Accent | 0 – 100 % | 50 % |
| 6 | Volume | −60 – 0 dB | −8 dB |
| 7 | Tuning | −50 – +50 cents | 0 |
| 8 | Waveform | Square / Saw | Saw |
| 9 | Distortion | 0 – 100 % | 0 % |
| 10 | Drive | 0 – 24 dB | 0 dB |
| 11 | Tempo | 40 – 240 BPM | 132 |
| 12 | Pattern | 1 – 16 | 1 |
| 13 | Pattern length | 1 – 16 | 16 |
| 14 | Sync | Free / Host | Host |
| 15 | Run | Stop / Run | Stop |
| 16 | MIDI mode | Pattern / Note | Pattern |
| 17 | Pitch Transpose | −12 – +12 st (integer steps) | 0 st |
| 18 | Scale Aware | Off / On | Off |
| 19 | Scale Key | C – B | C |
| 20 | Scale Type | Major – Locrian | Major |
| 21 | Half Speed | 1:1 / 1:2 | 1:1 |

`fullState` stores the 16-step patterns, including each pattern’s length, alongside
the standard parameter state.

## Editor

- **Sequencer** — pitch lane plus 16 step columns. Drag a note cell vertically
  to transpose it. `G`, `A` and `S` toggle gate, accent and slide. The playhead
  is driven by the audio unit.
- **Transport** — the `HALF` toggle beside start/stop switches the sequencer
  between 1:1 and 1:2 timing for both host-synced and free-running playback.
- **Filter** — a stepped ±12-semitone Pitch Transpose knob followed by cutoff,
  resonance, envmod and decay. It shares its row with Voice.
- **Voice** — square/saw switch and bipolar tuning.
- **Scale Aware** — Scale Aware toggle, key menu and mode menu. While active,
  notes are quantized at trigger time and Pitch Transpose is bypassed. It shares
  its row with Output.
- **Output** — accent, volume, distortion and drive, aligned to the left edge.
- All knobs write through `AUParameter.setValue(_:originator:)`, the
  automation-safe path, and follow host automation via a parameter observer.

## Presets

Presets are ordinary JSON files with the `.v303preset` extension. They live
outside the app and plug-in bundles, in:

```
~/Library/Application Support/Vinegar303/Presets/<Category>/<Name>.v303preset
```

Categories are folders in that library. Create a category in the preset manager
before importing another user’s presets so their set stays separated from your
own presets. Both the standalone app and the AUv3 extension use the same library.

Goodie presets placed under `Content/Presets/<Category>/` are bundled into the
app and copied once into the user library on first launch. They are ordinary
user presets and can be edited or deleted; existing files are never overwritten,
and a deleted bundled preset is not restored.

A single preset exports as a `.v303preset` file. A full category exports as one
`.v303category` JSON file containing every preset in that category, with each
preset’s complete 16-pattern bank and stored sound/scale data. A single-preset
import uses the category selected in the manager. A category import restores the
category name stored in the file, creating that category automatically if needed.

If a category or preset already exists, the manager asks how to resolve the
collision: **SKIP** leaves the existing item untouched, **KEEP BOTH** imports a
copy with a `version` suffix (`Source version`, then `Source version 2`, and so
on), and **OVERWRITE EXISTING** replaces the existing preset or the complete
category and all of its presets.

- **Factory Default** is built into the app, locked and read-only. Use **Save As**
in the manager to create an editable copy.
- **PRESET** in the SEQUENCER header is the fast browser: previous, next, the
current preset name, **SAVE** and **MANAGE**.
- **Patterns** scope stores the 16 patterns, their lengths and the selected
pattern. **Full** also stores sound and Scale Aware settings.
- The manager adds and renames categories, renames, duplicates and deletes
presets, imports/exports, and provides Save As and **Copy Patterns**. **EXPORT** on a preset writes one `.v303preset` file;
**EXPORT CATEGORY** writes every preset in the selected category as one
`.v303category` file. **DELETE CATEGORY** permanently removes the category
folder and every preset inside it after confirmation. Pattern copying can copy
one pattern or all 16 and keeps the destination preset’s sound settings.
- Tempo, Run/Stop, Sync and MIDI mode are performance settings and are not saved
in presets.

The current ad-hoc build uses a sandbox home-relative exception for the shared
preset folder. For distribution, replace it with an App Group, which requires a
provisioning profile and development signing.

## Standalone MIDI

CoreMIDI input is initialized only by the standalone app. The AUv3 extension
leaves MIDI routing to the DAW. The input port reconnects automatically when a
controller is connected or disconnected, and the `MIDI` panel filters incoming
messages by Omni or one of channels 1–16.

The default `Launchkey Mini` profile uses channel 1:

- CC 21 cutoff, 22 resonance, 23 envmod, 24 decay, 25 accent, 26 tuning,
  27 volume, 28 tempo.
- Notes 36–51 select patterns 1–16.
- Notes 52–67 toggle step gates in the current pattern.
- Notes 68–83 toggle step accents in the current pattern.
- Pitch bend controls tuning.

The Launchkey Mini MK3 pad grid has two standalone modes in DAW/Session mode,
independent of the selected profile:

- **EDIT MODE off** (default): the top row selects patterns 01–08 and the bottom
  row selects patterns 09–16 (MIDI notes 96–103 and 112–119). The selected
  pattern glows green.
- **EDIT MODE on**: the top row edits gates 01–08 and the bottom row edits gates
  09–16. Enabled gates glow green.
- The sounding gate glows red in either mode while its gate is open. In
  pattern-select mode all other pads are unlit.
- Toggle EDIT MODE with the `EDIT MODE` chip in the SEQUENCER header or by
  pressing **RECORD**. The mode is session-only and starts off.

The standalone app puts the Launchkey into DAW/Session mode and sends LED
feedback on its DAW port. The AUv3 extension does not create this output and
never changes the controller's mode.

When the standalone app puts the Launchkey into DAW mode, the eight rotary
controls send CC 21–28 on channel 16. Those DAW knob messages are accepted by
the active profile even when its channel filter is channel 1, so the mapped
cutoff, resonance, envmod, decay, accent, tuning, volume and tempo controls keep
working alongside the pad LEDs.

### Launchkey note knobs

When EDIT MODE is on, the eight knobs edit the current pattern's step notes.
When it is off, the same knobs control the mapped sound parameters:

- Turn EDIT MODE on with the `EDIT MODE` chip or **RECORD**. The MIDI panel shows
  the active mode.
- In EDIT MODE, knobs 1–8 edit the top-row gates 1–8.
- Hold **SHIFT** while turning a knob to edit the bottom-row gates 9–16.
- The knobs use pickup: a knob takes control only after it reaches the note
  already on the pad. After pickup, the full 0–127 pot travel maps to the
  sequencer's complete C1–C4 range. Switching rows or leaving EDIT MODE does not
  jump the note. The edit is applied to the current pattern.

### Launchkey pattern length

Hold **SHIFT** and use the track buttons to change the current pattern's length
by one step:

- **SHIFT + TRACK LEFT** shortens the pattern.
- **SHIFT + TRACK RIGHT** lengthens the pattern.

The length stays within the sequencer's 1–16 step range and applies to the
currently selected pattern.

Click `LEARN` in the MIDI panel to reveal the `L` badge on every mappable
control, then click a badge and move a CC control or press a pad. Learn captures
both continuous CC controls and note messages, so the Launchkey pads can be
assigned to patterns, gates, accents, notes or transport actions. A learned pad
assignment takes precedence over that pad's built-in behavior.

The learnable surface includes:

- All parameter knobs, switches, menus and the transport `RUN` control.
- Each of the 16 pattern-column badges, which map a pad or key to that pattern.
- Each gate, accent and slide toggle.
- Each step note selector, which accepts a CC knob or a note.
- The `EDIT MODE` and `SHIFT` controls.
- The pattern length `−` and `+` buttons.

Turning `LEARN` off hides every badge and cancels a pending learn. Learn
visibility is not saved. Profiles are ordinary JSON files under:

```
~/Library/Application Support/Vinegar303/MIDI/Profiles/<Name>.json
```

Goodie profiles placed under `Content/MIDI/Profiles/` are bundled into the app
and copied once into the user profile folder on first launch. They are ordinary
user profiles and can be edited or deleted; existing files are never overwritten,
and a deleted bundled profile is not restored.

The `MIDI` panel changes the channel filter, loads a profile, shows all bindings,
and removes individual bindings. `SAVE PROFILE...` reveals the profile-name field
only when a profile is being saved. The current custom profile can be deleted
after confirmation; the built-in Launchkey Mini profile restores with
`LAUNCHKEY`.

## Testing

With a full Xcode installation:

```sh
swift test
```

The SwiftPM target compiles the shared DSP/AU/UI/MIDI sources and runs engine
tests that check audio output, pre-allocation silence, pattern state
round-tripping, per-pattern lengths, preset scopes, categories, pattern copying,
parameter ranges, MIDI parsing, channel filtering, learn capture, and profile
storage.

The AUv3 extension itself is best validated in Xcode with `auval`:

```sh
auval -v aumu Vg03 Vngr
```

Or run the included host app, press **Space** to toggle play/stop, and hold the
**HOLD C3** pad to send MIDI to the unit.

## License

MIT. See [`LICENSE`](LICENSE).
