# Test audio (not committed)

Put any short speech recording here as `sample.m4a` (1–10 min, < 25 MB — Whisper limit).
Sources: a Zoom **local** recording (free plan), a phone voice memo, etc.

The `mock-zoom` service serves this folder at `http://mock-zoom:8000/`, and
`fixtures/zoom/recording.completed.json` points its audio `download_url` there,
so the pipeline can be tested end-to-end without a paid Zoom account.

**Phone recordings** are often a 3GP container with a `.m4a` name — OpenAI rejects them
(`Invalid file format`). Remux to real M4A without re-encoding:

```bash
docker run --rm --user "$(id -u):$(id -g)" -v "$PWD/fixtures/audio":/a -w /a python:3.12-alpine \
  sh -c 'apk add -q ffmpeg && ffmpeg -i input.m4a -map 0:a -c copy -f ipod sample.m4a'
```

Then update `file_size` in `fixtures/zoom/recording.completed.json`.

Files here are git-ignored: recordings may contain real voices and personal data.
