#!/usr/bin/env python3
"""
Deploy (or validate) the semantic view from its YAML file in this repo.

The YAML file is the source of truth. This script reads it and calls
SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML, which is the same thing the notebook in
segment 8 does after fetching the file from the git repository stage - the only
difference is where the bytes come from.

Usage:
    # validate without creating anything
    .venv-ml/bin/python tools/deploy_semantic_view.py --verify-only

    # create (or replace, preserving grants) the semantic view
    .venv-ml/bin/python tools/deploy_semantic_view.py

    # deploy into a different schema, e.g. to prove the file is portable
    .venv-ml/bin/python tools/deploy_semantic_view.py --schema DEMO.GUARDANT_GITOPS

Requires the .venv-ml environment (see demo/README or the runbook) and a
connection named in ~/.snowflake/connections.toml.
"""

from __future__ import annotations

import argparse
import pathlib
import sys

from snowflake.snowpark import Session

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
DEFAULT_YAML = REPO_ROOT / "semantic" / "sv_guardant_variants.yaml"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--connection", default="Demo_Account",
                        help="connections.toml profile name")
    parser.add_argument("--role", default="ACCOUNTADMIN",
                        help="role to deploy as; needs CREATE SEMANTIC VIEW on the schema")
    parser.add_argument("--schema", default="DEMO.GUARDANT_DEMO",
                        help="fully qualified target schema")
    parser.add_argument("--yaml", type=pathlib.Path, default=DEFAULT_YAML,
                        help="path to the semantic view YAML")
    parser.add_argument("--verify-only", action="store_true",
                        help="validate the spec without creating the object")
    args = parser.parse_args()

    if not args.yaml.is_file():
        print(f"ERROR: no YAML at {args.yaml}", file=sys.stderr)
        return 1

    spec = args.yaml.read_text()

    session = Session.builder.config("connection_name", args.connection).create()
    try:
        # The tool/driver may not carry the role we need, so set it explicitly.
        session.sql(f"USE ROLE {args.role}").collect()

        # Bind the spec as a parameter rather than interpolating it: the YAML
        # contains quotes and newlines, and string-building it into the SQL is
        # how you get a syntax error at 11:04 on a Thursday.
        result = session.sql(
            "CALL SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML(?, ?, ?)",
            params=[args.schema, spec, args.verify_only],
        ).collect()

        print(result[0][0])
        return 0
    except Exception as exc:  # surface the server message, it is the useful part
        print(f"FAILED: {exc}", file=sys.stderr)
        return 1
    finally:
        session.close()


if __name__ == "__main__":
    sys.exit(main())
