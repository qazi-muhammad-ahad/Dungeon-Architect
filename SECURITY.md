# Security

Dungeon Architect is a static Flutter application. Its C++ engine runs as
WebAssembly in a dedicated browser worker. There is no HTTP API, account system,
database, server-side generation, remote file upload, or runtime credential.
Projects are read and saved on the visitor's computer. The `api/` source directory
defines the C ABI; it is not a web endpoint and is not deployed.

Only `apps/flutter_ui/build/web` is served. Deployment checks reject source maps,
source files, secrets, and internal directories. CanvasKit and engine assets are
self-hosted. The content security policy restricts scripts and connections to the
same origin, allows WebAssembly compilation, and blocks framing and form posts.
Flutter requires inline styling; inline JavaScript and general JavaScript eval
are not allowed. HTTPS, MIME protection and browser permission restrictions are
configured in `vercel.json`.

The engine accepts at most 16 MiB of project input, uses at most 512 MiB of Wasm
memory, permits one executing job per worker, and validates dimensions, algorithm
work limits, and the 14-active-pack exact-solver limit. These safeguards protect
normal browser use; client-side controls are not a network security boundary.

Traffic rate limiting belongs to the Vercel project firewall, ahead of static
asset delivery. It is configured separately from `vercel.json`; consult
`docs/deployment.md` for its setup and verification status. Vercel's platform
DDoS mitigation is automatic. Neither it nor rate limiting guarantees immunity
to every attack or bandwidth exhaustion.

Do not commit credentials or add keys to Dart/JavaScript or build arguments.
Public browser assets and this public repository are inspectable by anyone.
Future server-backed features require a fresh security review and server-side
authentication, authorization, validation, and rate limiting.

Report vulnerabilities privately through the repository owner's GitHub profile;
do not include credentials or private project files in a public issue.
