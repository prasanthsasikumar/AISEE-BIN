#!/usr/bin/env python3
"""Render the fixed phrases both apps speak into recorded clips.

    python3 voice/generate.py          # render new or changed phrases
    python3 voice/generate.py --all    # render every phrase again
    python3 voice/generate.py --check  # no network: every phrase is still in the app sources

The phrases are in voice/phrases.json. Each becomes voice/clips/<slug>.mp3, and
voice/clips/index.json maps the phrase (normalised as below) to its file. The
iOS app bundles voice/clips as a folder and Android packs it into its assets.
When an app is about to speak text that matches a clip, it plays the clip;
anything else (place names, distances) still goes to the system voice.

The ElevenLabs key is read from ~/.config/aiseebin/elevenlabs_key, never the repo.
"""
import hashlib
import json
import pathlib
import re
import sys
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent
REPO = ROOT.parent
CLIPS = ROOT / "clips"
KEY_FILE = pathlib.Path.home() / ".config/aiseebin/elevenlabs_key"
SOURCES = [REPO / "AISEEBIN", REPO / "android/app/src/main/java"]


def normalise(text: str) -> str:
    """Must match VoiceClips.normalise in Swift and Kotlin."""
    text = text.replace("’", "'").lower()
    return " ".join(text.split())


def slug(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", normalise(text).replace("'", "")).strip("-")


def text_hash(text: str, voice: str, model: str) -> str:
    return hashlib.sha256(f"{voice}|{model}|{text}".encode()).hexdigest()[:16]


def render(text: str, voice: str, model: str, key: str) -> bytes:
    body = json.dumps({
        "text": text,
        "model_id": model,
        "voice_settings": {"stability": 0.6, "similarity_boost": 0.75},
    }).encode()
    req = urllib.request.Request(
        f"https://api.elevenlabs.io/v1/text-to-speech/{voice}?output_format=mp3_44100_128",
        data=body,
        headers={"xi-api-key": key, "Content-Type": "application/json", "Accept": "audio/mpeg"},
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        return resp.read()


def check(phrases) -> int:
    corpus = "".join(p.read_text(errors="ignore")
                     for d in SOURCES for p in d.rglob("*") if p.suffix in (".swift", ".kt"))
    missing = [t for t in phrases if t not in corpus]
    for t in missing:
        print(f"not in the app sources any more: {t!r}")
    print(f"{len(phrases) - len(missing)}/{len(phrases)} phrases found in the sources")
    return 1 if missing else 0


def main() -> int:
    spec = json.loads((ROOT / "phrases.json").read_text())
    voice, model, phrases = spec["voice"], spec["model"], spec["phrases"]
    if "--check" in sys.argv:
        return check(phrases)

    key = KEY_FILE.read_text().strip()
    CLIPS.mkdir(exist_ok=True)
    index_path = CLIPS / "index.json"
    old = json.loads(index_path.read_text())["clips"] if index_path.exists() else {}
    clips = {}
    for text in phrases:
        name, h = slug(text) + ".mp3", text_hash(text, voice, model)
        prev = old.get(normalise(text))
        if "--all" not in sys.argv and prev and prev["hash"] == h and (CLIPS / name).exists():
            clips[normalise(text)] = prev
            continue
        print(f"rendering {name}")
        (CLIPS / name).write_bytes(render(text, voice, model, key))
        clips[normalise(text)] = {"file": name, "hash": h}

    keep = {c["file"] for c in clips.values()} | {"index.json"}
    for f in CLIPS.iterdir():
        if f.name not in keep:
            print(f"removing {f.name}")
            f.unlink()
    index_path.write_text(json.dumps({"voice": voice, "model": model, "clips": clips}, indent=1) + "\n")
    print(f"{len(clips)} clips in {CLIPS.relative_to(REPO)}")
    return check(phrases)


if __name__ == "__main__":
    sys.exit(main())
