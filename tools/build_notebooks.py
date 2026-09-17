#!/usr/bin/env python3
"""
Build the Snowflake Notebook (.ipynb) files for the Guardant enablement session.

The notebooks are generated rather than hand-edited so that cell content stays
reviewable as plain text in this file, and so a bad merge in a .ipynb JSON blob
can always be fixed by regenerating.

Usage:
    python tools/build_notebooks.py

Writes into ../notebooks/ relative to this file.
"""

from __future__ import annotations

import json
import pathlib

NOTEBOOK_DIR = pathlib.Path(__file__).resolve().parent.parent / "notebooks"


def md(name: str, text: str) -> dict:
    return {
        "cell_type": "markdown",
        "id": name,
        "metadata": {"name": name, "collapsed": False},
        "source": text,
    }


def sql(name: str, text: str) -> dict:
    return {
        "cell_type": "code",
        "execution_count": None,
        "id": name,
        "metadata": {"language": "sql", "name": name, "collapsed": False},
        "outputs": [],
        "source": text,
    }


def py(name: str, text: str) -> dict:
    return {
        "cell_type": "code",
        "execution_count": None,
        "id": name,
        "metadata": {"language": "python", "name": name, "collapsed": False},
        "outputs": [],
        "source": text,
    }


def notebook(cells: list[dict]) -> dict:
    return {
        "cells": cells,
        "metadata": {
            "kernelspec": {"display_name": "Streamlit Notebook", "name": "streamlit"},
        },
        "nbformat": 4,
        "nbformat_minor": 5,
    }


# ===========================================================================
# Notebook 1 — Snowflake Notebooks
# ===========================================================================

