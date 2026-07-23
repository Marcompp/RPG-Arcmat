"""Formatting lint for Database/*.json.

Canonicalizes every JSON file under Database/ to tab-indented, ensure_ascii=False
formatting so files are consistently readable regardless of which tool wrote them.

Usage:
    python tools/lint_json.py          # check mode: report non-canonical files, exit 1 if any
    python tools/lint_json.py --fix    # rewrite non-canonical files in place
"""

import json
import sys
from pathlib import Path

DATABASE_DIR = Path(__file__).resolve().parent.parent / "Database"


def canonicalize(data: object) -> str:
    return json.dumps(data, indent="\t", ensure_ascii=False) + "\n"


def main() -> int:
    fix = "--fix" in sys.argv

    non_canonical = []
    for path in sorted(DATABASE_DIR.rglob("*.json")):
        raw = path.read_bytes()
        has_bom = raw.startswith(b"\xef\xbb\xbf")
        original = raw.decode("utf-8-sig")
        data = json.loads(original)
        canonical = canonicalize(data)

        if has_bom or original != canonical:
            non_canonical.append(path)
            if fix:
                path.write_bytes(canonical.encode("utf-8"))

    if not non_canonical:
        print("All JSON files are canonically formatted.")
        return 0

    verb = "Reformatted" if fix else "Non-canonical formatting:"
    print(verb)
    for path in non_canonical:
        print(f"  {path.relative_to(DATABASE_DIR.parent)}")

    if fix:
        return 0

    print(f"\n{len(non_canonical)} file(s) need formatting. Run with --fix to rewrite them.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
