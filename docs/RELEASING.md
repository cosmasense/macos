# Backend Release Flow (PyPI)

The Python backend ships to PyPI from the separate `cosma` repo; the
macOS app auto-upgrades to the latest release on every launch. You
don't need to rebuild or re-ship the Swift app for a backend-only change.

## How clients pick up new backends

`CosmaManager.upgradeCosmaIfNeeded()` runs before the server starts in
the "installed cosma" launch strategy:

- Reads `cosma --version` (installed) and fetches the latest PyPI
  version with a 3 s timeout.
- If they differ, runs `uv tool upgrade cosma --no-cache` (bounded by
  120 s). Non-fatal: on timeout or error, launch continues with the
  existing version.

So to roll out a backend fix, just publish a new PyPI release — users
get it on their next app launch with no intervention.

## Publishing a new backend release

Run in the `cosma` repo:

1. Bump `version` in the root `pyproject.toml` and in every changed
   `packages/*/pyproject.toml`. Keep versions in lockstep.
2. `git commit -m "v0.8.0"`.
3. `git tag v0.8.0`.
4. `git push && git push --tags`.
5. `.github/workflows/release.yml` (cosma repo) builds wheels and
   publishes to PyPI via trusted publishing.

See `cosma/docs/RELEASING.md` for backend-side details.

## Shipping the Swift app itself

Only required when `.swift` files or entitlements change. Build via
Xcode (or `xcodebuild`), sign, and distribute the `.app` as usual.
Backend changes alone don't require this.
