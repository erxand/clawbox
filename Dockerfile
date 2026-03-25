# OpenClaw Docker — run the gateway in a container
# https://github.com/openclaw/openclaw
FROM node:22-alpine

# Install system deps
# - git: workspace operations and repo cloning
# - tini: proper PID 1 signal handling
# - socat: loopback→LAN bridge (see entrypoint.sh)
# - curl: used by agent tooling
RUN apk add --no-cache git tini socat curl

# Remove setuid/setgid bits from all binaries to reduce privilege escalation risk
RUN find / -xdev -perm /6000 -type f 2>/dev/null | xargs chmod a-s 2>/dev/null || true

# Install openclaw globally
RUN npm install -g openclaw

# The node user already exists in node:22-alpine (uid=1000, gid=1000)
RUN mkdir -p /home/node/.openclaw && chown -R node:node /home/node/.openclaw

# Make npm global dir owned by node so agent can install packages without sudo
RUN mkdir -p /home/node/.npm-global && chown -R node:node /home/node/.npm-global

VOLUME /home/node/.openclaw

EXPOSE 18789

USER node
WORKDIR /home/node

ENV NODE_ENV=production
ENV HOME=/home/node
ENV NPM_CONFIG_PREFIX=/home/node/.npm-global
ENV PATH="/home/node/.npm-global/bin:${PATH}"

# Seed files for first-run workspace initialization
COPY --chown=node:node seed/ /home/node/seed/

# Entrypoint script handles first-run init + signal forwarding
COPY --chown=node:node entrypoint.sh /home/node/entrypoint.sh
RUN chmod +x /home/node/entrypoint.sh

ENTRYPOINT ["/sbin/tini", "--", "/home/node/entrypoint.sh"]
