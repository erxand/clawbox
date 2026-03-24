# OpenClaw Docker — run the gateway in a container
# https://github.com/openclaw/openclaw
FROM node:22-alpine

# System deps for openclaw (git for workspace, openssl for token gen)
RUN apk add --no-cache git tini socat

# Install openclaw globally
RUN npm install -g openclaw

# The node user already exists in node:22-alpine with home /home/node
# Set up the state directory as a volume mount point
RUN mkdir -p /home/node/.openclaw && chown -R node:node /home/node/.openclaw

VOLUME /home/node/.openclaw

# Default gateway port
EXPOSE 18789

USER node
WORKDIR /home/node

ENV NODE_ENV=production
ENV HOME=/home/node

# Seed files for first-run workspace initialization
COPY --chown=node:node seed/ /home/node/seed/

# Entrypoint script handles first-run init + signal forwarding
COPY --chown=node:node entrypoint.sh /home/node/entrypoint.sh
RUN chmod +x /home/node/entrypoint.sh

# tini ensures proper signal handling (PID 1 reaping)
ENTRYPOINT ["/sbin/tini", "--", "/home/node/entrypoint.sh"]