NB1 = notebook([
    md("md_intro", """# 1 — Snowflake Notebooks
## "Your Jupyter, but in Snowflake"

This is the same notebook interface you already use. The difference is *where the work happens*.

Today the workflow is:

> query Snowflake &rarr; **download the result** &rarr; process it in pandas on a laptop &rarr; write results back

That download step is the bottleneck. It caps you at local RAM, it means every teammate needs an identical Python environment, and it puts patient-adjacent data onto endpoints.

Here the download step is gone. SQL and Python cells sit side by side, both executing on Snowflake compute, against data that never leaves the account.

**Dataset:** synthetic liquid-biopsy cohort — 50,000 patients, 120,000 blood draws, **20,000,000 raw variant calls**. None of it is real patient data."""),

    md("md_ctx", """### Set the context

No `pip install`, no conda environment, no credentials file. The notebook already knows who you are and what you are allowed to see."""),

    sql("sql_ctx", """USE WAREHOUSE GUARDANT_DEMO_WH;
USE SCHEMA DEMO.GUARDANT_DEMO;

SELECT CURRENT_USER()      AS whoami,
       CURRENT_ROLE()      AS acting_as,
       CURRENT_WAREHOUSE() AS compute,
       CURRENT_SCHEMA()    AS working_in;"""),

    md("md_scale", """### How big is the table?

This is the number that matters. 20 million raw calls is one modest cohort, and it is already past the point where `pd.read_sql(...)` on a laptop is a good idea."""),

    sql("sql_scale", """SELECT COUNT(*)                                         AS raw_variant_calls,
       COUNT(DISTINCT specimen_id)                      AS specimens,
       COUNT(DISTINCT gene_symbol)                      AS genes_on_panel,
       ROUND(COUNT(*) / COUNT(DISTINCT specimen_id), 1) AS avg_calls_per_specimen
FROM VARIANT_CALLS;"""),

    md("md_filter", """### The filtering step you run every day

Raw calls include the noise floor: low mapping quality, shallow depth, sub-threshold VAF. Filtering it out is the first thing any variant analysis does.

On a laptop that means pulling all 20M rows down and *then* discarding most of them. Here the filter runs where the data already lives, and only the summary comes back."""),

    sql("sql_filter", """SELECT call_filter,
       COUNT(*)                                           AS calls,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_total
FROM VARIANT_CALLS
GROUP BY call_filter
ORDER BY calls DESC;"""),

    md("md_handoff", """### Hand a SQL result straight to Python

This is the part that tends to surprise people. Any SQL cell is addressable from Python **by its cell name** — `sql_gene_burden.to_pandas()`. No connector, no cursor, no credentials.

The aggregation ran on Snowflake across 20M rows. What crosses into Python is 15 rows."""),

    sql("sql_gene_burden", """SELECT gene_symbol,
       COUNT(*)                    AS reportable_calls,
       COUNT(DISTINCT specimen_id) AS specimens_affected,
       ROUND(MEDIAN(vaf) * 100, 3) AS median_vaf_pct,
       ROUND(AVG(read_depth))      AS mean_depth,
       MAX(is_actionable)          AS has_targeted_therapy
FROM V_REPORTABLE_VARIANTS
GROUP BY gene_symbol
ORDER BY reportable_calls DESC
LIMIT 15;"""),

    py("py_handoff", """# The SQL cell above is available here by name. One method call.
df = sql_gene_burden.to_pandas()

print(f"Rows that crossed into Python: {len(df):,}")
print(f"Rows scanned on Snowflake:     20,000,000")
df"""),

    md("md_viz", """### Plot it with the libraries you already use

matplotlib, seaborn, plotly, scipy, scikit-learn — all available from the packages picker. Charts render inline."""),

    py("py_viz", """import matplotlib.pyplot as plt

plot_df = df.sort_values("REPORTABLE_CALLS")
colors = ["#29B5E8" if a else "#B0BEC5" for a in plot_df["HAS_TARGETED_THERAPY"]]

fig, ax = plt.subplots(figsize=(9, 6))
ax.barh(plot_df["GENE_SYMBOL"], plot_df["REPORTABLE_CALLS"], color=colors)
ax.set_xlabel("Reportable variant calls")
ax.set_title("Mutation burden by gene\\n(blue = targeted therapy available)")
ax.spines[["top", "right"]].set_visible(False)
plt.tight_layout()
plt.show()"""),

    md("md_python_first", """### Or skip SQL entirely and stay in Python

If you would rather express the whole thing as a DataFrame, you can. `session.table(...)` returns a **lazy** Snowpark DataFrame: the operations below assemble a query, and nothing executes until you ask for a result.

That laziness is the bridge into notebook 2."""),

    py("py_snowpark_peek", """from snowflake.snowpark.context import get_active_session
import snowflake.snowpark.functions as F

session = get_active_session()

variants = session.table("V_REPORTABLE_VARIANTS")

# Nothing has executed yet — this is a query being assembled, not data being moved.
actionable_by_cancer = (
    variants
    .filter(F.col("IS_ACTIONABLE") & (F.col("VAF") >= 0.05))
    .group_by("PRIMARY_CANCER_TYPE")
    .agg(
        F.count_distinct("PATIENT_ID").alias("PATIENTS_WITH_ACTIONABLE"),
        F.count("*").alias("ACTIONABLE_CALLS"),
    )
    .sort(F.col("PATIENTS_WITH_ACTIONABLE").desc())
)

actionable_by_cancer.show(10)"""),

    md("md_close", """---

### What changed

| | Today | Here |
|---|---|---|
| Where compute runs | Your laptop | Snowflake |
| Data movement | Full extract, every time | Results only |
| Environment setup | Per person, per machine | None |
| Ceiling | Local RAM | Warehouse size |
| Governance | Data on endpoints | Never leaves the account |

Next: **notebook 2** takes the same data to a scale with no laptop equivalent."""),
])


# ===========================================================================
# Notebook 2 — Snowpark
# ===========================================================================

