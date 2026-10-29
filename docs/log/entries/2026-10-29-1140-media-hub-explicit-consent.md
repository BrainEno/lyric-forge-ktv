# [2026-10-29 11:40] Secure Media Hub with fingerprint-pinned HTTPS

- Scope: Resolve the critical transport problem in issue #218 by replacing plaintext LAN Media Hub traffic with HTTPS using a persisted per-installation certificate/key pair and SHA-256 certificate pinning delivered through the pairing QR code and authenticated discovery. Keep sharing off by default, require explicit scope consent, and restrict listener binding to private-LAN/Tailscale IPv4 and loopback.
- Protocol and playback: require protocol version 2, move session-token auth to the Authorization bearer header, remove tokens from playback URLs, and proxy native audio through loopback while preserving HTTP Range semantics on the pinned HTTPS hop. HTTPS also protects track metadata, lyrics, artwork, and uploads.
- Android: deny cleartext traffic globally; allow only the loopback native-audio proxy to use HTTP.
- UI: describe the real HTTPS trust model and what paired devices can access; do not continue warning that the updated Media Hub still uses plaintext HTTP.
- Validation on commit `3c264855420dd65f31492e2295cd079220f5c4b4`: Flutter Quality Gate passed, KTV history/recovery validation passed, and Windows Debug native build passed. A final run is required after the current copy/test cleanup.
- Boundaries: legacy v1 saved connections must pair again; IPv4 is currently supported; physical devices still need a real pairing and playback smoke test.
- Commit currently validated: `3c264855420dd65f31492e2295cd079220f5c4b4`.
