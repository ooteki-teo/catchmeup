# CatchMeUp

> A native macOS personal task assistant: drop in screenshots, text, files, folders, or URLs and it organizes them into items and to-dos, and remembers "where I left off and what's next".

[简体中文](README.md) · **English** · [Español](README.es.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

CatchMeUp is a **single-file native macOS app** (SwiftUI + Swift 6). No Electron, no Python — everything runs locally except calls to the DeepSeek API.

---

## Features

### Unified capture (WeChat-style, few clicks)
- One input for everything: **text / URL / file path / drag files / drag folders / paste a screenshot (⌘V) / select a screen region** — the type is detected automatically.
- Smart routing: URLs are fetched, file paths are read, images go to OCR or the vision model.
- Global hotkey (default `⌘⇧M`, **configurable**): select a region from anywhere → the app comes to front and analyzes it.

### AI organization (DeepSeek)
- Multiple AI providers: **DeepSeek (default)**, OpenAI, OpenRouter, Moonshot, Ollama, or any OpenAI-compatible endpoint. Default model `deepseek-flash` (image input).
- Produces a title, summary, tags, category, and two structured results:
  - **Tasks**: to-dos with explicit deadlines;
  - **Handoff**: a project recap (goals / approach / detailed progress / next steps / risks).
- Screenshots use the vision model first, and fall back to the built-in **Vision OCR** (Chinese + English).
- Folder input becomes "README (if present) + directory tree + one-line note per file" — full file text is never dumped.

### Task system (date-grouped, one click)
- The default "Tasks" view groups by **Overdue / Today / Tomorrow / This week / Later / No date / Completed**.
- Add with one line + Return; tick the circle to complete, tap the date to reschedule, tap the dot to change priority.
- Local notifications at the right time (they still fire when the app is closed), with daily / weekly / monthly repeats.
- Optionally write tasks (with a due date) to the **system Calendar**.

### Handoff (continuous tracking)
- Every handoff item has an incremental "update": re-scan the source and feed the previous handoff back in, keeping valid progress and adding only changes.
- Start / end sessions and generate a handoff summary, copyable as Markdown.

### More
- Menu bar extra: quick note, screenshot, clipboard, upcoming items.
- **Token usage stats** (Settings → DeepSeek): requests / input / output / total, broken down by model.
- The API key is stored in a local file, not the system Keychain — **no permission prompts**.
- All permissions (notifications / calendar / screen recording) are **requested only when you click in Settings** — nothing pops up at launch.
- **Languages: 简体中文, English, Español, 日本語, 한국어** (Settings → Language; follow the system or pick one).

---

## Requirements

- macOS 14.0 or later (verified on Apple Silicon)
- Xcode or Command Line Tools (Swift 6 toolchain)
- A [DeepSeek](https://platform.deepseek.com/) API key
- Optional: an Apple Development certificate (for stable permission memory, see below)

---

## Quick start

```bash
# Build (release) and package dist/CatchMeUp.app
bash scripts/build.sh

# Run
open "dist/CatchMeUp.app"

# Tests
bash scripts/test.sh   # or: swift test
```

First run:

1. Open **Settings → DeepSeek**, paste your API key, click **Save**.
2. Open **Settings → Permissions** and grant what you need: Notifications, Calendar, Screen Recording.
3. Press `⌘⇧M` (changeable in **Settings → General**) to select a region and auto-analyze.

---

## Usage

| Scenario | Action |
| --- | --- |
| Note some text | Type in the Workspace box, press Return |
| Save a web page | Paste the URL, press Return |
| Organize a project folder | Drag the folder in (handled as a handoff) |
| Organize a screenshot | `⌘⇧M`, the camera button, or paste with ⌘V |
| See an item | Click a card → a separate window (movable/resizable, has **Refresh**) |
| Tasks | Type a line in the Tasks tab; reschedule/priority/complete inline |
| Handoff | Generate a summary in the Handoff tab, or update a card in place |

---

## Project structure

```text
catchmeup/
├── Package.swift                 # SwiftPM manifest (macOS 14+, no third-party deps)
├── Sources/
│   ├── CatchMeUpCore/            # models, storage, AI, OCR, calendar, reminders, pipeline
│   │   ├── Models.swift          # Item / TaskItem / Session / Handoff
│   │   ├── Database.swift        # SQLite persistence
│   │   ├── DeepSeekClient.swift  # DeepSeek API + prompts + JSON parsing
│   │   ├── L10n.swift            # in-app localization (zh/en/es/ja/ko)
│   │   ├── OCR.swift             # offline Vision OCR
│   │   ├── Ingest.swift          # text/url/file/folder/screenshot reading
│   │   ├── ReminderScheduler.swift
│   │   ├── CalendarService.swift
│   │   ├── Pipeline.swift        # capture → organize → store → remind/calendar
│   │   ├── Secrets.swift         # local file secrets + preferences
│   │   └── Usage.swift           # token usage
│   └── CatchMeUpApp/             # SwiftUI app layer
├── Tests/CatchMeUpCoreTests/
└── scripts/                      # build.sh / test.sh / Info.plist / make-icon.swift
```

---

## Data & privacy

- Data folder: `~/Library/Application Support/CatchMeUp/`
  - `catchmeup.db` (SQLite), `storage/` (attachments), `secrets.json` (API key), `usage.json` (token stats).
- The API key lives in `secrets.json` (mode 0600); you can also override it with the `DEEPSEEK_API_KEY` environment variable.
- DeepSeek is called only when you organize content; everything else stays on your Mac.

---

## Permissions & code signing

macOS remembers permissions like Screen Recording by the app's **code signature**. With an **ad-hoc signature**, the designated requirement is a `cdhash` that changes on every build, so the system treats each rebuild as a new app and re-asks.

`scripts/build.sh` prefers your **Apple Development** certificate so permissions persist across rebuilds:

```bash
CODESIGN_IDENTITY="Apple Development: you@example.com (XXXXXXXXXX)" bash scripts/build.sh
```

If no certificate is found it falls back to ad-hoc (you may need to re-grant after each rebuild).

For a **clean, shareable build** with no personal signing identity (e.g. for a GitHub release):

```bash
bash scripts/package-release.sh   # → dist/CatchMeUp-<version>.zip (ad-hoc, no email/Team ID)
```

---

## FAQ

**Q: Screen Recording is requested again and again.**
A: Rebuild with a certificate (above) and grant once in Settings → Permissions. Ad-hoc builds look like new apps after each rebuild.

**Q: Can I use it without granting permissions?**
A: Yes. You just won't get notifications, calendar events, or screenshots; organizing and tasks still work.

**Q: Can I avoid DeepSeek?**
A: Organizing and handoff currently rely on the DeepSeek API; without a key you can still create and manage tasks manually.

---

## License

[MIT](LICENSE)
