#!/usr/bin/env python3
"""
Train a SECOND model locally, and deliberately do NOT commit it.

Purpose: Part 5 of the session needs two distinct paths shown.

  Path A (committed)   model/variant_clf.joblib is in git. Snowflake can see it
                       on the git repository stage. That demonstrates git as the
                       handoff boundary between training and deployment.

  Path B (local only)  THIS model never enters git. It goes straight from the
                       laptop into the Model Registry as a new version. That is
                       the everyday path a data scientist actually uses, and it
                       is the honest contrast: the registry is the artifact
                       store, git is for the code and the definitions.

The output path is in .gitignore. If you find yourself needing to commit it,
something has gone wrong with the story.

A different algorithm from V1 on purpose - V1 is a RandomForest. Gradient
boosting gives a visibly different model in the registry rather than a
near-identical twin, which makes the versioning point land.

Usage:
    .venv-ml/bin/python tools/train_second_model.py
    .venv-ml/bin/python tools/deploy_local_model.py \
        --model-file model/variant_clf_gb_local.joblib --version V2
"""

from __future__ import annotations

import pathlib
import sys

import joblib
import pandas as pd
import sklearn
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.metrics import roc_auc_score
from sklearn.model_selection import train_test_split

from snowflake.snowpark import Session

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
# NOTE the _local suffix: .gitignore matches model/*_local.joblib
MODEL_PATH = REPO_ROOT / "model" / "variant_clf_gb_local.joblib"

CONNECTION = "Demo_Account"
ROLE = "ACCOUNTADMIN"
DATABASE = "DEMO"
SCHEMA = "GUARDANT_DEMO"
WAREHOUSE = "GUARDANT_DEMO_WH"

FEATURES = ["VAF", "READ_DEPTH", "ALT_READ_COUNT", "MAPPING_QUALITY"]
TARGET = "IS_PATHOGENIC"

TRAINING_SAMPLE_SQL = f"""
SELECT VAF, READ_DEPTH, ALT_READ_COUNT, MAPPING_QUALITY,
       IFF(CLINICAL_SIGNIFICANCE = 'Pathogenic', 1, 0) AS IS_PATHOGENIC
FROM {DATABASE}.{SCHEMA}.VARIANT_CALLS SAMPLE (80000 ROWS)
WHERE CALL_FILTER = 'PASS'
LIMIT 50000
"""


def main() -> int:
    print(f"scikit-learn {sklearn.__version__}  joblib {joblib.__version__}")

    session = Session.builder.config("connection_name", CONNECTION).create()
    try:
        session.sql(f"USE ROLE {ROLE}").collect()
        session.sql(f"USE WAREHOUSE {WAREHOUSE}").collect()
        session.sql(f"USE SCHEMA {DATABASE}.{SCHEMA}").collect()

        print("Pulling a 50k training sample down to the laptop...")
        df: pd.DataFrame = session.sql(TRAINING_SAMPLE_SQL).to_pandas()
        print(f"  {len(df):,} rows, {df[TARGET].mean():.1%} pathogenic")

        X_train, X_test, y_train, y_test = train_test_split(
            df[FEATURES], df[TARGET], test_size=0.25, random_state=7,
            stratify=df[TARGET],
        )

        # class_weight="balanced" for the same reason as V1: with ~8% positives an
        # unweighted model never crosses the 0.5 threshold and PREDICT returns a
        # column of zeros for every row, which looks broken on screen.
        clf = HistGradientBoostingClassifier(
            max_iter=120, max_depth=6, learning_rate=0.1,
            min_samples_leaf=50, class_weight="balanced", random_state=7,
        )
        clf.fit(X_train, y_train)

        auc = roc_auc_score(y_test, clf.predict_proba(X_test)[:, 1])
        pred_rate = clf.predict(X_test).mean()
        print(f"  holdout ROC AUC: {auc:.4f}")
        print(f"  predicted-positive rate: {pred_rate:.1%} (base rate {y_test.mean():.1%})")
        if pred_rate in (0.0, 1.0):
            print("WARNING: the model predicts a single class. Do not demo this.",
                  file=sys.stderr)

        MODEL_PATH.parent.mkdir(parents=True, exist_ok=True)
        joblib.dump(clf, MODEL_PATH, compress=3)
        size_kb = MODEL_PATH.stat().st_size / 1024
        print(f"  wrote {MODEL_PATH.relative_to(REPO_ROOT)} ({size_kb:.0f} KB)")
        print("\nThis file is gitignored on purpose. Deploy it with:")
        print(f"  .venv-ml/bin/python tools/deploy_local_model.py \\")
        print(f"      --model-file {MODEL_PATH.relative_to(REPO_ROOT)} --version V2")
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
