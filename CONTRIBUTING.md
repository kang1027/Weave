# Contributing to Weave

Thanks for your interest! Issues and pull requests are welcome.

## Development

Weave is a Swift Package (SwiftUI, menu-bar app). Requires **macOS 14+** and a Swift toolchain.

```sh
git clone https://github.com/kang1027/Weave.git
cd Weave
scripts/fetch-sparkle.sh   # one-time — vendors Sparkle
swift run Weave            # run
swift test                 # unit tests
scripts/bundle.sh          # build dist/Weave.app
```

## Project layout

- `Sources/WeaveCore/` — models, calculators, providers, stores (pure, unit-tested).
- `Sources/Weave/` — SwiftUI app: `App/` (state), `Views/`, `Update/`, `Services/`.
- `docs/` — feature spec, flows, appcast, landing page.
- `scripts/` — bundle / release / publish automation.

## Pull requests

- Keep changes focused; one concern per PR.
- Match the existing code style; prefer small files.
- Write commit messages in **English** using [Conventional Commits](https://www.conventionalcommits.org) (`feat:`, `fix:`, `docs:`, `chore:`, `refactor:`, `perf:`).
- Run `swift build` and `swift test` before opening the PR.
- No telemetry, analytics, or account systems — Weave is local-only by design (see [PRIVACY.md](PRIVACY.md)).

## Reporting bugs / requesting features

Use the issue templates. Include your macOS version, Weave version (shown in the footer), and steps to reproduce.
