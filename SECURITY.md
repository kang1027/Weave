# Security Policy

## Supported versions

Only the latest release is supported. Please update before reporting an issue.

## Reporting a vulnerability

Please **do not** open a public issue for security problems.

- Use GitHub's [private vulnerability reporting](https://github.com/kang1027/Weave/security/advisories/new), or
- email **kang@opq.ooo**.

Include steps to reproduce and the affected version. I aim to acknowledge reports within a few days and will keep you updated on a fix.

## How Weave protects you

- **Distribution** — release builds are signed with an Apple Developer ID and notarized by Apple, so macOS Gatekeeper runs them without warnings.
- **Updates** — delivered via Sparkle over HTTPS and verified with an **EdDSA (Ed25519)** signature; an unsigned or tampered update is rejected.
- **No secrets at rest** — Weave stores no passwords, tokens, or account credentials; it has no account system.
- **Local-only data** — see [PRIVACY.md](PRIVACY.md).
