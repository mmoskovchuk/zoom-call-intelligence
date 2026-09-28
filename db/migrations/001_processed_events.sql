-- Idempotency registry: one row per (meeting, recording file).
-- Zoom retries webhooks, so the same event may arrive more than once.
CREATE SCHEMA IF NOT EXISTS app;

CREATE TABLE IF NOT EXISTS app.processed_events (
    id              bigserial   PRIMARY KEY,
    idempotency_key text        NOT NULL UNIQUE,          -- "<meeting_uuid>:<file_id>"
    source          text        NOT NULL DEFAULT 'zoom',
    meeting_uuid    text        NOT NULL,
    file_id         text        NOT NULL,
    status          text        NOT NULL DEFAULT 'received'
                    CHECK (status IN ('received', 'done', 'failed')),
    error           text,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now()
);
