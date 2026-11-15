# Qwen runtime TLS test identity

The PEM certificate and private key in this directory are a public, test-only
self-signed identity generated for local Dart HTTP integration tests. Its
certificate is deliberately backdated to avoid CI clock-skew flakiness. These
files must never be used by the application or a packaged runtime. Production
sessions create a fresh ephemeral Rustls certificate and key in the child
process.