NB2 = notebook([
    md("md_intro", """# 2 — Snowpark
## "Python DataFrames at Snowflake scale"

Snowpark is a DataFrame API that looks like pandas and executes like a database.

The critical difference: a Snowpark DataFrame is **lazy**. It holds a query, not data. Nothing moves until you call `.show()`, `.to_pandas()`, or `.collect()` — and when you do, only the result comes back.

That single property is what removes the memory ceiling."""),

    sql("sql_ctx", """USE WAREHOUSE GUARDANT_DEMO_WH;
USE SCHEMA DEMO.GUARDANT_DEMO;"""),

    md("md_session", """### The session

Inside a Snowflake Notebook there is nothing to authenticate. `get_active_session()` hands you the session the notebook is already running in."""),

    py("py_session", """from snowflake.snowpark.context import get_active_session
import snowflake.snowpark.functions as F
from snowflake.snowpark.window import Window

session = get_active_session()

variants  = session.table("VARIANT_CALLS")
specimens = session.table("SPECIMENS")
patients  = session.table("PATIENTS")
panel     = session.table("GENE_PANEL")

# Project the panel with a distinct join key. Joining two DataFrames that both
# carry GENE_SYMBOL leaves that name ambiguous downstream, so rename it once
# here rather than disambiguating at every later reference.
panel_lookup = panel.select(
    F.col("GENE_SYMBOL").alias("PANEL_GENE"),
    "IS_ACTIONABLE",
    "TARGETED_THERAPY",
)

print(f"VARIANT_CALLS rows: {variants.count():,}")"""),

    md("md_lazy", """### Proof that it is lazy

Build a multi-stage pipeline — filter, join, aggregate, window — and then look at what Snowpark actually produced. It is SQL. No rows have moved."""),

    py("py_lazy", """pipeline = (
    variants
    .filter(F.col("CALL_FILTER") == "PASS")
    .join(specimens, on="SPECIMEN_ID")
    .filter(F.col("QC_STATUS") == "PASS")
    .group_by("GENE_SYMBOL", "ASSAY")
    .agg(F.count("*").alias("N_CALLS"))
)

# The DataFrame is a query. Here it is.
print(pipeline.queries["queries"][0][:900])"""),

    md("md_scale_agg", """### An aggregation across 20M rows

Per-gene statistics over the full raw table, no pre-filtering. On a laptop this requires the extract first. Here it is one expression, and the result is small enough to hand straight to pandas."""),

    py("py_scale_agg", """import time

gene_stats = (
    variants
    .join(panel_lookup, variants["GENE_SYMBOL"] == panel_lookup["PANEL_GENE"])
    .group_by("GENE_SYMBOL", "IS_ACTIONABLE")
    .agg(
        F.count("*").alias("TOTAL_CALLS"),
        F.sum(F.iff(F.col("CALL_FILTER") == "PASS", 1, 0)).alias("PASS_CALLS"),
        F.count_distinct("SPECIMEN_ID").alias("SPECIMENS"),
        F.round(F.median("VAF") * 100, 3).alias("MEDIAN_VAF_PCT"),
        F.round(F.max("VAF") * 100, 2).alias("MAX_VAF_PCT"),
        F.round(F.avg("READ_DEPTH")).alias("MEAN_DEPTH"),
    )
    .sort(F.col("TOTAL_CALLS").desc())
)

t0 = time.time()
result = gene_stats.to_pandas()
elapsed = time.time() - t0

print(f"Aggregated 20,000,000 rows in {elapsed:.1f}s")
print(f"Returned {len(result)} rows to Python\\n")
result.head(12)"""),

    md("md_window", """### Window functions: longitudinal VAF tracking

The clinically interesting question is not "what is the VAF" — it is "is the VAF rising across serial draws". That is a window function over each patient's draw history.

This is precisely the kind of operation that gets painful in pandas at scale, because it needs the whole partition in memory at once. Snowflake does it in the warehouse."""),

    py("py_window", """# Per patient / gene, track the clonal variant across successive draws.
clonal = (
    variants
    .filter((F.col("CALL_FILTER") == "PASS") & (F.col("VAF") >= 0.02))
    .join(specimens, on="SPECIMEN_ID")
    .filter(F.col("QC_STATUS") == "PASS")
    .select("PATIENT_ID", "SPECIMEN_ID", "GENE_SYMBOL",
            "COLLECTION_DATE", "DRAW_NUMBER", "VAF", "TUMOR_FRACTION")
)

w = Window.partition_by("PATIENT_ID", "GENE_SYMBOL").order_by("COLLECTION_DATE")

trajectory = (
    clonal
    .with_column("PREV_VAF", F.lag("VAF").over(w))
    .with_column("PREV_DATE", F.lag("COLLECTION_DATE").over(w))
    .filter(F.col("PREV_VAF").is_not_null())
    .with_column("VAF_DELTA", F.round((F.col("VAF") - F.col("PREV_VAF")) * 100, 3))
    .with_column("DAYS_BETWEEN", F.datediff("day", F.col("PREV_DATE"), F.col("COLLECTION_DATE")))
    .filter(F.col("DAYS_BETWEEN") > 0)
    .with_column("VAF_TREND", F.iff(F.col("VAF_DELTA") > 0, F.lit("rising"), F.lit("falling")))
)

rising = (
    trajectory
    .group_by("GENE_SYMBOL")
    .agg(
        F.count("*").alias("PAIRED_OBSERVATIONS"),
        F.sum(F.iff(F.col("VAF_DELTA") > 0, 1, 0)).alias("RISING"),
        F.round(F.avg("VAF_DELTA"), 4).alias("MEAN_VAF_DELTA_PCT"),
    )
    .with_column("PCT_RISING", F.round(100 * F.col("RISING") / F.col("PAIRED_OBSERVATIONS"), 1))
    .sort(F.col("PAIRED_OBSERVATIONS").desc())
)

rising.to_pandas().head(12)"""),

    md("md_udf", """### Reusable logic: a UDF

Right now a scoring rule like this probably lives in a Python file on someone's machine, and drifts between team members. Registered as a UDF it runs inside Snowflake, is versioned as an object, and is callable from SQL by anyone with the grant — including analysts who do not write Python."""),

    py("py_udf", """from snowflake.snowpark.types import FloatType, StringType, IntegerType, BooleanType

def confidence_score(vaf: float, depth: int, alt_reads: int, mapq: int, actionable: bool) -> float:
    \"\"\"Composite confidence that a call is a true somatic variant worth reporting.\"\"\"
    if vaf is None or depth is None or alt_reads is None or mapq is None:
        return 0.0
    score = 0.0
    score += min(vaf / 0.10, 1.0) * 35          # allele fraction
    score += min(depth / 5000.0, 1.0) * 25      # coverage
    score += min(alt_reads / 50.0, 1.0) * 20    # supporting reads
    score += min(max(mapq - 20, 0) / 40.0, 1.0) * 15   # mapping quality
    if actionable:
        score += 5                              # clinical relevance nudge
    return round(min(score, 100.0), 2)

session.udf.register(
    func=confidence_score,
    name="VARIANT_CONFIDENCE_SCORE",
    return_type=FloatType(),
    input_types=[FloatType(), IntegerType(), IntegerType(), IntegerType(), BooleanType()],
    is_permanent=True,
    stage_location="@DEMO_STAGE",
    replace=True,
)

print("Registered DEMO.GUARDANT_DEMO.VARIANT_CONFIDENCE_SCORE")"""),

    md("md_udf_sql", """The same function, now callable from SQL. This is the handoff moment: the data scientist writes it in Python, the analyst uses it in SQL."""),

    sql("sql_udf_use", """SELECT specimen_id,
       gene_symbol,
       ROUND(vaf * 100, 3)                AS vaf_pct,
       read_depth,
       alt_read_count,
       clinical_significance,
       VARIANT_CONFIDENCE_SCORE(vaf, read_depth, alt_read_count,
                                mapping_quality, is_actionable) AS confidence
FROM V_REPORTABLE_VARIANTS
WHERE is_actionable
QUALIFY ROW_NUMBER() OVER (ORDER BY confidence DESC) <= 20
ORDER BY confidence DESC;"""),

    md("md_writeback", """### Writing results back

`save_as_table` persists a Snowpark DataFrame with no extract-transform-upload round trip. The cohort table below is built entirely server-side."""),

    py("py_writeback", """cohort = (
    variants
    .filter(F.col("CALL_FILTER") == "PASS")
    .join(panel_lookup, variants["GENE_SYMBOL"] == panel_lookup["PANEL_GENE"])
    .filter(F.col("IS_ACTIONABLE") & (F.col("VAF") >= 0.05))
    .join(specimens, on="SPECIMEN_ID")
    .filter(F.col("QC_STATUS") == "PASS")
    .join(patients, on="PATIENT_ID")
    .select(
        "PATIENT_ID", "SPECIMEN_ID", "PRIMARY_CANCER_TYPE", "STAGE_AT_DIAGNOSIS",
        "COLLECTION_DATE", "ASSAY", "TUMOR_FRACTION",
        "GENE_SYMBOL", "CONSEQUENCE", "VAF", "READ_DEPTH",
        "CLINICAL_SIGNIFICANCE", "TARGETED_THERAPY",
    )
)

cohort.write.mode("overwrite").save_as_table("ACTIONABLE_COHORT")

print(f"ACTIONABLE_COHORT written: {session.table('ACTIONABLE_COHORT').count():,} rows")"""),

    md("md_close", """---

### What changed

| | pandas on a laptop | Snowpark |
|---|---|---|
| Where it runs | Local CPU / RAM | Snowflake warehouse |
| 20M-row aggregate | Extract first, then hope | One expression |
| Scaling up | Buy a bigger laptop | Resize the warehouse |
| Sharing logic | Copy the .py file around | Register a UDF, grant it |
| Writing back | Upload step | `save_as_table` |

Next: **notebook 3** — the same platform, applied to the unstructured half of the data."""),
])


