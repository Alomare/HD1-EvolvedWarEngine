# Rules for this repository

**Every release has a changelog.** Before tagging, add a section for the version to `CHANGELOG.md`, headed `## <version>`, listing the new, changed or removed features. Each change is one line, starting `New:`, `Changed:` or `Removed:`, and describes the change briefly and directly. The Release workflow publishes that section as the release notes, and stops if the section is missing.

**The map data is shared.** `src/galaxy.lua` is generated from `ObsidianCommander/data/galaxy-hd2.json` by `tools/build_galaxy_lua.py`; the server, the war screens and this mod must draw the same file. Change the data in Commander (`tools/build_galaxy.py` there) and rebuild here.

**Tests and pictures.** `luajit tests/run.lua` runs everything that doesn't need the game. `luajit tools/preview.lua` then `python -P tools/render_preview.py` draws each level offline from `tests/fixtures/state.json` into `internal/preview/`. `tools/fixture_state.py <commander-server.exe>` makes a fresh fixture from a real server.

**Writing.** Player-facing text (locales, README, changelog) is plain and objective: no persona, no first person, no possessives, no "its".
