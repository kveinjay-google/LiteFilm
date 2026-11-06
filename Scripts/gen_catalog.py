#!/usr/bin/env python3
"""Rebuild SpektraFilm/Resources/FilmCatalog.json from the vendored profiles."""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ENGINE = ROOT / "vendor" / "SpektraLab" / "engine"


def info_of(path: Path) -> tuple[dict, dict]:
    data = json.loads(path.read_text())
    return data, data.get("info") or {}


def main() -> None:
    bases = {}
    for path in (ENGINE / "resources" / "profiles").glob("*.json"):
        _, info = info_of(path)
        bases[path.stem] = info

    films: list[dict] = []
    papers: list[dict] = []

    def add(path: Path, origin: str) -> None:
        data, info = info_of(path)
        stage = info.get("stage")
        support = info.get("support")
        derived = data.get("derived_from")
        target = info.get("target_print")
        if not target and derived and derived in bases:
            target = bases[derived].get("target_print")
        channel = info.get("channel_model")
        if not channel and derived:
            channel = (bases.get(derived) or {}).get("channel_model")
        kind = "paper" if stage == "printing" or support == "paper" else (info.get("type") or "negative")
        row = {
            "id": path.stem,
            "name": info.get("name") or path.stem,
            "kind": kind,
            "channel": channel or "color",
            "targetPrint": target,
            "origin": origin,
        }
        (papers if kind == "paper" else films).append(row)

    for path in sorted((ENGINE / "resources" / "profiles").glob("*.json")):
        add(path, "spektrafilm")
    for path in sorted((ENGINE / "resources_product" / "profiles").glob("*.json")):
        add(path, "spektralab")
    films.sort(key=lambda row: row["name"])
    papers.sort(key=lambda row: row["name"])
    dest = ROOT / "SpektraFilm" / "Resources" / "FilmCatalog.json"
    dest.write_text(json.dumps({"films": films, "papers": papers}, ensure_ascii=False, indent=2) + "\n")
    print(f"{dest} films={len(films)} papers={len(papers)}")


if __name__ == "__main__":
    main()
