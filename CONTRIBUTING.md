# Contributing to DynIsl

Thanks for helping! Bug reports, feature ideas and pull requests are all welcome.

## Reporting a bug

Open an issue with the **Bug report** template, or use **Report a problem…** in the menu bar menu or in Settings, which pre-fills your macOS version, Mac model and DynIsl version.

## Suggesting a feature

Open an issue with the **Feature request** template. Please describe the problem you want solved, not only the solution.

## Building

Requirements: macOS 14+, Xcode or the Xcode Command Line Tools (Swift 5.9+).

```bash
git clone https://github.com/caganerdal/DynIsl.git
cd DynIsl
swift build          # debug build
swift test           # unit tests
./build-app.sh       # signed app bundle in build/DynIsl.app
```

## Pull requests

- Keep each pull request focused on one change.
- Run `swift test` before opening it; CI runs the build and the tests on every push.
- Match the existing code style: SwiftUI, Swift concurrency with `@MainActor` services, no code comments (names should explain the code).
- If you add user-facing text, write it in Turkish in code and run `./Tools/localize.sh`, then add the English translation to `Resources/Localizable.xcstrings`.
- Anything that sends data off the Mac needs a clear reason and an entry in the Privacy section of the README.

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
