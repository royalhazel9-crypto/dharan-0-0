# syntax=docker/dockerfile:1

# ---------- Stage 1: build ----------
# Compiles Tailwind CSS from source (no CDN in production) and minifies HTML.
FROM node:20-alpine AS build
WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm ci --no-audit --no-fund

COPY tailwind.config.js ./
COPY scripts ./scripts
COPY src ./src
RUN npm run build

# ---------- Stage 2: runtime ----------
# Unprivileged nginx image: runs as a non-root user out of the box and
# listens on port 8080 instead of 80, per container security best practice.
FROM nginxinc/nginx-unprivileged:1.27-alpine AS runtime

# Metadata (OCI standard labels)
LABEL org.opencontainers.image.title="dharan-explorer" \
      org.opencontainers.image.description="Dharan Explorer — static local guide site" \
      org.opencontainers.image.licenses="MIT"

COPY --chown=nginx:nginx nginx/nginx.conf /etc/nginx/nginx.conf
COPY --chown=nginx:nginx nginx/default.conf /etc/nginx/conf.d/default.conf
COPY --from=build --chown=nginx:nginx /app/dist /usr/share/nginx/html

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD wget -qO- --no-verbose --tries=1 http://127.0.0.1:8080/healthz || exit 1

# nginx-unprivileged image already sets USER nginx and a valid CMD/ENTRYPOINT
