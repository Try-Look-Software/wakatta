# Publishing KotoLens to the Chrome Web Store

## 1. One-time setup
1. Sign in at https://chrome.google.com/webstore/devconsole with the Google account that will own the listing.
2. Pay the one-time **$5 developer registration fee** and verify your email.
3. Privacy policy URL: https://try-look-software.github.io/wakatta/kotolens/privacy.html (served from `docs/kotolens/` in the wakatta repo).

## 2. Build the package
```bash
npm install
npm test
npm run package        # → kotolens-<version>.zip
```
Before each new upload, bump `"version"` in `src/manifest.json` (and `package.json`).

## 3. Test the exact zip
Unzip it somewhere, load it with **Load unpacked** in `chrome://extensions`, and test these:
- [ ] Right-click Japanese text → Explain in English: furigana, audio, vocab, and grammar all show
- [ ] Right-click Korean text → Explain in English
- [ ] Right-click English text → Translate to Japanese / Korean
- [ ] ＋ adds a card, the toolbar badge shows the due count, and the review page works
- [ ] Text inside a textarea, and a selection inside a long paragraph
- [ ] Settings → Test succeeds with a real API key, and a wrong key shows a friendly error
- [ ] On chrome://extensions, "Explain" opens the standalone panel window

## 4. Create the item
In the developer console: **New item** → upload the zip, then fill in these tabs.

### Store listing
Paste the copy from `store/listing.md`. Upload the 128×128 icon (`src/icons/icon128.png`), at least one 1280×800 screenshot, and the 440×280 small promo tile.

### Privacy practices
**Single purpose:**
> Translate and explain text the user highlights, between English and Japanese/Korean, with readings, audio, grammar notes, and personal flashcards.

**Permission justifications:**
| Permission | Justification |
|---|---|
| `contextMenus` | Adds the "Translate to Japanese / Korean / Explain in English" items to the right-click menu for selected text. |
| `activeTab` | Gives temporary access to the current tab only when the user picks a KotoLens menu item or shortcut, so the extension can read the selection and show the result popup. |
| `scripting` | Injects the result popup into the active tab after the user clicks a KotoLens menu item (used with activeTab; no persistent content scripts). |
| `storage` | Saves the user's settings, their Anthropic API key (locally), and their flashcards. |
| `tts` | Reads Japanese and Korean words and sentences aloud with Chrome's text-to-speech. |
| `alarms` | Periodically updates the toolbar badge with the number of flashcards due for review. |
| Host `https://api.anthropic.com/*` | Sends the highlighted text and its surrounding sentence to the Anthropic API, using the user's own API key, to generate translations and explanations. |

**Remote code:** No. All JavaScript ships in the package; the extension only makes API calls to `api.anthropic.com`.

**Data usage disclosures.** Tick:
- *Website content* (the highlighted text and its surrounding sentence are sent to Anthropic to fulfil the user's request)
- *Authentication information* (the user's API key is stored locally and sent only to Anthropic)

Then certify: not sold to third parties; not used for purposes unrelated to the single purpose; not used for creditworthiness or lending.

**Privacy policy URL:** https://try-look-software.github.io/wakatta/kotolens/privacy.html

### Distribution
Choose Public (or Unlisted for a soft launch) and your regions.

## 5. Submit for review
Reviews usually take a few days. Because there's no broad host permission and no remote code, this extension falls into the lower-risk review path. If it's rejected, the email names the policy. Fix it, bump the version, and upload again.

## Later: a keyless version for mainstream users
Asking users for an Anthropic API key limits the audience to technical learners. To reach everyone, add a small backend proxy (e.g. a Cloudflare Worker) that holds your key, authenticates users, and rate-limits them, and point `analyze()` at it. You can pay for it with a subscription through a payment provider (the Chrome Web Store no longer handles payments). If you do this, update the privacy policy and the data disclosures.
