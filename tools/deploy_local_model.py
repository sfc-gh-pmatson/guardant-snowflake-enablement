#!/usr/bin/env python3
"""
Deploy a model from your laptop into the Snowflake Model Registry as a NEW
VERSION of an existing model.

This is the generic version of the Part 5 story. train_and_register_model.py
trains and registers in one go and REPLACES the model; this script takes a
.joblib that already exists on disk and adds it as another version, which is
what you actually want when demonstrating a handoff or a model update.

    # add a local model file as version V2
    .venv-ml/bin/python tools/deploy_local_model.py \
        --model-file model/variant_clf_gb.joblib --version V2

    # check what is already registered without changing anything
    .venv-ml/bin/python tools/deploy_local_model.py --list

    # deploy a model that lives on the git repository stage instead of locally
    #   (Snowflake fetches it; nothing is uploaded from the laptop)
    .venv-ml/bin/python tools/deploy_local_model.py \
        --from-stage '@DEMO.GUARDANT_DEMO.GUARDANT_ENABLEMENT_REPO/branches/main/model/variant_clf.joblib' \
        --version V3

WHY THE VERSION PIN MATTERS
joblib.load needs a compatible scikit-learn between the process that wrote the
pickle and the process that reads it. This environment pins 1.5.2 because
snowflake-ml-python 1.9.2 requires <1.6 AND Snowflake's Anaconda channel carries
1.5.2 - so the writer and the reader agree. The script asserts this rather than
letting a mismatch surface as a confusing inference error later.
"""

from __future__ import annotations

import argparse
import pathlib
import sys
import tempfile

import joblib
import sklearn

from snowflake.ml.registry import Registry
from snowflake.snowpark import Session

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent

CONNECTION = "Demo_Account"
ROLE = "ACCOUNTADMIN"
DATABASE = "DEMO"
SCHEMA = "GUARDANT_DEMO"
WAREHOUSE = "GUARDANT_DEMO_WH"
MODEL_NAME = "GUARDANT_VARIANT_CLF"

# scikit-learn versions Snowflake's Anaconda channel carries below the 1.6 ceiling
# that snowflake-ml-python 1.9.2 imposes.
SUPPORTED_SKLEARN = ("1.5.2", "1.5.1")

FEATURES = ["VAF", "READ_DEPTH", "ALT_READ_COUNT", "MAPPING_QUALITY"]

SIGNATURE_SAMPLE_SQL = f"""
SELECT {", ".join(FEATURES)}
FROM {DATABASE}.{SCHEMA}.VARIANT_CALLS SAMPLE (200 ROWS)
WHERE CALL_FILTER = 'PASS'
LIMIT 100
"""


