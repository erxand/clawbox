const net = require('net');
const http = require('http');

const ALLOWED = [
  'api.anthropic.com',
  'registry.npmjs.org',
  'objects.githubusercontent.com',
  'npm.org',
];

function isAllowed(host) {
  return ALLOWED.some(allowed =>
    host === allowed || host.endsWith('.' + allowed)
  );
}

const server = http.createServer((req, res) => {
  res.writeHead(403, { 'Content-Type': 'text/plain' });
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