# ===========================================================================
# Notebook 3 — Cortex AI
# ===========================================================================

NB3 = notebook([
    md("md_intro", """# 3 — Snowflake Cortex AI
## "Built-in AI for unstructured clinical data"

Structured variant tables are the easy half. The other half — pathology narratives, clinical notes, trial protocols, literature — holds facts that live in prose, not columns.

Cortex gives you LLM functions as **SQL functions**. No endpoint to stand up, no API key to rotate, no data leaving the account, and the same role-based access control as every other object.

We have 2,000 synthetic pathology narratives to work with."""),

    sql("sql_ctx", """USE WAREHOUSE GUARDANT_DEMO_WH;
USE SCHEMA DEMO.GUARDANT_DEMO;

SELECT report_id, specimen_id, report_date, pathologist,
       LENGTH(report_text) AS chars
FROM PATHOLOGY_REPORTS
LIMIT 5;"""),

    md("md_read_one", """### What we are working with

Deliberately narrative and inconsistent, the way dictated reports actually are. The facts are in the prose. This is why regex is the wrong tool."""),

    sql("sql_read_one", """SELECT report_text
FROM PATHOLOGY_REPORTS
WHERE report_id = (SELECT MIN(report_id) FROM PATHOLOGY_REPORTS);"""),

    md("md_extract", """### AI_EXTRACT — prose to columns

Ask questions in plain English, get back structured answers. One SQL function, no prompt engineering scaffolding.

This turns a free-text corpus into something you can join and aggregate."""),

    sql("sql_extract", """SELECT
    report_id,
    specimen_id,
    AI_EXTRACT(
        text => report_text,
        responseFormat => {
            'cancer_type':       'What is the primary cancer type?',
            'gene':              'Which gene had the reported alteration?',
            'vaf_percent':       'What was the variant allele frequency, as a number?',
            'targetable':        'Is a targeted therapy indicated? Answer yes or no.',
            'resistance':        'Does the report suggest a resistance mechanism? Answer yes or no.'
        }
    ) AS extracted
FROM PATHOLOGY_REPORTS
LIMIT 10;"""),

    md("md_extract_flat", """Flatten the extraction into real columns, and it joins to the structured tables like anything else."""),

    sql("sql_extract_flat", """WITH extracted AS (
    SELECT
        r.report_id,
        r.specimen_id,
        AI_EXTRACT(
            text => r.report_text,
            responseFormat => {
                'gene':       'Which gene had the reported alteration?',
                'targetable': 'Is a targeted therapy indicated? Answer only yes or no.'
            }
        ) AS e
    FROM PATHOLOGY_REPORTS r
    LIMIT 50
)
SELECT
    x.report_id,
    x.specimen_id,
    x.e:response:gene::VARCHAR       AS gene_from_narrative,
    LOWER(x.e:response:targetable::VARCHAR) AS targetable_from_narrative,
    p.primary_cancer_type,
    s.tumor_fraction
FROM extracted x
JOIN SPECIMENS s ON s.specimen_id = x.specimen_id
JOIN PATIENTS  p ON p.patient_id  = s.patient_id;"""),

    md("md_classify", """### AI_CLASSIFY — triage at corpus scale

Route reports into the buckets a molecular tumour board actually cares about. Categories are supplied inline; there is no model to train."""),

    sql("sql_classify", """SELECT
    report_id,
    AI_CLASSIFY(
        report_text,
        ['actionable alteration found',
         'no actionable alteration',
         'resistance mechanism emerging',
         'no change from prior testing']
    ):labels[0]::VARCHAR AS triage_bucket
FROM PATHOLOGY_REPORTS
LIMIT 25;"""),

    md("md_classify_agg", """Classify a slice and aggregate it — a corpus-level view of a text pile that was previously only readable one report at a time."""),

    sql("sql_classify_agg", """WITH classified AS (
    SELECT
        AI_CLASSIFY(
            report_text,
            ['actionable alteration found',
             'no actionable alteration',
             'resistance mechanism emerging',
             'no change from prior testing']
        ):labels[0]::VARCHAR AS triage_bucket
    FROM PATHOLOGY_REPORTS
    LIMIT 200
)
SELECT triage_bucket,
       COUNT(*)                                           AS reports,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM classified
GROUP BY triage_bucket
ORDER BY reports DESC;"""),

    md("md_complete", """### AI_COMPLETE — generation with your own instructions

Where the task is not extraction or classification but summarisation or drafting, `AI_COMPLETE` takes a prompt and a model.

Here: a one-line clinician-facing summary per report."""),

    sql("sql_complete", """SELECT
    report_id,
    AI_COMPLETE(
        'claude-4-sonnet',
        CONCAT(
            'You are assisting a molecular tumour board. In ONE sentence of at most 30 words, ',
            'state the actionable finding and the recommended next step. No preamble.\\n\\n',
            report_text
        )
    ) AS board_summary
FROM PATHOLOGY_REPORTS
LIMIT 5;"""),

    md("md_agg", """### AI_AGG — reasoning across many rows at once

`AI_AGG` is the one with no laptop equivalent at all: it reasons over a whole *group* of text values, not row by row. Ask what the themes are across a cohort's reports."""),

    sql("sql_agg", """WITH cohort AS (
    SELECT r.report_text, p.primary_cancer_type
    FROM PATHOLOGY_REPORTS r
    JOIN SPECIMENS s ON s.specimen_id = r.specimen_id
    JOIN PATIENTS  p ON p.patient_id  = s.patient_id
    WHERE p.primary_cancer_type IN ('Non-Small Cell Lung', 'Colorectal')
    LIMIT 120
)
SELECT
    primary_cancer_type,
    COUNT(*) AS reports_reviewed,
    AI_AGG(
        report_text,
        'Across these pathology reports, summarise in 3 short bullets: the most common
         alterations mentioned, any recurring resistance patterns, and the dominant
         recommended next step. Be specific and concise.'
    ) AS cohort_themes
FROM cohort
GROUP BY primary_cancer_type;"""),

    md("md_python_side", """### The same functions from Python

If the team prefers to stay in Snowpark, Cortex is available there too — so an AI step drops into an existing DataFrame pipeline rather than sitting beside it."""),

    py("py_cortex", """from snowflake.snowpark.context import get_active_session
import snowflake.snowpark.functions as F

session = get_active_session()

reports = session.table("PATHOLOGY_REPORTS").limit(8)

summarised = reports.select(
    F.col("REPORT_ID"),
    F.call_function(
        "AI_COMPLETE",
        F.lit("claude-4-sonnet"),
        F.concat(
            F.lit("In under 20 words, state the single key finding. No preamble.\\n\\n"),
            F.col("REPORT_TEXT"),
        ),
    ).alias("KEY_FINDING"),
)

summarised.to_pandas()"""),

    md("md_close", """---

### What changed

| | Today | Here |
|---|---|---|
| Unstructured data | Read manually, or not at all | Queryable |
| AI on clinical text | External API, data leaves | In-account, governed |
| Access control | Separate system | Same roles as everything else |
| Structured + text together | Two pipelines | One SQL statement |

**Governance point worth making out loud:** every call above ran inside the Snowflake boundary. No report text was sent to a third-party endpoint."""),
])



