# Public browser deployment

Live app: https://dungeon-architet.vercel.app
Repository: https://github.com/qazi-muhammad-ahad/Dungeon-Architect

The browser app uses the same C++ algorithms as the CLI, compiled to WebAssembly.
Vercel serves static files only. No server functions, API endpoints, database,
account system, or runtime environment variables are required.

## Rebuild on Vercel

Import `qazi-muhammad-ahad/Dungeon-Architect` using the repository root and the
Other framework preset. `vercel.json` supplies the build command and output
directory. `tools/build-vercel.sh` installs pinned Flutter 3.47.5, Emscripten
6.0.12, and CMake 3.31.10, compiles the C++ engine, builds Flutter with CSP support
and local CanvasKit, then checks the deployment contents. Subsequent pushes to
`main` can deploy through Vercel's Git integration.

Only `apps/flutter_ui/build/web` is public on the website. The source repository
is public separately. Course PDFs and personal DOCX files remain on the author's
computer and are intentionally excluded from Git and deployments.

## Verify locally on Windows

```powershell
.\tools\build-web-engine.ps1
cd apps/flutter_ui
flutter pub get --enforce-lockfile
flutter build web --release --no-web-resources-cdn --csp
flutter test
cd ../..
node tools/verify-deployment.mjs
node tools/preview-web.mjs
```

Open `http://127.0.0.1:4173` in current desktop Chrome. The preview applies the
production security headers, so it catches CSP regressions in Flutter and Wasm.
The editor uses in-page navigation; missing files and `/api/*` should return 404,
not an SPA fallback. Test Generate & solve, cancellation, and local file saving.

`docs/github-actions-ci.yml` is an optional GitHub Actions workflow template for
building and testing the native engine and complete Linux web build. It is not
active: the current GitHub OAuth permission does not allow publishing workflows.
An owner can move it to `.github/workflows/ci.yml` after approving that permission.
The template uses read-only job permissions and pins external actions to commits.

## Firewall

Vercel applies platform DDoS mitigation automatically. A project-level fixed-window
rate limit is published and allows 600 requests per 60 seconds per IP for all paths and returns
429 above the limit. Confirmed active on 2026-10-13, with no pending drafts.
This accommodates the app's asset downloads and shared
classroom networks; generation itself makes no network requests. Counters are
regional, and distributed sources can exceed any single-IP limit.

Firewall configuration is account state, not part of `vercel.json`. Verify the
active rule in the project's Firewall dashboard after configuring it. Do not
claim a rule is enforced merely because a draft exists. Keep automatic DDoS
mitigation enabled. Avoid paid plan upgrades or account-wide changes for this
demonstration. See [Vercel rate limiting](https://vercel.com/docs/vercel-firewall/vercel-waf/rate-limiting).

See [SECURITY.md](../SECURITY.md) for the threat model and browser-side limits.
