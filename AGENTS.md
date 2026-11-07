# Project Instructions

## Git and GitHub workflow

- `main` is protected: never commit or push feature work, fixes or refactors directly to it.
- Start every feature, bug fix or refactor on a branch named `feature/<feature-name>`
  (for example `feature/scale-aware-generator`, `feature/half-speed-toggle`).
- Push that branch with `git push -u origin feature/<feature-name>` and open a pull request
  into `main` instead of merging locally.
- Commit messages are descriptive and typed, for example
  `feat: implement 1/2 speed step-accumulator DSP logic` or
  `fix: keep per-pattern length inside the 1-16 step range`.
  Never use `update files`, `auto-push` or other generic summaries.
- Tag validated milestones with semver, for example
  `git tag -a v1.0.0 -m "Release v1.0.0 - Stable Standalone & AUv2 Build"`,
  then `git push origin v1.0.0`. A milestone qualifies once `auval -v aumu Vg03 Vngr`
  passes or a standalone release build succeeds.
- Undo bad changes with `git revert <commit-hash>`, never `git reset --hard`,
  so history stays intact and the revert is reviewable.

## UI conventions

- Keep labels consistent between the standalone app and the AUv3 editor.
- Section and panel titles use capital letters only: `SEQUENCER`, `FILTER`, `VOICE`, `OUTPUT`, `SCALE AWARE`.
- The standalone window width is always 1300 px; vertical size is flexible and content-driven. When adding a section, let the content determine the height rather than introducing a fixed height that crops the header, footer, or panels.
- The AUv3 preferred canvas width is 1300 px; keep its vertical size fitted to the complete editor content and verify it in a host.
- Verify the full layout at the resulting standalone and AUv3 sizes, including the header and footer; a new panel must not push either out of view.
- Parameter readouts use exactly one space between the value and its unit:
  `520 Hz`, `20 %`, `0 st`, `300 ms`, `132 BPM`.
- Never concatenate a unit directly to a value (`520Hz`, `20%`, `0st`, `300ms` are wrong).

## Agent commands

### `UAT`

When the user sends exactly `UAT`:

1. Verify the current working tree compiles successfully without errors.
2. Push the current feature branch to GitHub without merging into `main`:
   `git push -u origin <current-branch>`.
3. Build the universal Release app and deploy it directly to the user's Applications directory at
   `$HOME/Applications/Vinegar303.app`, replacing the installed copy. Do not create or use an
   installable DMG for UAT.
4. Report the deployed app path, pushed branch, architecture/signature checks, and any checks that
   could not be completed.