# ===========================================================================
# Notebook 4 — train and register a model without leaving Snowflake
# ===========================================================================

NB_MODEL = notebook([
    md("md_intro", """# 4 — Train and Register a Model, Without Leaving Snowflake

Part 5 shows three ways a model reaches the registry. This notebook is the third.

| | Where training runs | How it reaches the registry |
|---|---|---|
| **A — via git** | Laptop | Committed to the repo; Snowflake pulls it off the git stage |
| **B — from your laptop** | Laptop | `log_model` pushes it straight from your machine |
| **C — this notebook** | **Snowflake** | Never touches a laptop at all |

Path C is the one to reach for when the training data is large enough that pulling
it down was the problem in the first place. The data stays where it is, the compute
comes to it, and the finished model is a governed Snowflake object at the end.

The result is a third version of `GUARDANT_VARIANT_CLF`, deliberately a different
algorithm from the other two so the registry shows three genuinely different
models rather than three near-identical twins."""),

    py("py_session", """# In a Snowflake notebook you never build a connection. You are already in one.
from snowflake.snowpark.context import get_active_session

session = get_active_session()

DATABASE = "DEMO"
SCHEMA = "GUARDANT_DEMO"
MODEL_NAME = "GUARDANT_VARIANT_CLF"
VERSION = "V3"

FEATURES = ["VAF", "READ_DEPTH", "ALT_READ_COUNT", "MAPPING_QUALITY"]

print("account  :", session.get_current_account())
print("role     :", session.get_current_role())
print("warehouse:", session.get_current_warehouse())"""),

    md("md_data", """## The training sample

Note what is *not* happening: no extract, no CSV, no `df.to_csv()` on a laptop.

`SAMPLE` has to come immediately after the table name and before `WHERE` — the
other order is a syntax error. We sample 80k rows and then filter to `PASS`
calls, which lands around 50k rows: enough to train on, small enough to pull into
the notebook's memory in a couple of seconds."""),

    py("py_train", """import pandas as pd
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import roc_auc_score, recall_score
from sklearn.model_selection import train_test_split

TRAINING_SQL = f\"\"\"
SELECT VAF, READ_DEPTH, ALT_READ_COUNT, MAPPING_QUALITY,
       IFF(CLINICAL_SIGNIFICANCE = 'Pathogenic', 1, 0) AS IS_PATHOGENIC
FROM {DATABASE}.{SCHEMA}.VARIANT_CALLS SAMPLE (80000 ROWS)
WHERE CALL_FILTER = 'PASS'
LIMIT 50000
\"\"\"

df = session.sql(TRAINING_SQL).to_pandas()
print(f"pulled {len(df):,} rows into the notebook")

X = df[FEATURES]
y = df["IS_PATHOGENIC"]
print(f"positive class: {y.mean():.1%}")

X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.25, random_state=42, stratify=y
)

# A linear model on purpose - V1 is a RandomForest and V2 is gradient boosting.
# LogisticRegression needs its features on a common scale, so it goes in a
# Pipeline. The registry treats a Pipeline as one model, which is what you want:
# the scaler travels with the coefficients instead of being re-implemented in SQL.
#
# class_weight="balanced" is not optional here. The positive class is under 10%,
# so an unweighted model happily predicts zero for every row and reports the base
# rate as its accuracy.
pipe = Pipeline([
    ("scaler", StandardScaler()),
    ("clf", LogisticRegression(max_iter=1000, class_weight="balanced", random_state=42)),
])
pipe.fit(X_train, y_train)

proba = pipe.predict_proba(X_test)[:, 1]
pred = pipe.predict(X_test)
auc = roc_auc_score(y_test, proba)
recall = recall_score(y_test, pred)
pred_rate = pred.mean()

print(f"holdout ROC AUC        : {auc:.4f}")
print(f"recall on pathogenic   : {recall:.1%}")
print(f"predicted-positive rate: {pred_rate:.1%} (base rate {y_test.mean():.1%})")

if pred_rate in (0.0, 1.0):
    raise RuntimeError("Model predicts a single class - do not register this.")"""),

    md("md_register", """## Registering it

Two arguments below are the ones that actually decide whether this works.

**`sample_input_data`** is required for scikit-learn. The registry reads the
feature names and types off it to build the model's signature. Without it (or an
explicit `signatures=`) `log_model` refuses the model.

**`target_platforms=["WAREHOUSE"]`** matters *because this notebook runs on a
container runtime*. There, `target_platforms` defaults to Snowpark Container
Services only — so the model would register successfully and then `MODEL!PREDICT`
from SQL would fail to resolve. Off container runtime the default covers both, so
this is the kind of line that looks redundant right up until it isn't."""),

    py("py_register", """from snowflake.ml.registry import Registry
from snowflake.ml.model import task

# Position the session. The registry resolves unqualified names against the
# session's database and schema, and a notebook does not necessarily start in
# the one you want.
session.sql(f"USE DATABASE {DATABASE}").collect()
session.sql(f"USE SCHEMA {SCHEMA}").collect()

registry = Registry(session=session, database_name=DATABASE, schema_name=SCHEMA)

# Re-running this notebook would otherwise collide on the version name. Fail
# loudly and clear it deliberately rather than letting log_model error out with
# a stale model still live in the registry.
existing = [r["name"] for r in
            session.sql(f"SHOW VERSIONS IN MODEL {DATABASE}.{SCHEMA}.{MODEL_NAME}").collect()]
print("versions already registered:", ", ".join(existing) or "(none)")

if VERSION in existing:
    print(f"{VERSION} exists - dropping it so this run replaces it")
    session.sql(
        f"ALTER MODEL {DATABASE}.{SCHEMA}.{MODEL_NAME} DROP VERSION {VERSION}"
    ).collect()

mv = registry.log_model(
    pipe,
    model_name=MODEL_NAME,
    version_name=VERSION,
    sample_input_data=X_train.head(100),
    task=task.Task.TABULAR_BINARY_CLASSIFICATION,
    metrics={
        "roc_auc": round(float(auc), 4),
        "recall": round(float(recall), 4),
        "predicted_positive_rate": round(float(pred_rate), 4),
    },
    comment="LogisticRegression pipeline, trained and registered inside Snowflake",
    target_platforms=["WAREHOUSE"],
)

print(f"\\nregistered {MODEL_NAME} {VERSION}")
# show_functions() returns dicts in some snowflake-ml-python versions and
# objects in others. Handle both rather than guessing.
funcs = mv.show_functions()
print("callable methods:", [f["name"] if isinstance(f, dict) else f.name for f in funcs])"""),

    md("md_verify", """## Scoring it from SQL

The model is now a schema-level object. Anyone with `USAGE` on it can call it
from plain SQL without knowing it is a scikit-learn pipeline, without a Python
environment, and without the ability to see inside it.

`USAGE` is the privilege to keep in mind for a wider team: it permits warehouse
inference while revealing nothing about the model's internals. `READ` is the more
permissive one, and it exposes metadata and metrics."""),

    sql("sql_versions", """SHOW VERSIONS IN MODEL DEMO.GUARDANT_DEMO.GUARDANT_VARIANT_CLF;"""),

    sql("sql_predict", """-- Model methods resolve against the session schema, so USE SCHEMA is required
-- here. An unqualified MODEL!PREDICT without it fails as "Unknown function".
USE SCHEMA DEMO.GUARDANT_DEMO;

WITH m AS MODEL GUARDANT_VARIANT_CLF VERSION V3
SELECT
    variant_id,
    gene_symbol,
    vaf,
    read_depth,
    m!PREDICT(vaf, read_depth, alt_read_count, mapping_quality) AS scored
FROM DEMO.GUARDANT_DEMO.VARIANT_CALLS
WHERE call_filter = 'PASS'
LIMIT 10;"""),

    md("md_close", """## Where that leaves you

`GUARDANT_VARIANT_CLF` now carries three versions, each having arrived by a
different route, and all three callable the same way from SQL.

The point worth keeping: **the registry is the artifact store, and git is for the
code that produces the artifact.** A `.joblib` in a repo gives you no signature,
no metrics, no versioning and no access control. The same model logged here gives
you all four, and inference runs next to the data instead of pulling it to a
laptop first.

Set which version consumers get by default with:

```sql
ALTER MODEL DEMO.GUARDANT_DEMO.GUARDANT_VARIANT_CLF SET DEFAULT_VERSION = V3;
```"""),
])


# ===========================================================================

def main() -> None:
    NOTEBOOK_DIR.mkdir(parents=True, exist_ok=True)
    targets = {
        "01_snowflake_notebooks.ipynb": NB1,
        "02_snowpark_at_scale.ipynb": NB2,
        "03_cortex_ai_clinical_text.ipynb": NB3,
        "04_train_register_in_snowflake.ipynb": NB_MODEL,
    }
    for filename, nb in targets.items():
        path = NOTEBOOK_DIR / filename
        path.write_text(json.dumps(nb, indent=1) + "\n")
        n_sql = sum(1 for c in nb["cells"] if c["metadata"].get("language") == "sql")
        n_py = sum(1 for c in nb["cells"] if c["metadata"].get("language") == "python")
        n_md = sum(1 for c in nb["cells"] if c["cell_type"] == "markdown")
        print(f"wrote {filename}: {len(nb['cells'])} cells ({n_md} md, {n_sql} sql, {n_py} py)")


if __name__ == "__main__":
    main()
