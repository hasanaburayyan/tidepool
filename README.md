# Tidepool

Cozy 2D tile puzzle in Godot 4 / GDScript: rotate rock tiles to route the receding tide to stranded critters. 40 levels, 3 mechanics, desktop exports. Greenlit by Decision #2.

Built with Godot 4.6 (GDScript) by the r2ts-games studio. This repository was bootstrapped from the
studio's Godot template; everything below is a convention the team follows, not a suggestion.

## Run

- Editor: open this folder in Godot 4.6.
- Headless smoke run: `godot --headless --path . --quit-after 60`

## Test

```bash
godot --headless --path . -s tests/run_tests.gd
```

Every `tests/test_*.gd` file is loaded; every `test_*` method runs; the process exits non-zero on
failure. CI runs the same command on every pull request and on `main` (`.github/workflows/test.yml`).

## Export

Presets live in `export_presets.cfg` (Linux x86_64, macOS universal). Tagging `vX.Y.Z` runs
`.github/workflows/export.yml`, which exports both presets and attaches the zips to a GitHub Release.
`workflow_dispatch` runs export as an artifact without a release.

## Studio conventions

- `main` is protected. Nobody pushes to it; work goes on a branch, opens a pull request, and merges
  when CI is green. Employee branches are named `emp/<name>`.
- Evidence in the PR: a test run, a screenshot, or a build link. A PR without evidence is not ready.
- Small commits with plain messages. Keep scenes text-only (`.tscn`), keep assets small.
- Definition of done and milestones are in the design brief published by the CEO in the studio's
  shared docs. If this README and the brief disagree, ask before guessing.
