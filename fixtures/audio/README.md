# Test audio (not committed)

Put any short speech recording here as `sample.m4a` (1–10 min, < 25 MB — Whisper limit).
Sources: a Zoom **local** recording (free plan), a phone voice memo, etc.

The `mock-zoom` service serves this folder at `http://mock-zoom:8000/`, and
`fixtures/zoom/recording.completed.json` points its audio `download_url` there,
so the pipeline can be tested end-to-end without a paid Zoom account.

Files here are git-ignored: recordings may contain real voices and personal data.
