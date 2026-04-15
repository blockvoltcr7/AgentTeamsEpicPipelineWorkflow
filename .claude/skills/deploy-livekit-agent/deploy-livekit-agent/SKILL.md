---
name: deploy-livekit-agent
description: Deploy the OS HQ voice agent to LiveKit Cloud. Use when deploying, redeploying, or rolling back the LiveKit agent in apps/agent/. Triggers on "deploy agent", "deploy livekit", "push agent to production", "update the agent", "rollback agent". Covers initial setup, updates, secrets, and rollback.
---

# LiveKit Agent Deployment

## Project Config

- **Agent directory:** `apps/agent/`
- **Agent ID:** `CA_Qi5VAPFU2HJq`
- **Project subdomain:** `os-hq-co8kd657`
- **Region:** `us-east`
- **Config file:** `apps/agent/livekit.toml`
- **Agent name:** `os-hq-agent` (used in `ServerOptions` and `RoomAgentDispatch`)

## Prerequisites

1. `lk` CLI installed (`brew install livekit-cli`)
2. Authenticated: `lk cloud auth` (select OS HQ project)
3. Default project set: `lk project set-default "os-hq"`

Docker is **not** required locally — builds happen on LiveKit Cloud's build service.

## Deploy (Update Existing Agent)

```bash
cd apps/agent && lk agent deploy
```

This reads `livekit.toml`, uploads your code, builds the Docker image on LiveKit Cloud, and performs a **rolling deployment**:

1. **Build** — CLI uploads code, Cloud builds container from Dockerfile
2. **Deploy** — New instances start alongside old ones
3. **Route** — Once new instances pass health checks, new sessions route to them
4. **Drain** — Old instances stop accepting new sessions, get up to 1 hour to finish active ones
5. **Scale** — Old instances shut down, new instances autoscale to meet demand

Zero downtime throughout.

## Initial Setup (First-Time Only)

If `livekit.toml` does not exist:

```bash
cd apps/agent && lk agent create
```

This registers the agent, generates `livekit.toml`, uploads secrets from `.env.local`, builds the image, and deploys. After this, use `lk agent deploy` for all subsequent updates.

## Secrets Management

LiveKit Cloud injects secrets as environment variables at runtime. They are **not** baked into the Docker image (`.env.*` is in `.dockerignore`).

**Auto-injected by LiveKit Cloud (do NOT set manually):**
- `LIVEKIT_URL`
- `LIVEKIT_API_KEY`
- `LIVEKIT_API_SECRET`

**Required application secrets:**
- `OPENAI_API_KEY` — LLM (GPT-4.1-mini) and inference
- `GHL_SYNC_SERVICE_URL` — GHL microservice base URL for tool calls

### Update secrets from file

```bash
lk agent update-secrets --secrets-file .env.local
```

The CLI reads `.env.local` and uploads all key-value pairs (excluding LiveKit credentials).

### Update individual secrets

```bash
lk agent update-secrets --secrets "OPENAI_API_KEY=sk-..." --secrets "GHL_SYNC_SERVICE_URL=https://..."
```

### Overwrite all secrets (replace, not merge)

```bash
lk agent update-secrets --secrets-file .env.local --overwrite
```

### List current secrets

```bash
lk agent secrets
```

Shows names and timestamps. Values cannot be retrieved.

Secrets persist across deploys. Updating secrets triggers a rolling restart.

## Rollback

```bash
lk agent rollback
```

Instant rollback to the previous version without a rebuild. Uses the same rolling deployment strategy.

Or deploy a specific git ref by checking out the commit and running `lk agent deploy`.

## Verify Deployment

1. Check agent status: `lk agent status`
2. Tail logs: `lk agent logs`
3. Test from web app: navigate to `/member/agent` and start a voice session

## Dockerfile Notes

- Multi-stage build: `node:22-slim` base
- Stage 1 (build): `pnpm install` → `pnpm build` (tsc) → `pnpm download-files` (pre-downloads Silero VAD + turn-detector ONNX models) → `pnpm prune --prod`
- Stage 2 (production): copies built app, runs as unprivileged `appuser`
- Uses `--no-frozen-lockfile` (standalone package, no root monorepo lockfile)
- Production entrypoint: `pnpm start` → `node dist/main.js start`
- Build context size limit: 1 GB. Build timeout: 10 minutes.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `lk: command not found` | Install: `brew install livekit-cli` |
| `not authenticated` | Run `lk cloud auth`, select OS HQ project |
| `agent not found` | Check `livekit.toml` exists with correct agent ID |
| Agent doesn't join rooms | Verify `agentName: "os-hq-agent"` matches `RoomAgentDispatch` in `token-server.ts` |
| Missing API keys at runtime | Update secrets: `lk agent update-secrets --secrets-file .env.local` |
| Build fails or times out | Check `.dockerignore` excludes `node_modules/`, `.git/`; build must complete within 10 min |
| Health check fails (5 min timeout) | Ensure `prewarm` (Silero VAD load) completes quickly; check `lk agent logs` |
| Local dev agent conflicts with prod | Local `pnpm dev` registers another worker — LiveKit load-balances. Stop local dev or use a different `agentName` for dev |
