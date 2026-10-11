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
xcodebuild -project animango.xcodeproj -scheme animango -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:animangoTests/animangoTests/example
```

Unit tests use Swift Testing (`import Testing`, `@Test`, `#expect`), not XCTest. Test coverage is currently placeholder only.

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

## Rules

- Always build and run the relevant tests before declaring a task done.
- Never commit secrets, API keys, tokens, or credentials. This repo is public.
- Work on a feature branch and open a PR; never push directly to main.
- Keep changes small and focused on the task.
- If a task is ambiguous, stop and ask instead of guessing.
