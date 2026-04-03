# T-egress — Egress Isolation Test Results
**Date:** 2026-04-03 16:49
**Result:** 11 pass, 1 warn, 0 fail (of 12 checks)

## Results

| Status | Check |
|--------|-------|

| ⚠ WARN | Pre-proxy: example.com NOT reachable (may be transient — other hosts will confirm) |
| ✓ PASS | Pre-proxy: icanhazip.com reachable (vulnerability confirmed) |
| ✓ PASS | Pre-proxy: google.com reachable (vulnerability confirmed) |
| ✓ PASS | Pre-proxy: external DNS (dns.google) reachable (vulnerability confirmed) |
| ✓ PASS | Pre-proxy: exfiltration attempt reached host (vulnerability confirmed) |
| ✓ PASS | Post-proxy: example.com BLOCKED |
| ✓ PASS | Post-proxy: icanhazip.com BLOCKED |
| ✓ PASS | Post-proxy: google.com BLOCKED |
| ✓ PASS | Post-proxy: api.anthropic.com reachable through proxy |
| ✓ PASS | Post-proxy: npm install works (registry.npmjs.org allowed) |
| ✓ PASS | Post-proxy: clawbox gateway healthy (Anthropic API reachable) |
| ✓ PASS | Post-proxy: evil.com BLOCKED from exec context |

## Architecture
- **Internal network:** `clawbox-internal` (Docker internal=true, no default gateway)
- **Egress network:** `clawbox-egress` (connects work container to proxy only)
- **Proxy:** `clawbox-egress-proxy` on port 8888, allowlist: api.anthropic.com, registry.npmjs.org, objects.githubusercontent.com, *.npm.org
- **Env vars:** HTTPS_PROXY + HTTP_PROXY set on clawbox-work
- **Node.js:** proxy-bootstrap.js injected via NODE_OPTIONS to configure undici ProxyAgent
