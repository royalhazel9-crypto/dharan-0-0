# Dharan Explorer — Deployment Infrastructure

Production build pipeline, containerization, CI/CD, and monitoring for the
Dharan Explorer static site.

## Architecture

```
src/index.html  ──▶  npm run build  ──▶  dist/  ──▶  Docker image  ──▶  registry (GHCR)
                (Tailwind compiled,                 (nginx-unprivileged,        │
                 HTML minified)                      non-root, port 8080)       ▼
                                                                        prod host / cluster
                                                                        (pull + docker compose up)
                                                                                 │
                                                                    Prometheus ──┴── Grafana
                                                                   (nginx-exporter scrapes /nginx_status)
```

The source (`src/index.html`) still uses the Tailwind **Play CDN** for a
zero-install local preview. The build step compiles an actual Tailwind
stylesheet from source and strips the CDN `<script>`, so the production image
ships no third-party runtime dependency and gets a materially tighter CSP.

## Local development

```bash
npm ci
npm run dev          # serves src/ as-is (CDN Tailwind) at http://localhost:8000
```

## Production build

```bash
npm run build         # -> dist/ (compiled CSS, minified HTML)
npm run serve:dist     # sanity-check the built output locally
```

## Docker

```bash
docker build -t dharan-explorer:local .
docker run --rm -p 8080:8080 dharan-explorer:local
curl http://localhost:8080/healthz   # -> ok
```

The runtime image is `nginxinc/nginx-unprivileged`, runs as a non-root user,
and the container in `docker-compose.yml` additionally runs `read_only: true`
with `tmpfs` mounts for nginx's writable paths and `no-new-privileges`.

## docker-compose

```bash
cp .env.example .env      # set IMAGE / WEB_PORT / GRAFANA_ADMIN_PASSWORD

docker compose up -d --build web        # site only
docker compose --profile monitoring up -d   # + Prometheus + Grafana + nginx-exporter
```

| Service | URL |
|---|---|
| Site | http://localhost:8080 |
| Prometheus | http://localhost:9090 |
| Grafana | http://localhost:3000 (import `monitoring/grafana-dashboard.json`, or add Prometheus at `http://prometheus:9090` as a data source first) |

## CI/CD (GitHub Actions)

- **`.github/workflows/ci.yml`** — every PR/push to `main`: lints the HTML,
  runs the production build, builds the Docker image, and fails the build on
  any CRITICAL/HIGH CVE found by Trivy.
- **`.github/workflows/cd.yml`** — on push to `main` (or a `vX.Y.Z` tag):
  builds and pushes the image to GHCR (tagged by commit SHA, `latest`, and
  semver where applicable), then deploys over SSH by running
  `docker compose pull && up -d` on the target host.

  Swap the `deploy` job for `kubectl rollout restart` / a PaaS deploy hook /
  `terraform apply` if the target isn't a single Docker host.

  Required repository secrets for the SSH deploy path:
  `DEPLOY_HOST`, `DEPLOY_USER`, `DEPLOY_SSH_KEY`.

## Monitoring & alerting

- nginx emits structured JSON access logs to stdout (`nginx/nginx.conf`) —
  ready to ship to any log pipeline (Loki, ELK, CloudWatch Logs).
- `nginx-prometheus-exporter` scrapes `ngx_http_stub_status_module` at
  `/nginx_status` (restricted to the compose network) for connection-level
  metrics (`nginx_up`, active/accepted/handled connections, request count).
- `monitoring/alerts.yml` ships two starter rules: `SiteDown` and
  `ConnectionSaturation`. `stub_status` doesn't expose per-status-code or
  latency data — for 5xx-rate/p95-latency alerting, ship the JSON logs to a
  log pipeline and alert there, or switch the base image to one built with
  the nginx VTS module if you want that natively in Prometheus.
- `/healthz` is a plain 200 endpoint for container/orchestrator health checks
  and load-balancer probes, independent of the metrics stack.

## Scaling notes

- The app is fully static, so the most scalable option overall is skipping
  container hosting for the edge entirely and serving `dist/` from an
  object-storage + CDN origin (Cloudflare Pages, S3+CloudFront, Netlify) —
  worth it once traffic or global latency matters. The pipeline above still
  applies: same `npm run build` output, different deploy target.
- If staying on containers: this image has no local state, so it scales
  horizontally by running more replicas behind a load balancer (Compose
  `--scale web=N` behind an external LB, an ECS/Cloud Run service, or a
  Kubernetes `Deployment` + `HorizontalPodAutoscaler` keyed on CPU or
  request rate).
- `limit_req_zone` in `nginx/nginx.conf` gives basic per-IP request throttling
  at the container level; put a CDN/WAF in front for real abuse protection at
  scale.

## Security notes

- CSP allows `'unsafe-inline'` for scripts/styles because the app's logic is
  written as inline `<script>` and inline event-handler attributes
  (`onclick`, `onload`, `onerror`). If the frontend is ever refactored to an
  external bundle, tighten `nginx/default.conf`'s CSP to a nonce/hash policy.
- `frame-src`/`img-src` are scoped to `https://www.google.com` and Google
  Fonts hosts only — matching exactly what the page actually loads.
- Trivy scans the built image on every CI run and gates merges on
  CRITICAL/HIGH findings; the CD run also scans the pushed image (report-only,
  since CI already gated the merge).
