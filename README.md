# Zoom Call Intelligence Pipeline

Automated post-call pipeline: **Zoom recording → n8n → OpenAI (Whisper + GPT) → Postgres report**.

The user just records a Zoom call to the cloud — a structured report (summary, participants, key points, action items) appears automatically.

```
Zoom ──(recording.completed, HMAC-signed)──► Cloudflare Tunnel ──► n8n Webhook
                                                                      │
                               ┌──────────────────────────────────────┤
                               ▼                                      ▼
                     verify signature / URL challenge        respond 200 (<3s)
                               │
                               ▼
          normalize → dedupe → download audio → Whisper → GPT (JSON schema) → Postgres
                     [step 2]      [step 2]      [step 2]      [step 3]       [step 4]
```

## Stack
| Service    | Purpose                                             |
|------------|-----------------------------------------------------|
| `n8n`      | Orchestration, pinned version, Postgres-backed      |
| `postgres` | n8n metadata/executions + app tables (`processed_events`, `call_reports`) |
| `tunnel`   | Cloudflare quick tunnel → public HTTPS for Zoom (profile `tunnel`) |

## Quick start
```bash
make init          # .env with generated secrets
make up            # postgres + n8n → http://localhost:${N8N_HOST_PORT}
make import        # load workflows/*.json
make publish ID=zoomIntake00001
make test-webhook  # signed fixtures: url_validation, recording.completed, bad signature
```

## Zoom setup
1. Zoom Marketplace → *Develop → Build App → General App* (or Webhook-only app).
2. *Features → Access*: copy **Secret Token** → `ZOOM_WEBHOOK_SECRET_TOKEN` in `.env`, `make up`.
3. `make tunnel` → copy printed URL → *Event Subscriptions* → Endpoint URL → **Validate**.
4. Subscribe to **Recording → All Recordings have completed** (`recording.completed`).
5. Scopes: `cloud_recording:read:list_recording_files` (download via `download_token`).

> Quick tunnel URLs change on restart; update `WEBHOOK_URL` in `.env` and re-validate in Zoom.

## Workflows
| File                             | Description                                               |
|----------------------------------|-----------------------------------------------------------|
| `workflows/zoomIntake00001.json` | 01 · Zoom Webhook Intake: HMAC verification (timing-safe, 5-min replay window), URL validation challenge, event routing, payload normalization |

Workflow changes are made in the UI and committed via `make export`.

## Security
- `x-zm-signature` verified for every request; invalid → `401`.
- n8n bound to `127.0.0.1`; only the tunnel is public.
- Secrets live in `.env` (git-ignored); `.env.example` documents all variables.
