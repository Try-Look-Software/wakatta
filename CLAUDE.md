# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository layout

Three independent pieces share this repo:

- `animango/` — iOS app (SwiftUI + SwiftData) for learning Japanese from anime, manga, movies, J-drama and games. Xcode project `animango.xcodeproj`, single scheme `animango`, targets `animango`, `animangoTests`, `animangoUITests`.
- `chrome-extension/` — **KotoLens**, a standalone Chrome extension (Japanese/Korean reader using the Anthropic API). Shares no code with the iOS app.
- `docs/` — static GitHub Pages site (app support page, KotoLens landing and privacy pages).

The Python/FastAPI backend described in `DESIGN.md` is **not** in this repo; the iOS app only talks to it over HTTP.

`DESIGN.md` is the system design doc (data models, 3-tier content fallback, data flows, backend pipeline). It predates some features (Gemini provider, translation, deep word analysis), so verify it against the code.

## iOS app

### Commands

```bash
# Build
xcodebuild -project animango.xcodeproj -scheme animango -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# All tests
xcodebuild -project animango.xcodeproj -scheme animango -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

# A single test (Target/Suite/test)
xcodebuild -project animango.xcodeproj -scheme animango -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:animangoTests/SRSEngineTests/correctAnswersFollowSM2Schedule
```

Unit tests use Swift Testing (`import Testing`, `@Test`, `#expect`), not XCTest. Unit tests cover `SRSEngine` and `ComprehensionCalculator`; SwiftData tests use an in-memory `ModelContainer`. Suspected bugs are recorded with `withKnownIssue` rather than fixed in a test PR.

### Project settings that matter

- Deployment target iOS 26.2. Apple Intelligence uses the on-device `FoundationModels` framework.
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`: types are MainActor-isolated by default. Mark work that must run off the main actor explicitly (`nonisolated`, `@concurrent`, or a separate actor).
- The project uses file-system-synchronized groups, so new Swift files under `animango/` join the target without editing `project.pbxproj`.
- `Info.plist` has an ATS exception for the backend's bare IP (`44.210.75.181`, plain HTTP). If the backend address in `Services/Config.swift` changes, update both.
- `Config.swift` reads `TMDB_API_TOKEN`, `IGDB_CLIENT_ID` and `IGDB_CLIENT_SECRET` from the Info.plist. None are set in the repo, so TMDB and IGDB search return nothing unless they're provided locally.

### Architecture

MVVM: `Views/` (grouped by feature: Discover, Library, Study, Lesson, Chat, Translation, Detail, Profile) → `ViewModels/` (`@Observable`) → `Services/` → SwiftData `Models/`.

- **SwiftData models** include junction models (`MediaVocabulary`, `EpisodeKanji`, and others) that link media and episodes to shared `VocabularyItem`, `KanjiItem` and `GrammarPoint` records, so a word is stored once and referenced from many episodes. SRS state lives on the study items.
- **Content pipeline**: `ContentGenerationService` fills an episode's vocab, kanji and grammar with a 3-tier fallback: backend (`AnimangoAPIService`) → Jisho plus LLM generation → Jisho only. Each tier persists to SwiftData so later loads are local.
- **LLM layer**: `LLMServiceManager` routes to the provider chosen in `LLMConfiguration` (`apple`, `anthropic`, `openAI`, `gemini`). Each provider (`AppleIntelligenceProvider`, `AnthropicProvider`, `OpenAIProvider`, `GeminiProvider`) implements the `LLMServiceProvider` protocol in `LLMService.swift`. To add a provider, add an `LLMProvider` case (display name, icon, default model, model list) and a provider type, then wire it into the manager.
- **Learning**: `SRSEngine` (SM-2), `ComprehensionCalculator` (per-media comprehension from vocab knowledge state × frequency), `RecommendationService` (weighted discovery scoring).
- **External APIs** go through the generic `APIClient`. `JikanService` (0.35 s spacing) and `JishoService` (1 s spacing) throttle themselves; keep that when adding calls. `MediaSearchService` fans out across the Jikan, TMDB and IGDB services.
- **Speech**: `SpeechService` (TTS), `PronunciationService` and `LiveSpeechRecognizer` (ja-JP recognition plus scoring), `TranslationService` and `LiveTranslationViewModel` for live translation.
- Bundled offline data: `Data/jlpt_vocabulary.json` and `Data/jlpt_kanji.json`, loaded by `VocabularyDataService` and `KanjiDataService`.

## Chrome extension (KotoLens)

Run from `chrome-extension/`:

```bash
npm install
npm run build      # bundles src/ with esbuild into dist/ (load unpacked from dist/)
npm run watch      # rebuild on save
npm test           # node --test test/*.test.mjs
node --test test/logic.test.mjs                          # one file
node --test --test-name-pattern="detectScript" test/     # one test by name
npm run package    # build + zip for the Web Store
npm run icons      # regenerate icons (Python + Pillow)
```

Key constraints from the design:

- **No `<all_urls>` permission.** The content script is injected only when the user clicks a context-menu item (`activeTab` + `scripting`). Don't add broad host permissions.
- Claude calls live in `src/background.js`, and the prompt and JSON schema live in `src/lib/claude.js`. Responses use structured outputs. `test/claude.test.mjs` checks that every schema object is closed (`additionalProperties: false`) and lists every property as required, so keep that rule when editing `SCHEMA`.
- Model output is rendered with DOM text nodes, never `innerHTML`. The in-page popup uses Shadow DOM (`src/content.js`, `src/lib/render.js`).
- Users bring their own API key. `src/lib/settings.js` keeps it in `chrome.storage.local` (never synced) while other settings use `chrome.storage.sync`; keep that split.
- Pages where scripts can't run (chrome://, the Web Store, the PDF viewer) fall back to a standalone window.
- Store listing and publishing steps are in `store/` (`PUBLISHING.md`).

## CI

GitHub Actions runs on pull requests to `main` and pushes to `main`:

- `.github/workflows/ios.yml` runs on every PR and push so that the required `Build and unit test` check always reports. That check is a small gate job on Ubuntu. A `Detect iOS changes` job diffs the commit, and the macOS job (`iOS build and test (macOS)`) only runs when `animango/`, the Xcode project, the test folders, or `ios.yml` changed; otherwise the gate passes in seconds. Don't add a `paths:` filter to this workflow, or PRs that skip it can't merge. The macOS job uses the `macos-26` runner with Xcode 26.3 pinned through `DEVELOPER_DIR` (the iOS 26.2 SDK) and runs `-only-testing:animangoTests` on `iPhone 17 Pro, OS=26.2`. When bumping the deployment target, confirm in the runner image README (actions/runner-images) that the Xcode version and simulator exist on the image.
- `.github/workflows/chrome-extension.yml` runs on every PR and push with no path filter, because its `npm test` job is a required check and takes only about 10 seconds. It runs `npm ci` and `npm test` on `ubuntu-latest` with Node 24.

The `protect-main` ruleset requires the `Build and unit test` and `npm test` checks. A required check must report on every PR, so if you rename a job or add a required check, update the ruleset to match and make sure the job never gets skipped by path filters.

Neither workflow uses secrets.

Bug fixes flow from an issue to the App Store through three more workflows:

- `.github/workflows/claude-fix-issue.yml` runs Claude on `macos-26` for every new issue from someone with write access (issues that mention `@claude` go to `claude.yml` instead). It sets `prompt`, which runs the action in agent mode: Claude fixes the issue on a `claude/issue-N-*` branch, runs the build and tests, opens a PR with `Closes #N`, and links it on the issue. If the issue is unclear, it asks on the issue instead.
- `.github/workflows/testflight.yml` archives the `animango` scheme and uploads it to TestFlight on every push to `main` that changes iOS files, and can be run by hand. The build number is a UTC timestamp (`YYYYMMDDHHMM`) passed as `CURRENT_PROJECT_VERSION` at archive time; the committed value stays as it is.
- `.github/workflows/app-store-submit.yml` is run by hand. It uses fastlane `deliver` to submit a TestFlight build of the current `MARKETING_VERSION` for review, with automatic release on approval. Once that version is approved, TestFlight rejects new uploads for it, so start the next release before merging more fixes. This workflow doesn't create a release tag; tag only when the user says the version shipped.

