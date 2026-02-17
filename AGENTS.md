# Repository Guidelines

## Project Structure & Module Organization
- `fileSearchForntendApp.swift` bootstraps the SwiftUI app and wires shared models into the environment.
- `ContentView.swift` configures the split-view navigation; child views live in `Views/` (`HomeView`, `JobsView`, `SettingsView`, `SidebarView`) with reusable components under `Views/Components/`.
- Data types that sync UI state (search tokens, watched folders, recents) live in `Models/`.
- Visual assets are stored in `Assets.xcassets`, and documentation such as product rationale is tracked in `Design Doc.md`.

## Build, Test, and Development Commands
- `xed .` opens the project in the latest Xcode for graphical development, previews, and debugging.
- `xcodebuild -scheme fileSearchForntend -configuration Debug build` produces a local build from the CLI; use `-destination 'platform=macOS'` when testing Catalyst targets.
- `xcodebuild test -scheme fileSearchForntend -destination 'platform=macOS'` runs the XCTest bundle (create tests before running to avoid “no tests found” warnings).
- For SwiftUI previews, use Xcode’s canvas or run `open -a Simulator` alongside the debug build to validate layout with live data.

## Coding Style & Naming Conventions
- Follow Swift 5.9 style: four-space indentation, `UpperCamelCase` for types, `lowerCamelCase` for properties and functions, and descriptive enum cases.
- Keep view models lightweight; prefer struct models in `Models/` and isolate side effects in dedicated `ObservableObject` types.
- Use `// MARK:` pragmas to separate lifecycle, body content, and helpers inside each view for quick navigation.
- Run `swiftlint` if installed locally; match Xcode’s default formatting (control-click → “Format File”) before committing.

## Testing Guidelines
- Add unit and snapshot tests under a `fileSearchForntendTests` target; mirror the source hierarchy (e.g., `Views/HomeViewTests.swift`).
- Name tests using `test_<Scenario>_<ExpectedBehavior>` and keep fixtures inside `Tests/Fixtures/` once created.
- Target ≥80% coverage on models that transform data (search tokens, folder filtering). For UI, focus on accessibility traits and state toggles.

## Commit & Pull Request Guidelines
- The branch currently lacks history; adopt Conventional Commit prefixes (`feat:`, `fix:`, `chore:`) to keep future logs scannable.
- Reference the design doc or tracked issues in the commit body when a change touches requirements.
- Pull requests should include: summary of user-facing impact, screenshots or screen recordings for UI changes, testing notes (`xcodebuild test` output), and a checklist of remaining TODOs or follow-ups.
