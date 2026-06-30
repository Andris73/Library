# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Library is a native iOS app (Swift 6, iOS 26+) for browsing, downloading, and managing ebooks from self-hosted book servers. It uses SwiftUI, SwiftData, and provides a clean, native interface for building and organising a personal ebook library.

Library is derived from [ShelfPlayer](https://github.com/rasmuslos/ShelfPlayer) (an Audiobookshelf audiobook client) but stripped of all audio playback capabilities. It focuses purely on book acquisition — discovering, downloading, and managing ebooks and other text-based content.

## Build & Run

The project uses **XcodeGen** to generate the Xcode project from `project.yml`.

```bash
# Generate the Xcode project (required after changing project.yml or pulling changes)
xcodegen generate

# Build from command line
xcodebuild -scheme Library -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

### First-time setup

1. Copy `Configuration/Debug.xcconfig.template` to `Configuration/Debug.xcconfig`
2. Edit with your development team ID, bundle prefix, and feature flags
3. Run `xcodegen generate`

### Configuration flags

- `ENABLE_CENTRALIZED` — enables features requiring a paid developer account (app groups, iCloud, etc.). Without it, the app uses `FREE_DEVELOPER_ACCOUNT.entitlements`.
- Build number is auto-set from git commit count via a post-compile script.

## Versioning

`MARKETING_VERSION` in `project.yml` is the single source of truth for the user-facing version and follows SemVer as **major.feature.patch**:

- **major** — bump when a commit is tagged a release (reset feature and patch to 0).
- **feature** (minor) — bump when adding a new feature (reset patch to 0).
- **patch** — bump for a bug fix or other minor change.

Bump `MARKETING_VERSION` in the same commit as the change it represents. The build number (`CFBundleVersion`) is the git commit count, set automatically — it is unique per commit and is what the AltStore source (`apps.json`) dedupes on, so every nightly build is published as a new entry regardless of whether the marketing version changed.

## Architecture

### Module dependency graph

```
Library (app)
├── LibraryKit (framework) — data models, networking, persistence
│   ├── RFKit (SPM, internal utility lib)
│   ├── SwiftSoup (HTML parsing)
│   └── SocketIO (real-time updates)
├── LibraryMigration (framework) — version migration
│   └── LibraryKit
├── ABBKit (framework) — book source scraping
│   └── SwiftSoup
├── TransmissionKit (framework) — BitTorrent download client
└── LibraryWidgets (app extension) — WidgetKit widgets
    └── LibraryKit
```

### Key layers

- **LibraryKit** (`/LibraryKit/`): Core framework. Contains REST API client (actor-based), SwiftData persistence with subsystem pattern, and data models. No SwiftUI dependency.
- **App** (`/App/`): SwiftUI UI layer. Uses `@Observable` ViewModels. Key singletons: `Satellite` (navigation/UI coordinator), `ConnectionStore`.
- **WidgetExtension** (`/WidgetExtension/`): Home screen widgets sharing data via app group.

### Patterns

- **@Observable + @MainActor** for ViewModels (Swift 6 concurrency)
- **Subsystem pattern** in persistence: each domain is a separate subsystem class under `LibraryKit/Persistence/Subsystems/`
- **Actor-based API client** for thread-safe networking
- **Combine** for event publishing
- Shared state between app and widgets via **UserDefaults suite** (app group)

### Data model hierarchy

```
Item (base)
├── name, authors, description, genres, addedAt, released, size
├── Book (ebook)
└── Document (pdf, etc.)
```

## Design & Code Style

- **4-unit spacing system** for all UI layout
- UI should look and feel like a native Apple-made iOS app — minimal, clean, familiar
- **Prefer system styling; avoid custom.** Reach for stock SwiftUI controls, modifiers, and materials (`Form`, `Label`, `LabeledContent`, `.foregroundStyle`, system symbols, semantic colors) before building a bespoke equivalent.
- **Search the docs before reinventing.** When you need an API, look it up rather than hand-rolling from memory.
- Write minimal, lean, expressive Swift 6 code using modern language features: async/await, actors, Combine, @Observable, Sendable
- All "backend" code (networking, persistence, data models) belongs in LibraryKit, not in the app target
- The app target contains only SwiftUI views, ViewModels, and navigation

## Tests

Test targets currently contain placeholder stubs. Add Swift Testing-based integration tests in `LibraryKitTests` and XCTest-based UI tests in `LibraryUITests`.

## Distribution

Apps ship through the central AltStore source at `github.com/Andris73/altstore`. Publishing is handled by CI — see `.github/workflows/build.yml`.

Per-app metadata lives in `altstore/library.json`. The `APP_ID` for AltStore publishing is `library`.

## Key differences from ShelfPlayer

Library is a fork of ShelfPlayer (BookWave) with these intentional differences:

- **No audio playback** — LibraryKit has no playback framework; the app is for acquiring and managing ebooks, not listening to audiobooks
- **No CarPlay support** — removed as irrelevant for a reading app
- **No Siri playback intents** — `INPlayMediaIntent` and media categories removed
- **No microphone usage** — not applicable
- **Focus on download management** — downloading and organising ebooks is the primary function