The TestFlight and submit workflows use the `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_KEY_P8` secrets from an App Store Connect API key with the Admin role, and fail with a clear error when they're missing.

`.github/workflows/claude.yml` runs Claude Code when an issue or comment mentions `@claude`. It uses the `CLAUDE_CODE_OAUTH_TOKEN` secret and the Claude GitHub App token, which is scoped to this repository. When it finishes work on a new branch, it opens the PR itself with `gh pr create --repo <this repo>` instead of posting a link. Its only allowed Bash commands are `gh pr create`, `gh pr list` and `gh pr view` (set in `claude_args`). Don't set the action's `prompt` input, because that switches it to automation mode and stops it responding to `@claude`.

## Releases

Versions use three parts, `X.Y.Z`. The current `MARKETING_VERSION = 1.2` counts as `1.2.0`; write all three parts from the next release on.

A version is released once it has a git tag `vX.Y.Z` on the commit that shipped. Tag a version only when the user says it shipped. Versions 1.0 and 1.1 shipped before tagging started, so they have no tags but still count as released.

To start a new release:

1. Choose the next version from the current `MARKETING_VERSION`:
   - **Patch** (`X.Y.Z+1`) for bug fixes.
   - **Minor** (`X.Y+1.0`) for features.
   - **Major** (`X+1.0.0`) only when the user explicitly asks for it.

   If it's unclear whether the release is fixes or features, ask.
2. Never reuse a version that has already been released. Check `git fetch --tags && git tag -l 'v*'`, and stop and ask if the version is already tagged or is 1.0 or 1.1.
3. On a new branch, set `MARKETING_VERSION` to the new version in every configuration of the `animango` target (Debug and Release in `animango.xcodeproj/project.pbxproj`). Change nothing else: not `CURRENT_PROJECT_VERSION`, not the test targets.
4. Open a PR titled `Start release X.Y.Z`.

## Rules

- Always build and run the relevant tests before declaring a task done.
- Never commit secrets, API keys, tokens, or credentials. This repo is public.
- Work on a feature branch and open a PR; never push directly to main.
- Keep changes small and focused on the task.
- If a task is ambiguous, stop and ask instead of guessing.
