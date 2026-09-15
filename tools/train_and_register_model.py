#!/usr/bin/env python3
"""
Segment 5 - train a model on your laptop, then put it in the Snowflake Model
Registry so it can be scored server-side.

What it does:
  1. Pulls a 50k-row training sample out of Snowflake (small on purpose - this is
     the "I work locally" starting point, not a scale demo)
  2. Trains a scikit-learn classifier predicting whether a variant call is
     PATHOGENIC, from VAF, depth, alt reads and mapping quality
  3. Logs it to the Model Registry, so it can be called from SQL
  4. Writes the same model to model/variant_clf.joblib for segment 8, where it
     gets committed to git and loaded back in from the repo

Usage:
    .venv-ml/bin/python tools/train_and_register_model.py

VERSION PINNING MATTERS HERE. snowflake-ml-python 1.9.2 requires scikit-learn
<1.6, and the model gets unpickled inside Snowflake in segment 8. We pin 1.5.2
because Snowflake's Anaconda channel also has 1.5.2 - so the version that writes
the pickle and the version that reads it are the same. Change this pin and
segment 8 is where you will find out.
"""

from __future__ import annotations

import pathlib
import sys

import joblib
import pandas as pd
import sklearn
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import roc_auc_score
from sklearn.model_selection import train_test_split

from snowflake.ml.registry import Registry
from snowflake.snowpark import Session

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
MODEL_PATH = REPO_ROOT / "model" / "variant_clf.joblib"

CONNECTION = "Demo_Account"
ROLE = "ACCOUNTADMIN"
DATABASE = "DEMO"
SCHEMA = "GUARDANT_DEMO"
WAREHOUSE = "GUARDANT_DEMO_WH"
MODEL_NAME = "GUARDANT_VARIANT_CLF"

# WHY THIS TARGET AND NOT "is the call reportable":
# call_filter is derived by the data generator from exactly these four columns
# (mapping quality, depth, VAF, alt reads), so predicting it scores a perfect
# AUC of 1.0 - the model just relearns the threshold rule. That invites an
# obvious and correct leakage question from anyone in the room who does this for
# a living. Pathogenicity also depends on the gene's actionability and the
# predicted consequence, neither of which is a feature here, so there is genuine
# irreducible error and the AUC is believable.
#
# Be honest in the room anyway: this is synthetic data, so any model is learning
# the generator. The point of the segment is the registry and server-side
# scoring mechanics, not model quality.
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
    if not sklearn.__version__.startswith("1.5."):
        print("WARNING: expected scikit-learn 1.5.x to match Snowflake's channel.",
              file=sys.stderr)

    session = Session.builder.config("connection_name", CONNECTION).create()
    try:
        session.sql(f"USE ROLE {ROLE}").collect()
        session.sql(f"USE WAREHOUSE {WAREHOUSE}").collect()
        session.sql(f"USE SCHEMA {DATABASE}.{SCHEMA}").collect()

        # --- 1. the local starting point -----------------------------------
        print("Pulling a 50k training sample down to the laptop...")
        df: pd.DataFrame = session.sql(TRAINING_SAMPLE_SQL).to_pandas()
        print(f"  {len(df):,} rows, {df[TARGET].mean():.1%} pathogenic")

        X_train, X_test, y_train, y_test = train_test_split(
            df[FEATURES], df[TARGET], test_size=0.25, random_state=42, stratify=df[TARGET]
        )

        # --- 2. train ------------------------------------------------------
        # Deliberately small: this model gets committed to git in segment 8, and
        # a fat forest would bloat the repo. 40 shallow trees keeps the
        # serialized file well under a megabyte and still scores cleanly.
        #
        # class_weight="balanced" is not cosmetic. Pathogenic calls are ~8% of
        # the data, and without it the forest never crosses the 0.5 threshold:
        # PREDICT returns 0 for all 11.8M rows and the demo shows a column of
        # zeros at 92% "accuracy", which is just the base rate. Balancing makes
        # the predictions actually vary, which is the whole point of showing them.
        clf = RandomForestClassifier(
            n_estimators=40, max_depth=8, min_samples_leaf=50,
            class_weight="balanced",
            random_state=42, n_jobs=-1,
        )
        clf.fit(X_train, y_train)

        auc = roc_auc_score(y_test, clf.predict_proba(X_test)[:, 1])
        pred_rate = clf.predict(X_test).mean()
        print(f"  holdout ROC AUC: {auc:.4f}")
        print(f"  predicted-positive rate: {pred_rate:.1%} (base rate {y_test.mean():.1%})")
        if pred_rate == 0 or pred_rate == 1:
            print("WARNING: the model predicts a single class. Do not demo this.",
                  file=sys.stderr)

        # --- 3. log to the registry ----------------------------------------
        # Drop first. log_model() with an existing version_name fails with a
        # collision, and if you are filtering the noisy progress bars out of the
        # output you will not see the error - you will just carry on believing
        # the new model is registered while the old one is still serving.
        print("Replacing any existing model...")
        session.sql(f"DROP MODEL IF EXISTS {DATABASE}.{SCHEMA}.{MODEL_NAME}").collect()

        print("Logging to the Model Registry...")
        registry = Registry(session=session, database_name=DATABASE, schema_name=SCHEMA)

        mv = registry.log_model(
            model=clf,
            model_name=MODEL_NAME,
            version_name="V1",
            sample_input_data=X_train.head(100),
            comment=f"Pathogenicity classifier over reportable calls. sklearn {sklearn.__version__}, holdout AUC {auc:.4f}.",
            options={"relax_version": False},
        )
        print(f"  registered {DATABASE}.{SCHEMA}.{MODEL_NAME} version V1")

        # --- 4. write the file for segment 8 --------------------------------
        MODEL_PATH.parent.mkdir(parents=True, exist_ok=True)
        joblib.dump(clf, MODEL_PATH, compress=3)
        size_kb = MODEL_PATH.stat().st_size / 1024
        print(f"  wrote {MODEL_PATH.relative_to(REPO_ROOT)} ({size_kb:.0f} KB)")
        if size_kb > 1024:
            print("WARNING: model file is over 1 MB. Reduce n_estimators or max_depth "
                  "before committing it.", file=sys.stderr)

        print("\nNow score it server-side. In SQL:")
        print(f"  SELECT {MODEL_NAME}!PREDICT(VAF, READ_DEPTH, ALT_READ_COUNT, MAPPING_QUALITY)")
        print(f"  FROM {DATABASE}.{SCHEMA}.VARIANT_CALLS LIMIT 5;")
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
