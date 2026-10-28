# Continue development on another PC

## Clone the development branch

```powershell
git clone --branch Development https://github.com/qazi-muhammad-ahad/Dungeon-Architect.git
cd Dungeon-Architect
git status --short --branch
```

Open this cloned folder as the project in Codex. `Development` contains implemented phases 00-15;
`main` remains the production branch. Commit and push ongoing work to
`Development`. Do not merge into `main` until a production release is intended.
GitHub authentication is required to push, but not to clone this public repository.

## Windows setup

Install Git, Python 3, Chrome, and Flutter 3.47.5 stable. Put `git`, `python`, and
`flutter` on PATH. Node.js is needed for the deployment verifier and browser tests.
From the repository root, run these commands in PowerShell, stopping if any fails:

```powershell
.\tools\bootstrap-native.ps1
.\tools\bootstrap-web.ps1
.\tools\build-native.ps1 -Configuration Release
.\tools\build-web-engine.ps1
cd apps/flutter_ui
flutter pub get
flutter analyze
flutter test
flutter run -d chrome --no-web-resources-cdn
```

Both bootstrap scripts are needed: the Wasm build uses CMake and Make installed by
the native bootstrap. Tools download into ignored `.tools/`; nothing requires the
original computer's drive layout. Python can be supplied explicitly with
`tools/bootstrap-web.ps1 -Python '<path-to-python>'` if needed.

For a release build, from `apps/flutter_ui`:

```powershell
flutter build web --release --no-web-resources-cdn --csp
cd ../..
node tools/verify-deployment.mjs
node tools/preview-web.mjs
```

The preview serves at `http://127.0.0.1:4173`. Browser workflow tests additionally
require the `playwright` Node package and installed Chrome. The Windows scripts
above are the established development setup; Linux hosting uses
`tools/build-vercel.sh` as described in [deployment.md](deployment.md).

## Portable Codex handoff

Suggested first message on the new PC:

> Read README.md, docs/new-device.md, plan.md, and the current phase in todo.md.
> Inspect Git status before edits. Stay on Development. Phases 00-15 are
> implemented; do not start a later phase until I request it. Set up the tools
> needed on this PC and verify the existing project first.

Current scope includes room/catalogue editing, bounded real algorithm playback,
linked BSP/DP inspection, isolated reproducible benchmarks/charts/export, temporary
failure scenarios, and exploration-only Play with native collision and exit completion.
Combat/enemy AI and later phases remain outside this scope. See
[Analyze and benchmarks](analyze_benchmarks.md) and [scenarios and Play](scenarios_play.md).

Preserve these project constraints:

- C++ is authoritative for generation, allocation, validation, and movement.
- Preserve BSP generation and exact subset DP; no silent heuristic fallback.
- Preserve the last valid result on errors and reject stale asynchronous results.
- The app is static Flutter web with C++ Wasm in a Web Worker. Keep strict CSP,
  self-hosted assets, and `--csp --no-web-resources-cdn` release build flags.
- Do not add runtime secrets, server APIs, uploads, accounts, databases, or
  external services without discussing the change.
- Check account usage at session start and milestones. At 15% or less remaining,
  stop implementation and write a concise local handoff. Never invent unavailable
  telemetry. Keep private machine/session details out of committed documents.

Recorded local validation for phases 00-15 includes 19 native suites, 49 Flutter
tests, clean analyzer, Wasm/CSP release builds, artifact verification and real
Chrome scenario/Play and Analyze workflows. Benchmark observations and exact
fixtures are in benchmarks/ and docs/analyze_benchmarks.md. A new PC still needs
its own setup verification; measurements are not universal latency guarantees.

## What cloning includes

Application source, tests, fixtures, vendored dependencies and font assets,
lockfiles, build scripts, `plan.md`, `todo.md`, and `deliverables.md` are versioned.
Installed SDKs, caches, generated binaries, screenshots, saved local dungeon
outputs, credentials, hosting login state, course PDFs, and personal Word
documents are excluded. Copy any personal documents or saved dungeon files you
want separately. The original local `AGENTS.md` and `progression.md` contain
machine/session details and remain excluded; this page provides portable context.

No runtime credentials or Vercel login are required to develop locally. GitHub
and Codex sign-in are configured separately on the new PC. Vercel Git integration
may create a preview for a branch push; production remains on `main`.
