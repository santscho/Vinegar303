# Bundled MIDI Profiles

Put goodie MIDI mappings here before packaging the app. Each file must be a profile exported by Vinegar303, with the `.json` extension:

```
Content/MIDI/Profiles/<Name>.json
```

The app copies these files once into `~/Library/Application Support/Vinegar303/MIDI/Profiles/` on first launch. They are ordinary user profiles and can be edited or deleted. Existing files are never overwritten, and a deleted bundled profile is not restored.
