#!/usr/bin/env python3
"""
Verify every SQL cell in the notebooks actually executes against the demo
account, and report which ones fail.

This exists because a notebook that only *looks* right is worthless in front of
a customer. Run it after any edit to build_notebooks.py.

Usage:
    python tools/verify_sql_cells.py [notebook.ipynb ...]

Defaults to all notebooks in ../notebooks/. Uses the `snow` CLI so it picks up
the same connection profile you demo with.
"""

from __future__ import annotations

import json
import pathlib
import subprocess
import sys
import tempfile

CONNECTION = "Demo_Account"
ROLE = "ACCOUNTADMIN"
PREAMBLE = "USE WAREHOUSE GUARDANT_DEMO_WH;\nUSE SCHEMA DEMO.GUARDANT_DEMO;\n"

NOTEBOOK_DIR = pathlib.Path(__file__).resolve().parent.parent / "notebooks"


def sql_cells(path: pathlib.Path):
    nb = json.loads(path.read_text())
    for cell in nb["cells"]:
        if cell.get("metadata", {}).get("language") == "sql":
            yield cell["metadata"]["name"], cell["source"]


def run(sql_text: str) -> tuple[bool, str]:
    with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False) as fh:
        fh.write(PREAMBLE + sql_text.rstrip().rstrip(";") + ";\n")
        tmp = fh.name
    proc = subprocess.run(
        ["snow", "sql", "-c", CONNECTION, "--role", ROLE, "-f", tmp],
        capture_output=True,
        text=True,
        timeout=900,
    )
    pathlib.Path(tmp).unlink(missing_ok=True)
    combined = proc.stdout + proc.stderr
    ok = proc.returncode == 0 and "Error" not in combined
    return ok, combined


def main() -> int:
    paths = (
        [pathlib.Path(a) for a in sys.argv[1:]]
        if len(sys.argv) > 1
        else sorted(NOTEBOOK_DIR.glob("*.ipynb"))
    )

    failures = []
    for path in paths:
        print(f"\n=== {path.name} ===")
        for name, sql_text in sql_cells(path):
            ok, output = run(sql_text)
            print(f"  [{'PASS' if ok else 'FAIL'}] {name}")
            if not ok:
                failures.append((path.name, name, output[-1500:]))

    if failures:
        print(f"\n{'=' * 60}\n{len(failures)} FAILING CELL(S)\n{'=' * 60}")
        for nb, name, output in failures:
            print(f"\n--- {nb} :: {name} ---\n{output}")
        return 1

    print("\nAll SQL cells executed successfully.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
