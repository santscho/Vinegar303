# Project Instructions

## UI conventions

- Keep labels consistent between the standalone app and the AUv3 editor.
- Section and panel titles use capital letters only: `SEQUENCER`, `FILTER`, `VOICE`, `OUTPUT`, `SCALE AWARE`.
- The standalone window width is always 1300 px; vertical size is flexible and content-driven. When adding a section, let the content determine the height rather than introducing a fixed height that crops the header, footer, or panels.
- The AUv3 preferred canvas width is 1300 px; keep its vertical size fitted to the complete editor content and verify it in a host.
- Verify the full layout at the resulting standalone and AUv3 sizes, including the header and footer; a new panel must not push either out of view.
- Parameter readouts use exactly one space between the value and its unit:
  `520 Hz`, `20 %`, `0 st`, `300 ms`, `132 BPM`.
- Never concatenate a unit directly to a value (`520Hz`, `20%`, `0st`, `300ms` are wrong).
