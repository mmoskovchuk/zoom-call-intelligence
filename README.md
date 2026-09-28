# Zoom Call Intelligence Pipeline

Automated post-call pipeline: **Zoom recording → n8n → OpenAI (Whisper + GPT) → Postgres report**.

The user just records a Zoom call to the cloud — a structured report (summary, participants, key points, action items) appears automatically.

![n8n workflow — successful end-to-end run](docs/workflow.png)

```
Zoom ──(recording.completed, HMAC-signed)──► Cloudflare Tunnel ──► n8n Webhook
                                                                      │
                     verify signature / URL challenge ── respond 200 (<3s)
                                                                      │
   normalize → register event (idempotent) ─ duplicate? → skip        │
                     │ new / previously failed                        │
                     ▼                                                ▼
   Download Audio → Transcribe (Whisper) → Analyze (GPT, strict JSON Schema) → Save Report
         └──────────────┴───────────── any error ──────────────┴──→ Mark Failed
```

### Example output
Stored in `app.call_reports.analysis` (full synthetic example: [`docs/example-report.json`](docs/example-report.json)):
```json
{
  "summary": "Менеджер провів ознайомчий дзвінок з ACME Corp щодо автоматизації обробки клієнтських звернень. …",
  "participants": [{ "name": "Андрій", "role": "керівник служби підтримки, ACME Corp" }, …],
  "key_points": ["Звернення зараз розподіляють вручну три оператори", …],
  "action_items": [{ "task": "Надіслати комерційну пропозицію щодо пілотного проєкту", "owner": "Олена", "due": "до п'ятниці" }, …]
}
```
Report language is set in the system prompt (Ukrainian); field names follow the schema.

## Stack
| Service     | Purpose |
|-------------|---------|
| `n8n`       | Orchestration (pinned version), Postgres-backed, binary data on filesystem |
| `postgres`  | n8n metadata + app schema `app`: `processed_events` (idempotency/status), `call_reports` (transcript + analysis JSONB) |
| `mock-zoom` | Dev/test stand-in for Zoom file storage — end-to-end tests without a paid Zoom plan |
| `tunnel`    | Cloudflare quick tunnel → public HTTPS for Zoom (profile `tunnel`) |

## Quick start
```bash
make init          # .env with generated secrets
make up            # postgres + n8n + mock-zoom → http://localhost:${N8N_HOST_PORT}
make db-migrate    # app schema (db/migrations/*.sql)
make import        # load workflows/*.json
```
Then in n8n create two credentials (they are never exported to git) and select them in the nodes:
- **Postgres** — host `postgres`, database `n8n`, user `n8n`, password from `.env`.
- **OpenAI** — API key; restrict *Allowed HTTP Request Domains* to `api.openai.com`.

```bash
make publish ID=zoomIntake00001
```

## Tests
Put a short speech recording at `fixtures/audio/sample.m4a` (see `fixtures/audio/README.md`), then:

| Command | Checks | OpenAI cost |
|---|---|---|
| `make test-webhook` | signature verification, URL validation, `401` on bad signature | — |
| `make test-idempotency` | same event twice → one row, duplicate skipped | ✓ |
| `make test-failure` | missing audio → retries → event marked `failed` | — |
| `make test-e2e` | full pipeline → `call_reports` row, status `done` | ≈ $0.006/min audio |
| `make last-execution` | summary of the latest run (nodes, status, binary metadata — never item data) | — |

## Design notes
- **Respond first, process later** — Zoom expects a reply within 3 s; transcription takes minutes.
- **Idempotency** — `UNIQUE(idempotency_key)` + `INSERT … ON CONFLICT`; duplicates are skipped atomically, previously failed events are re-processed.
- **Structured Outputs** — GPT is constrained by [`schemas/call_analysis.schema.json`](schemas/call_analysis.schema.json) (`strict: true`), so the report shape is guaranteed.
- **Error path** — download/transcribe/analyze/save errors go to an error output → `Mark Failed` stores a short message (never the failed query, which may contain the transcript).
- **Atomic save** — report insert and status update in one SQL statement (CTE).

## Zoom setup
1. Zoom Marketplace → *Develop → Build App → General App* (or Webhook-only app).
2. *Features → Access*: copy **Secret Token** → `ZOOM_WEBHOOK_SECRET_TOKEN` in `.env`, `make up`.
3. `make tunnel` → copy printed URL → *Event Subscriptions* → Endpoint URL → **Validate**.
4. Subscribe to **Recording → All Recordings have completed** (`recording.completed`).
5. Scopes: `cloud_recording:read:list_recording_files` (download via `download_token`).

> Quick tunnel URLs change on restart; re-validate the endpoint in Zoom.

## Workflows
| File | Description |
|---|---|
| `workflows/zoomIntake00001.json` | 01 · Zoom Webhook Intake → full pipeline: HMAC verification (timing-safe, 5-min replay window), URL validation, normalization, idempotency, download, Whisper, GPT analysis, report storage, error handling |

Workflow changes are made in the UI and committed via `make export` (strips owner info and pinned data).

## Security & privacy
- `x-zm-signature` verified for every request; invalid → `401`.
- n8n bound to `127.0.0.1`; only the tunnel is public.
- Secrets live in `.env` / encrypted n8n credentials; `.env.example` documents all variables.
- Test recordings (`fixtures/audio/*`) are git-ignored; transcripts stay in the local database.
