// Injected into every Node.js process via NODE_OPTIONS
// Configures undici (Node.js native fetch) to use the egress proxy
try {
  const { setGlobalDispatcher, ProxyAgent } = require('undici');
  const proxyUrl = process.env.HTTPS_PROXY || process.env.HTTP_PROXY;
  if (proxyUrl) {
    setGlobalDispatcher(new ProxyAgent(proxyUrl));
  }
} catch (e) {
  // undici not available or proxy not configured — silent fallback
}
