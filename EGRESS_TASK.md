# Egress Isolation Task — Build Then Test

## Goal
Prove the container has uncontrolled outbound internet access, then implement a proxy sidecar that locks it down to ONLY:
- `api.anthropic.com:443`
- `registry.npmjs.org:443`
- `objects.githubusercontent.com:443` (npm package downloads via CDN)
- `*.npm.org:443` (npm metadata fallback)

## Phase 1: Write failing tests FIRST

Create `tests/T-egress-isolation.sh`. This test should:

### Pre-proxy tests (should PASS = vulnerability confirmed):
1. Check that container CAN currently curl https://example.com (exit 0 = vulnerable)
2. Check that container CAN curl https://icanhazip.com (exit 0 = vulnerable)  
3. Check that container CAN curl https://google.com (exit 0 = vulnerable)
4. Check that container CAN resolve 8.8.8.8 (DNS to external = vulnerable)
5. Check that container CAN curl to a local netcat listener simulating exfiltration

### Post-proxy tests (should PASS = properly locked down):
6. Check that container CANNOT curl https://example.com (exit non-0 = blocked)
7. Check that container CANNOT curl https://icanhazip.com (exit non-0 = blocked)
8. Check that container CANNOT curl https://google.com (exit non-0 = blocked)
9. Check that container CAN still reach api.anthropic.com (proxy allows it)
10. Check that npm install of a real package works (registry allowed)
11. Check that the container agent can still call Anthropic API via clawbox CLI
12. Check that exec tool running `curl https://evil.com` inside the container fails

Run the pre-proxy tests first, assert they PASS (confirming vulnerability), document results.

## Phase 2: Build the proxy

### 1. Create `proxy/proxy.js`
A minimal Node.js HTTPS CONNECT proxy (zero dependencies, built-ins only):

```js
const net = require('net');
const http = require('http');

const ALLOWED = [
  'api.anthropic.com',
  'registry.npmjs.org', 
  'objects.githubusercontent.com',
  'npm.org',
  // Allow subdomains
];

function isAllowed(host) {
  return ALLOWED.some(allowed => 
    host === allowed || host.endsWith('.' + allowed)
  );
}

const server = http.createServer((req, res) => {
  res.writeHead(403, {'Content-Type': 'text/plain'});
  res.end('FORBIDDEN: Only Anthropic and npm traffic allowed');
});

server.on('connect', (req, clientSocket, head) => {
  const [host, port] = req.url.split(':');
  
  if (!isAllowed(host)) {
    console.log(`BLOCKED: ${host}:${port}`);
    clientSocket.write('HTTP/1.1 403 Forbidden\r\n\r\n');
    clientSocket.destroy();
    return;
  }
  
  console.log(`ALLOWED: ${host}:${port}`);
  const serverSocket = net.connect(parseInt(port) || 443, host, () => {
    clientSocket.write('HTTP/1.1 200 Connection Established\r\n\r\n');
    serverSocket.write(head);
    serverSocket.pipe(clientSocket);
    clientSocket.pipe(serverSocket);
  });
  
  serverSocket.on('error', (e) => {
    console.error(`Proxy error for ${host}: ${e.message}`);
    clientSocket.destroy();
  });
  clientSocket.on('error', () => serverSocket.destroy());
});

server.listen(8888, '0.0.0.0', () => {
  console.log('Egress proxy listening on :8888 (allowlist: anthropic + npm only)');
});
```

### 2. Create `proxy/Dockerfile`
```dockerfile
FROM node:22-alpine
WORKDIR /app
COPY proxy.js .
EXPOSE 8888
CMD ["node", "proxy.js"]
```

### 3. Update `docker-compose.yml`

Add two networks and the proxy service:

```yaml
networks:
  clawbox-internal:
    internal: true   # NO external routing - containers here cannot reach internet directly
  clawbox-egress:    # Only connects clawbox-work to the proxy
    driver: bridge

services:
  clawbox-egress-proxy:
    build:
      context: proxy
    container_name: clawbox-egress-proxy
    restart: unless-stopped
    networks:
      - clawbox-egress
      # Note: NOT on clawbox-internal, so it has real internet access to forward allowed traffic
    healthcheck:
      test: ["CMD", "node", "-e", "require('net').createConnection(8888,'127.0.0.1').on('connect',()=>process.exit(0)).on('error',()=>process.exit(1))"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 5s

  clawbox-work:
    # ... existing config ...
    depends_on:
      clawbox-egress-proxy:
        condition: service_healthy
    networks:
      - clawbox-internal  # No direct internet
      - clawbox-egress    # Can reach proxy only
    environment:
      # ... existing env ...
      # Route ALL outbound HTTPS through the egress proxy
      - HTTPS_PROXY=http://clawbox-egress-proxy:8888
      - HTTP_PROXY=http://clawbox-egress-proxy:8888
      # Also set for Node.js native fetch / undici (used by OpenClaw/Anthropic SDK)
      - NODE_OPTIONS=--require /home/node/proxy-bootstrap.js ${NODE_OPTIONS:-}
```

### 4. Create `proxy-bootstrap.js` (injected via NODE_OPTIONS)
This ensures the Anthropic SDK's native fetch uses the proxy:

```js
// Injected into every Node.js process via NODE_OPTIONS
// Configures undici (Node.js native fetch) to use the egress proxy
try {
  const { setGlobalDispatcher, ProxyAgent } = require('undici');
  const proxyUrl = process.env.HTTPS_PROXY || process.env.HTTP_PROXY;
  if (proxyUrl) {
    setGlobalDispatcher(new ProxyAgent(proxyUrl));
  }
} catch (e) {
  // undici not available or proxy not configured - silent fallback
}
```

### 5. Update `Makefile`
Add:
```makefile
test-egress: ## Test egress isolation (run pre-proxy tests, then post-proxy)
	@bash tests/T-egress-isolation.sh
```

## Phase 3: Validate

After building, run the post-proxy tests:
- curl to external sites should be BLOCKED
- npm install should still work
- Anthropic API calls should still work
- Agent interaction via clawbox CLI should work

## Important implementation notes

1. The `clawbox-internal: internal: true` setting is the KEY security control. Docker's `internal` network has no default gateway — packets to external IPs are simply dropped by the kernel, not routed.

2. The proxy sidecar itself is NOT on the internal network. It has real internet access and can forward to allowed hosts.

3. Node.js native fetch (used by Anthropic SDK) uses `undici` internally. The `proxy-bootstrap.js` sets the global undici dispatcher to route through the proxy. This means even `fetch()` calls in agent code will be proxied.

4. `curl` and other CLI tools respect `HTTPS_PROXY` env var automatically.

5. For the test: use `--max-time 5` on curl to avoid hanging forever on blocked connections.

## After completing everything:
- git add -A && git commit -m "security: egress isolation via proxy sidecar — only anthropic+npm allowed" && git push
- Run: openclaw system event --text "Done: clawbox egress isolation complete — tests written, pre-proxy vulns confirmed, proxy built, post-proxy tests passing" --mode now
