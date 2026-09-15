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
# Lab workbook — the hands-on version.
#
# Design constraints that differ from the demo notebooks above:
#   - ONE notebook covering all six stations. Six people switching between three
#     notebooks costs minutes the session does not have.
#   - Every station ends with a CHECKPOINT stating the expected result, so a
#     participant knows whether they are actually keeping up.
#   - Every station has an ESCAPE: a single cell that produces the end state
#     without the intermediate steps, for anyone who fell behind. Falling behind
#     on one station must never block the next.
#   - Writes only ever go to the participant's own schema.
#   - Exercises are one line each. Anything longer does not fit the pacing.
# ===========================================================================

NB_LAB = notebook([
    md("md_welcome", """# Guardant Health — Hands-On Lab Workbook

Work through this at your own pace. **You cannot break anything** — every write
goes into your own private schema.

### Before you start
You should already have run `lab/02_participant_setup.sql`. If you have not, do
that first: it gives you your own working area.

### How to use this workbook
- Six stations. Each one ends with a **CHECKPOINT** telling you what you should see.
- If a checkpoint does not match, or you fall behind: run the **ESCAPE** cell at
  the end of that station and move on. You will be in the right place for the
  next station.
- Exercises are marked **YOUR TURN** and are one line of code each. The answer is
  in the cell immediately after, so do not scroll if you want to try it.

Put your hand up whenever something does not work. That is what the session is for."""),

    md("md_s0", """---
## Station 0 — Where am I?

Confirms you are pointed at your own schema and can see the shared data.

This one is Python rather than SQL for a mundane reason: a notebook SQL cell will
not accept `SET x = <expression>`, so we work the schema name out in Python and
set the session context from there."""),

    py("py_s0", """import re
from snowflake.snowpark.context import get_active_session

session = get_active_session()

session.sql("USE ROLE GUARDANT_LAB").collect()
session.sql("USE WAREHOUSE GUARDANT_LAB_WH").collect()

me = session.sql("SELECT CURRENT_USER()").collect()[0][0]
my_schema = "GUARDANT_LAB.LAB_" + re.sub(r"[^A-Za-z0-9]", "_", me).upper()
session.sql(f"USE SCHEMA {my_schema}").collect()

shared_rows = session.table("GUARDANT_LAB.GUARDANT_DEMO.VARIANT_CALLS").count()

print(f"You:                  {me}")
print(f"Your private schema:  {my_schema}")
print(f"Shared variant calls: {shared_rows:,}")"""),

    md("md_s0_check", """**CHECKPOINT** — `your_private_schema` contains your username, and
`shared_variant_calls` is **20,000,000**.

If the count fails, you are missing a SELECT grant. Hand up."""),

    md("md_s1", """---
## Station 1 — Notebooks (~10 min)

The point of this station: **this is your Jupyter, but the compute is in Snowflake.**

Today you query Snowflake, download the result, and process it locally. Watch how
far you get here without downloading anything."""),

    sql("sql_s1_scale", """-- The table you are about to work with.
SELECT COUNT(*)                                         AS raw_variant_calls,
       COUNT(DISTINCT specimen_id)                      AS specimens,
       ROUND(COUNT(*) / COUNT(DISTINCT specimen_id), 1) AS avg_calls_per_specimen
FROM GUARDANT_LAB.GUARDANT_DEMO.VARIANT_CALLS;"""),

    sql("sql_s1_burden", """-- The aggregation runs on 20M rows. Only 15 rows come back.
SELECT gene_symbol,
       COUNT(*)                    AS reportable_calls,
       COUNT(DISTINCT specimen_id) AS specimens_affected,
       ROUND(MEDIAN(vaf) * 100, 3) AS median_vaf_pct,
       MAX(is_actionable)          AS has_targeted_therapy
FROM GUARDANT_LAB.GUARDANT_DEMO.V_REPORTABLE_VARIANTS
GROUP BY gene_symbol
ORDER BY reportable_calls DESC
LIMIT 15;"""),

    md("md_s1_handoff", """### The handoff

Any SQL cell is available in Python **by its cell name**. No connector, no
cursor, no credentials, no download."""),

    py("py_s1_handoff", """df = sql_s1_burden.to_pandas()

print(f"Rows now in Python:        {len(df):,}")
print(f"Rows scanned in Snowflake: 20,000,000")
df.head()"""),

    md("md_s1_turn", """### YOUR TURN

Plot it. One line — fill in the column name for the bar lengths:

```python
ax.barh(plot_df["GENE_SYMBOL"], plot_df[" ... "])
```"""),

    py("py_s1_viz", """import matplotlib.pyplot as plt

plot_df = df.sort_values("REPORTABLE_CALLS")
colors = ["#29B5E8" if a else "#B0BEC5" for a in plot_df["HAS_TARGETED_THERAPY"]]

fig, ax = plt.subplots(figsize=(9, 5))
ax.barh(plot_df["GENE_SYMBOL"], plot_df["REPORTABLE_CALLS"], color=colors)
ax.set_xlabel("Reportable variant calls")
ax.set_title("Mutation burden by gene (blue = targeted therapy available)")
ax.spines[["top", "right"]].set_visible(False)
plt.tight_layout()
plt.show()"""),

    md("md_s1_check", """**CHECKPOINT** — you have a horizontal bar chart, TP53 longest, some bars blue.

**ESCAPE** — if the chart did not render, skip it. The table from `sql_s1_burden`
makes the same point and nothing later depends on the plot."""),

    md("md_s2", """---
## Station 2 — GitHub (~10 min)

The point: **your existing Git workflow, connected — no new process to learn.**

This station is mostly driven in the Snowsight UI, not in this notebook.

1. Open a new browser tab → Snowsight → **Projects → Workspaces**
2. Click **From Git repository**
3. Repository URL: `https://github.com/sfc-gh-pmatson/guardant-snowflake-enablement.git`
4. The repo is **public**, so no credential or token is needed
5. Browse to `notebooks/` — this is the same content you are running now
6. Make an edit, then commit and push from inside Snowsight

**CHECKPOINT** — you can see the repo files in a Workspace and the commit button
is live.

**ESCAPE** — if your account blocks outbound access to github.com, this is a
policy restriction, not a mistake you made. Watch the facilitator's screen and
move to Station 3."""),

    md("md_s3", """---
## Station 3 — Cortex Code (~10 min)

The point: **an AI assistant that already knows your schema.**

Also driven in the UI. Open Cortex Code in Snowsight and give it this prompt:

> Using GUARDANT_LAB.GUARDANT_DEMO, write me a Snowpark query that finds the
> patients whose KRAS variant allele frequency increased between two blood draws.

Then ask it a follow-up:

> Explain what that query does, line by line.

**Why this matters for your team:** this is how a new joiner gets productive in
days instead of weeks. They can ask what a query does instead of finding the
person who wrote it.

**CHECKPOINT** — you got a query back that references real column names from the
schema, not invented ones.

**ESCAPE** — if Cortex Code is not enabled in your account, watch and move on."""),

    md("md_s4", """---
## Station 4 — Snowpark (~10 min)

The point: **pandas-style DataFrames, with no memory ceiling.**

The critical idea: a Snowpark DataFrame is **lazy**. It holds a query, not data.
Nothing moves until you ask for a result."""),

    py("py_s4_session", """from snowflake.snowpark.context import get_active_session
import snowflake.snowpark.functions as F
from snowflake.snowpark.window import Window

session = get_active_session()

variants  = session.table("GUARDANT_LAB.GUARDANT_DEMO.VARIANT_CALLS")
specimens = session.table("GUARDANT_LAB.GUARDANT_DEMO.SPECIMENS")
panel     = session.table("GUARDANT_LAB.GUARDANT_DEMO.GENE_PANEL")

# Rename the panel's join key so GENE_SYMBOL is never ambiguous downstream.
panel_lookup = panel.select(
    F.col("GENE_SYMBOL").alias("PANEL_GENE"), "IS_ACTIONABLE", "TARGETED_THERAPY"
)

print(f"Rows available: {variants.count():,}")"""),

    md("md_s4_lazy", """### Proof it is lazy

Build a four-stage pipeline, then look at what Snowpark actually made. It is SQL.
No rows have moved."""),

    py("py_s4_lazy", """pipeline = (
    variants
    .filter(F.col("CALL_FILTER") == "PASS")
    .join(specimens, on="SPECIMEN_ID")
    .group_by("GENE_SYMBOL")
    .agg(F.count("*").alias("N"))
)

print(pipeline.queries["queries"][0][:600])"""),

    md("md_s4_turn", """### YOUR TURN

Aggregate across all 20M rows. Fill in the filter so you only count calls that
passed QC:

```python
.filter(F.col(" ... ") == "PASS")
```"""),

    py("py_s4_agg", """import time

gene_stats = (
    variants
    .filter(F.col("CALL_FILTER") == "PASS")
    .join(panel_lookup, variants["GENE_SYMBOL"] == panel_lookup["PANEL_GENE"])
    .group_by("GENE_SYMBOL", "IS_ACTIONABLE")
    .agg(
        F.count("*").alias("PASS_CALLS"),
        F.count_distinct("SPECIMEN_ID").alias("SPECIMENS"),
        F.round(F.median("VAF") * 100, 3).alias("MEDIAN_VAF_PCT"),
    )
    .sort(F.col("PASS_CALLS").desc())
)

t0 = time.time()
out = gene_stats.to_pandas()
print(f"Aggregated 20M rows in {time.time() - t0:.1f}s, returned {len(out)} rows")
out.head(10)"""),

    md("md_s4_window", """### The question you actually care about

Not "what is the VAF" but "is it **rising** across serial draws". That is a
window function over each patient's draw history — the operation that gets
painful in pandas, because it needs the whole partition in memory."""),

    py("py_s4_window", """w = Window.partition_by("PATIENT_ID", "GENE_SYMBOL").order_by("COLLECTION_DATE")

trajectory = (
    variants
    .filter((F.col("CALL_FILTER") == "PASS") & (F.col("VAF") >= 0.02))
    .join(specimens, on="SPECIMEN_ID")
    .filter(F.col("QC_STATUS") == "PASS")
    .select("PATIENT_ID", "GENE_SYMBOL", "COLLECTION_DATE", "VAF")
    .with_column("PREV_VAF", F.lag("VAF").over(w))
    .filter(F.col("PREV_VAF").is_not_null())
    .with_column("VAF_DELTA", F.round((F.col("VAF") - F.col("PREV_VAF")) * 100, 3))
)

rising = (
    trajectory
    .group_by("GENE_SYMBOL")
    .agg(
        F.count("*").alias("PAIRED_OBSERVATIONS"),
        F.sum(F.iff(F.col("VAF_DELTA") > 0, 1, 0)).alias("RISING"),
    )
    .with_column("PCT_RISING",
                 F.round(100 * F.col("RISING") / F.col("PAIRED_OBSERVATIONS"), 1))
    .sort(F.col("PAIRED_OBSERVATIONS").desc())
)

rising.to_pandas().head(10)"""),

    md("md_s4_write", """### Write the result back to your own schema

No extract, no upload. `save_as_table` persists it server-side."""),

    py("py_s4_write", """my_cohort = (
    variants
    .filter(F.col("CALL_FILTER") == "PASS")
    .join(panel_lookup, variants["GENE_SYMBOL"] == panel_lookup["PANEL_GENE"])
    .filter(F.col("IS_ACTIONABLE") & (F.col("VAF") >= 0.05))
    .select("SPECIMEN_ID", "GENE_SYMBOL", "VAF", "READ_DEPTH", "TARGETED_THERAPY")
)

# Unqualified name = your own schema, because Station 0 set the context.
my_cohort.write.mode("overwrite").save_as_table("MY_ACTIONABLE_COHORT")

print(f"MY_ACTIONABLE_COHORT: {session.table('MY_ACTIONABLE_COHORT').count():,} rows")"""),

    md("md_s4_check", """**CHECKPOINT** — `MY_ACTIONABLE_COHORT` exists in your schema with roughly
3–4 million rows.

**ESCAPE** — run the cell below to create it in one statement and move on."""),

    sql("sql_s4_escape", """-- ESCAPE for Station 4: same end state, one statement.
CREATE OR REPLACE TABLE MY_ACTIONABLE_COHORT AS
SELECT specimen_id, gene_symbol, vaf, read_depth, targeted_therapy
FROM GUARDANT_LAB.GUARDANT_DEMO.V_REPORTABLE_VARIANTS
WHERE is_actionable AND vaf >= 0.05;

SELECT COUNT(*) AS my_cohort_rows FROM MY_ACTIONABLE_COHORT;"""),

    md("md_s5", """---
## Station 5 — Cortex AI (~10 min)

The point: **the unstructured half of your data becomes queryable.**

2,000 synthetic pathology narratives. The facts are in the prose, not in columns,
which is why regex is the wrong tool. And every call below runs inside Snowflake —
no report text goes to an external endpoint."""),

    sql("sql_s5_read", """-- Read one, so you can see what the model is working with.
SELECT report_text
FROM GUARDANT_LAB.GUARDANT_DEMO.PATHOLOGY_REPORTS
LIMIT 1;"""),

    md("md_s5_turn", """### YOUR TURN

`AI_EXTRACT` turns prose into columns. Add a fourth question of your own to the
`responseFormat` below — anything you would actually want off a report."""),

    sql("sql_s5_extract", """SELECT
    report_id,
    AI_EXTRACT(
        text => report_text,
        responseFormat => {
            'cancer_type': 'What is the primary cancer type?',
            'gene':        'Which gene had the reported alteration?',
            'targetable':  'Is a targeted therapy indicated? Answer only yes or no.'
        }
    ) AS extracted
FROM GUARDANT_LAB.GUARDANT_DEMO.PATHOLOGY_REPORTS
LIMIT 5;"""),

    md("md_s5_classify", """### Triage the whole corpus

`AI_CLASSIFY` routes reports into the buckets a molecular tumour board cares
about. No model to train, categories supplied inline."""),

    sql("sql_s5_classify", """WITH classified AS (
    SELECT AI_CLASSIFY(
             report_text,
             ['actionable alteration found',
              'no actionable alteration',
              'resistance mechanism emerging',
              'no change from prior testing']
           ):labels[0]::VARCHAR AS triage_bucket
    FROM GUARDANT_LAB.GUARDANT_DEMO.PATHOLOGY_REPORTS
    LIMIT 100
)
SELECT triage_bucket,
       COUNT(*)                                           AS reports,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM classified
GROUP BY triage_bucket
ORDER BY reports DESC;"""),

    md("md_s5_agg", """### Reasoning across many rows at once

`AI_AGG` is the one with no laptop equivalent: it reasons over a whole *group* of
text values rather than row by row."""),

    sql("sql_s5_agg", """WITH cohort AS (
    SELECT r.report_text, p.primary_cancer_type
    FROM GUARDANT_LAB.GUARDANT_DEMO.PATHOLOGY_REPORTS r
    JOIN GUARDANT_LAB.GUARDANT_DEMO.SPECIMENS s ON s.specimen_id = r.specimen_id
    JOIN GUARDANT_LAB.GUARDANT_DEMO.PATIENTS  p ON p.patient_id  = s.patient_id
    WHERE p.primary_cancer_type = 'Non-Small Cell Lung'
    LIMIT 60
)
SELECT primary_cancer_type,
       COUNT(*) AS reports_reviewed,
       AI_AGG(report_text,
              'In 3 short bullets: the most common alterations mentioned, any
               recurring resistance patterns, and the dominant recommended next
               step. Be specific and concise.') AS cohort_themes
FROM cohort
GROUP BY primary_cancer_type;"""),

    md("md_s5_check", """**CHECKPOINT** — the extraction returned a gene name matching the narrative, and
`AI_AGG` produced three bullets.

**ESCAPE** — if a Cortex call errors on model availability, that is a region
setting, not your mistake. Skip to Station 6."""),

    md("md_s6", """---
## Station 6 — Snowsight (~3 min)

The point: **your analyst colleagues get the same governed data, without code.**

In Snowsight: **Projects → Dashboards → New Dashboard**, add a tile, and paste:

```sql
SELECT primary_cancer_type,
       COUNT(DISTINCT patient_id) AS patients_with_actionable_variant
FROM GUARDANT_LAB.GUARDANT_DEMO.V_REPORTABLE_VARIANTS
WHERE is_actionable AND vaf >= 0.05
GROUP BY primary_cancer_type
ORDER BY patients_with_actionable_variant DESC
LIMIT 12;
```

Switch the tile to **Chart → Bar**. More tile queries are in
`dashboards/snowsight_dashboard_queries.sql`.

**CHECKPOINT** — a bar chart, no CSV involved anywhere.

**The thing to notice:** that dashboard reads the same tables you just used from
Python, under the same permissions. One copy of the data, one set of controls."""),

    md("md_close", """---
## What you just did

| | Before | Now |
|---|---|---|
| Where compute ran | Your laptop | Snowflake |
| Data movement | Full extract every time | Results only |
| Environment setup | Per person, per machine | None |
| Ceiling | Local RAM | Warehouse size |
| Unstructured data | Read by hand, or not at all | Queryable |
| Analyst access | You export a CSV for them | They self-serve |

### Take it with you

Everything here is public: **github.com/sfc-gh-pmatson/guardant-snowflake-enablement**

The dataset regenerates from SQL in about 30 seconds, so you can rebuild this
whole lab in any account.

### Your working area

Your schema and everything in it survives the session. If you want it cleaned up,
say so — otherwise it stays for you to keep poking at."""),
])


# ===========================================================================

def main() -> None:
    NOTEBOOK_DIR.mkdir(parents=True, exist_ok=True)
    targets = {
        "01_snowflake_notebooks.ipynb": NB1,
        "02_snowpark_at_scale.ipynb": NB2,
        "03_cortex_ai_clinical_text.ipynb": NB3,
        "00_lab_workbook.ipynb": NB_LAB,
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
