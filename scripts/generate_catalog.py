#!/usr/bin/env python3
import json
import sys
from pathlib import Path

if len(sys.argv) != 3:
    raise SystemExit("usage: generate_catalog.py SOURCE_JSON OUTPUT_JSON")

source = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
seen = set()
catalog = []

if isinstance(source, list):
    entries = []
    for value in source:
        if not isinstance(value, dict):
            continue
        entries.append((value.get("name") or "", value))
        for alias in value.get("aliases") or []:
            alias_value = dict(value)
            alias_value["name"] = alias
            entries.append((alias, alias_value))
else:
    entries = list(source.items())

for key, value in entries:
    name = (value.get("name") or key or "").strip()
    client_id = str(value.get("client_id") or value.get("id") or "").strip()
    if not name or not client_id or not client_id.isdigit():
        continue
    identity = (name.casefold(), client_id)
    if identity in seen:
        continue
    seen.add(identity)
    executable_path = str(value.get("executable_path") or "").strip() or None
    if not executable_path:
        windows_executables = [
            item.get("name") for item in (value.get("executables") or [])
            if item.get("os") == "win32" and item.get("name")
        ]
        executable_path = windows_executables[0] if windows_executables else None
    catalog.append({"name": name, "clientID": client_id, "executablePath": executable_path})

catalog.sort(key=lambda item: item["name"].casefold())
Path(sys.argv[2]).write_text(
    json.dumps(catalog, ensure_ascii=False, separators=(",", ":")),
    encoding="utf-8",
)
print(f"Wrote {len(catalog)} Discord game profiles")
