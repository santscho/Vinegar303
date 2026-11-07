# Bundled Presets

Put goodie presets here before packaging the app.

Use one folder per category and the normal preset extension:

```
Content/Presets/<Category>/<Name>.v303preset
```

The app copies these files once into `~/Library/Application Support/Vinegar303/Presets/` on first launch. They are ordinary user presets: they can be edited, renamed or deleted. Existing files are never overwritten, and a deleted bundled preset is not restored.
