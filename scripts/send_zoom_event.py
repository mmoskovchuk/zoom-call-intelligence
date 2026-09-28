#!/usr/bin/env python3
"""Send a Zoom-signed webhook event to the local n8n endpoint (stdlib only).

Usage:
  scripts/send_zoom_event.py fixtures/zoom/recording.completed.json
  scripts/send_zoom_event.py fixtures/zoom/endpoint.url_validation.json --url https://xxx.trycloudflare.com/webhook/zoom
  scripts/send_zoom_event.py fixtures/zoom/recording.completed.json --bad-signature
"""
import argparse
import hashlib
import hmac
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path


def load_env(path: Path) -> None:
    if not path.exists():
        return
    for line in path.read_text().splitlines():
        if line.strip() and not line.lstrip().startswith("#") and "=" in line:
            key, value = line.split("=", 1)
            os.environ.setdefault(key.strip(), value.strip())


def main() -> int:
    load_env(Path(__file__).resolve().parent.parent / ".env")
    port = os.environ.get("N8N_HOST_PORT", "5678")

    parser = argparse.ArgumentParser()
    parser.add_argument("fixture", type=Path)
    parser.add_argument("--url", default=f"http://localhost:{port}/webhook/zoom")
    parser.add_argument("--bad-signature", action="store_true")
    args = parser.parse_args()

    secret = os.environ.get("ZOOM_WEBHOOK_SECRET_TOKEN")
    if not secret:
        sys.exit("ZOOM_WEBHOOK_SECRET_TOKEN is not set")

    event = json.loads(args.fixture.read_text())
    event["event_ts"] = int(time.time() * 1000)
    body = json.dumps(event, separators=(",", ":"), ensure_ascii=False)

    ts = str(int(time.time()))
    key = b"wrong-secret" if args.bad_signature else secret.encode()
    signature = "v0=" + hmac.new(key, f"v0:{ts}:{body}".encode(), hashlib.sha256).hexdigest()

    req = urllib.request.Request(
        args.url,
        data=body.encode(),
        method="POST",
        headers={
            "Content-Type": "application/json",
            "x-zm-request-timestamp": ts,
            "x-zm-signature": signature,
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            status, payload = resp.status, resp.read().decode()
    except urllib.error.HTTPError as err:
        status, payload = err.code, err.read().decode()

    print(f"HTTP {status}\n{payload}")

    if event["event"] == "endpoint.url_validation" and status == 200:
        plain = event["payload"]["plainToken"]
        expected = hmac.new(secret.encode(), plain.encode(), hashlib.sha256).hexdigest()
        ok = json.loads(payload).get("encryptedToken") == expected
        print(f"encryptedToken check: {'OK' if ok else 'MISMATCH'}")
        return 0 if ok else 1
    return 0 if status < 400 or args.bad_signature else 1


if __name__ == "__main__":
    sys.exit(main())
