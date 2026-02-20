#!/usr/bin/env python3
import argparse
import base64
import json
import os
import pathlib
import sys
import time
import urllib.error
import urllib.request


def read_api_key(root: pathlib.Path) -> str:
    env_key = os.environ.get("GEMINI_API_KEY", "").strip()
    if env_key:
        return env_key
    key_file = root / "credentials" / "gemini_api_key"
    if key_file.exists():
        return key_file.read_text(encoding="utf-8").strip()
    return ""


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate images via Gemini (Nano Banana path).")
    parser.add_argument("--prompt", required=True, help="Text prompt for image generation.")
    parser.add_argument("--model", default=os.environ.get("NANO_BANANA_MODEL", "gemini-2.5-flash-image"))
    parser.add_argument("--out", default="", help="Output image path (.png).")
    args = parser.parse_args()

    root = pathlib.Path(os.environ.get("OPENCLAW_ROOT", "/Users/bilal/.openclaw"))
    api_key = read_api_key(root)
    if not api_key:
        print(json.dumps({"ok": False, "error": "missing_api_key", "message": "Set GEMINI_API_KEY or credentials/gemini_api_key"}))
        return 1

    out_dir = root / "outputs" / "images"
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = pathlib.Path(args.out) if args.out else out_dir / f"nano-banana-{int(time.time())}.png"

    url = f"https://generativelanguage.googleapis.com/v1beta/models/{args.model}:generateContent"
    payload = {
        "contents": [{"parts": [{"text": args.prompt}]}],
        "generationConfig": {"responseModalities": ["TEXT", "IMAGE"]},
    }

    req = urllib.request.Request(
        url=url,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "x-goog-api-key": api_key,
        },
        data=json.dumps(payload).encode("utf-8"),
    )

    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            raw = resp.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        try:
            parsed = json.loads(body)
            message = parsed.get("error", {}).get("message", f"http_{e.code}")
        except Exception:
            parsed = {"raw": body}
            message = f"http_{e.code}"
        print(json.dumps({"ok": False, "error": "http_error", "status": e.code, "message": message, "details": parsed}))
        return 1
    except Exception as e:
        print(json.dumps({"ok": False, "error": "request_failed", "message": str(e)}))
        return 1

    try:
        data = json.loads(raw)
    except Exception:
        print(json.dumps({"ok": False, "error": "invalid_json", "message": "provider returned non-json"}))
        return 1

    if "error" in data:
        print(json.dumps({"ok": False, "error": "provider_error", "details": data["error"]}))
        return 1

    image_b64 = ""
    text_out = ""
    for cand in data.get("candidates", []):
        parts = cand.get("content", {}).get("parts", [])
        for part in parts:
            if not text_out and isinstance(part.get("text"), str):
                text_out = part["text"]
            inline = part.get("inlineData") or {}
            if inline.get("data"):
                image_b64 = inline["data"]
                break
        if image_b64:
            break

    if not image_b64:
        print(json.dumps({"ok": False, "error": "no_image_data", "message": "No inline image returned", "response": data}))
        return 1

    try:
        image_bytes = base64.b64decode(image_b64)
    except Exception as e:
        print(json.dumps({"ok": False, "error": "decode_failed", "message": str(e)}))
        return 1

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_bytes(image_bytes)

    print(
        json.dumps(
            {
                "ok": True,
                "model": args.model,
                "output_path": str(out_path),
                "bytes": len(image_bytes),
                "text": text_out,
            }
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
