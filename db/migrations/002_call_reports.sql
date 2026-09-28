-- Final pipeline output: one report per processed event.
CREATE TABLE IF NOT EXISTS app.call_reports (
    id            bigserial   PRIMARY KEY,
    event_id      bigint      NOT NULL UNIQUE
                  REFERENCES app.processed_events (id) ON DELETE CASCADE,
    meeting_uuid  text        NOT NULL,
    meeting_topic text,
    host_email    text,
    start_time    timestamptz,
    duration_min  integer,
    transcript    text        NOT NULL,
    analysis      jsonb       NOT NULL,   -- schemas/call_analysis.schema.json
    created_at    timestamptz NOT NULL DEFAULT now()
);
