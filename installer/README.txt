Vinegar303 1.0 - macOS installer

Requirements: macOS 13 or newer, Apple Silicon or Intel.

Before installing, quit Vinegar303 and any DAW that has it loaded.

AUTOMATED INSTALL

1. Open the Vinegar303 disk image.
2. Double-click Install.command.
3. If macOS blocks the script, open Terminal and run:

   bash "/Volumes/Vinegar303 1.0/Install.command"

   Adjust the volume name if you renamed the mounted disk image.
4. The script installs to ~/Applications, removes the download quarantine,
   verifies the ad-hoc signature, and launches the app once to register AUv3.

MANUAL INSTALL

1. Drag Vinegar303.app to Applications or to ~/Applications.
2. Open it.
3. If macOS blocks it, open System Settings > Privacy & Security, scroll to
   Security, click Open Anyway, then confirm.
   On macOS 13 and 14, you can also Control-click the app and choose Open.
4. Restart your DAW and rescan AU plug-ins.

VALIDATE THE AUDIO UNIT

   auval -v aumu Vg03 Vngr

NOTES

- This build is ad-hoc signed, not notarized by Apple. The first launch needs
  your approval; macOS remembers that approval afterward.
- Factory Default is built into the app. Bundled goodie presets and MIDI
  profiles are copied once, on first launch, to
  ~/Library/Application Support/Vinegar303/Presets and
  ~/Library/Application Support/Vinegar303/MIDI/Profiles. They are ordinary
  user files: edit or delete them freely. Existing files are not overwritten,
  and deleted goodies are not restored.
- To uninstall, quit the app and delete ~/Applications/Vinegar303.app.
- No administrator password is required for the automated install.