def check_sklearn() -> None:
    if sklearn.__version__ not in SUPPORTED_SKLEARN:
        print(
            f"ERROR: scikit-learn {sklearn.__version__} is installed locally, but "
            f"Snowflake's channel has {', '.join(SUPPORTED_SKLEARN)}.\n"
            "        Unpickling across incompatible versions can fail, or worse, "
            "silently misbehave.\n"
            f"        Reinstall with: uv pip install 'scikit-learn=={SUPPORTED_SKLEARN[0]}'",
            file=sys.stderr,
        )
        sys.exit(1)
    print(f"scikit-learn {sklearn.__version__} — matches Snowflake's channel")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    src = parser.add_mutually_exclusive_group()
    src.add_argument("--model-file", type=pathlib.Path,
                     help="local .joblib to deploy")
    src.add_argument("--from-stage",
                     help="stage path to a .joblib, e.g. a git repository stage")
    parser.add_argument("--version", default=None,
                        help="version name to create, e.g. V2")
    parser.add_argument("--comment", default=None)
    parser.add_argument("--model-name", default=MODEL_NAME)
    parser.add_argument("--list", action="store_true",
                        help="list registered versions and exit")
    args = parser.parse_args()

    session = Session.builder.config("connection_name", CONNECTION).create()
    try:
        session.sql(f"USE ROLE {ROLE}").collect()
        session.sql(f"USE WAREHOUSE {WAREHOUSE}").collect()
        session.sql(f"USE SCHEMA {DATABASE}.{SCHEMA}").collect()

        registry = Registry(session=session, database_name=DATABASE, schema_name=SCHEMA)

        # --- inspect only -------------------------------------------------
        if args.list:
            rows = session.sql(
                f"SHOW VERSIONS IN MODEL {DATABASE}.{SCHEMA}.{args.model_name}"
            ).collect()
            print(f"\n{args.model_name}: {len(rows)} version(s)")
            for r in rows:
                print(f"  {r['name']:<8} {r['comment'] or ''}")
            return 0

        if not args.model_file and not args.from_stage:
            parser.error("give --model-file, --from-stage, or --list")
        if not args.version:
            parser.error("--version is required when deploying")

        check_sklearn()

        # --- get the model object ------------------------------------------
        if args.from_stage:
            # Pull the file out of the stage into a temp dir. For a git
            # repository stage this is how you deploy an artifact that was
            # committed rather than one sitting on your laptop.
            print(f"Downloading {args.from_stage} ...")
            with tempfile.TemporaryDirectory() as tmp:
                session.file.get(args.from_stage, tmp)
                downloaded = list(pathlib.Path(tmp).glob("*.joblib"))
                if not downloaded:
                    print(f"ERROR: nothing matching *.joblib at {args.from_stage}",
                          file=sys.stderr)
                    return 1
                print(f"  got {downloaded[0].name} "
                      f"({downloaded[0].stat().st_size / 1024:.0f} KB)")
                clf = joblib.load(downloaded[0])
            source = args.from_stage
        else:
            if not args.model_file.is_file():
                print(f"ERROR: no file at {args.model_file}", file=sys.stderr)
                return 1
            size_kb = args.model_file.stat().st_size / 1024
            print(f"Loading {args.model_file} ({size_kb:.0f} KB)")
            clf = joblib.load(args.model_file)
            source = str(args.model_file)

        print(f"  loaded {type(clf).__name__}")

        # --- signature ------------------------------------------------------
        # The registry needs to know the input shape. Take it from the real
        # table rather than hand-writing a schema.
        sample = session.sql(SIGNATURE_SAMPLE_SQL).to_pandas()

        # --- register as a new version -------------------------------------
        # Note: no DROP here. This ADDS a version, which is the point.
        print(f"Registering as {args.model_name} version {args.version} ...")
        registry.log_model(
            model=clf,
            model_name=args.model_name,
            version_name=args.version,
            sample_input_data=sample,
            comment=args.comment or
                    f"{type(clf).__name__} deployed from {source}. sklearn {sklearn.__version__}.",
            options={"relax_version": False},
        )

        rows = session.sql(
            f"SHOW VERSIONS IN MODEL {DATABASE}.{SCHEMA}.{args.model_name}"
        ).collect()
        print(f"\n{args.model_name} now has {len(rows)} version(s): "
              f"{', '.join(r['name'] for r in rows)}")
        print("\nScore it server-side:")
        print(f"  USE SCHEMA {DATABASE}.{SCHEMA};")
        print(f"  SELECT {args.model_name}!PREDICT(vaf, read_depth, alt_read_count, mapping_quality)")
        print(f"  FROM {DATABASE}.{SCHEMA}.VARIANT_CALLS LIMIT 5;")
        print("Set the default version with:")
        print(f"  ALTER MODEL {DATABASE}.{SCHEMA}.{args.model_name} "
              f"SET DEFAULT_VERSION = {args.version};")
        return 0
    except Exception as exc:
        import traceback
        traceback.print_exc()
        print(f"FAILED: {exc}", file=sys.stderr)
        return 1
    finally:
        session.close()


if __name__ == "__main__":
    sys.exit(main())
