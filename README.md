# Guardant Health — Snowflake Enablement Session

Demo assets for the in-person walkthrough with the Guardant Health bioinformatics
and data science team.

**Session:** Thursday 17 September 2026, 11:00–12:00 PDT (1 hour, in person)

## The problem we are addressing

The team currently queries Snowflake, **downloads the result**, processes it in
local Jupyter notebooks, and writes results back. That extract step is the
bottleneck: it caps analysis at local RAM, requires every teammate to maintain an
identical Python environment, and puts patient-adjacent data on laptops.

Every asset here demonstrates the same workload running *inside* the platform.

## What is in here

```
setup/
  00_setup.sql              database, schema, warehouse, stage
  01_synthetic_data.sql     generates the entire dataset (~20M rows)
  02_udf.sql                pre-seeds the variant confidence UDF
notebooks/
  01_snowflake_notebooks.ipynb      "your Jupyter, but in Snowflake"
  02_snowpark_at_scale.ipynb        Python DataFrames at 20M rows
  03_cortex_ai_clinical_text.ipynb  LLM functions over pathology narratives
  environment.yml                   notebook package requirements
dashboards/
  snowsight_dashboard_queries.sql   six tiles for the Snowsight segment
tools/
  build_notebooks.py        regenerates the .ipynb files from plain text
  verify_sql_cells.py       executes every SQL cell and reports failures
```

## The data

**All synthetic.** Nothing in this repo is real patient data, and there are no
data files — the entire dataset is generated in-database from Snowflake's
`GENERATOR` and `RANDOM` functions, so it is fully reproducible from SQL alone.

A synthetic liquid-biopsy cohort:

| Table | Rows | What it is |
|---|---|---|
| `PATIENTS` | 50,000 | Demographics, primary cancer type, stage |
| `SPECIMENS` | 120,000 | Serial blood draws with assay, tumour fraction, QC |
| `VARIANT_CALLS` | **20,000,000** | Raw pre-filter calls, ~167 per specimen |
| `PATHOLOGY_REPORTS` | 2,000 | Free-text narratives for the Cortex AI demo |
| `GENE_PANEL` | 60 | Panel definition with targeted-therapy annotations |
| `V_REPORTABLE_VARIANTS` | ~11,000,000 | The analysis-ready join (PASS calls only) |

The shaping is deliberate, not uniform noise:

- Gene mutation frequency follows a realistic long tail (TP53 ≫ KRAS ≫ PIK3CA ≫ …)
- VAF is cubed-skewed, so most calls are low-frequency and a minority are clonal
- Low tumour fraction correlates with QC trouble, as in a real assay
- ~59% of raw calls are `PASS`; the rest are the noise floor the demos filter out

20M rows is chosen so that "just pull it into pandas" is genuinely infeasible,
while still generating in about 30 seconds on a MEDIUM warehouse.

## Setup

Run once, in order:

```bash
snow sql -c <connection> --role ACCOUNTADMIN -f setup/00_setup.sql
snow sql -c <connection> --role ACCOUNTADMIN -f setup/01_synthetic_data.sql   # ~30s
snow sql -c <connection> --role ACCOUNTADMIN -f setup/02_udf.sql
```

Everything lands in `DEMO.GUARDANT_DEMO` on warehouse `GUARDANT_DEMO_WH`
(MEDIUM, 60s auto-suspend).

All three scripts are idempotent — re-running gives a fresh randomised dataset.

## Verifying before you present

```bash
python3 tools/verify_sql_cells.py
```

This executes **every** SQL cell in all three notebooks against the account and
reports pass/fail per cell. Run it the morning of the session: a notebook that
only looks right is worthless in front of a customer.

If you edit notebook content, edit `tools/build_notebooks.py` and regenerate:

```bash
python3 tools/build_notebooks.py
```

Cell content lives as plain text in that script, which keeps it reviewable in
diffs and means a mangled `.ipynb` JSON blob is always recoverable.

## Session flow

| Segment | Asset | Minutes |
|---|---|---|
| Notebooks | `01_snowflake_notebooks.ipynb` | ~10 |
| GitHub integration | this repo, linked as a Workspace | ~10 |
| Cortex Code | live, in Snowsight | ~10 |
| Snowpark | `02_snowpark_at_scale.ipynb` | ~10 |
| Cortex AI | `03_cortex_ai_clinical_text.ipynb` | ~10 |
| Snowsight | `dashboards/snowsight_dashboard_queries.sql` | ~3 |

The notebooks are built to be read in order — each one closes by pointing at the
next — but any single notebook stands alone if the conversation goes sideways.

## Connecting this repo as a Snowflake Workspace

The GitHub segment of the session uses this repo as its own demo subject.

Snowflake-side objects (secret, API integration, git repository) are created by
`setup/03_git_integration.sql`. **The Workspace itself must be created in the
Snowsight UI** — there is no DDL or CLI path for a git-backed Workspace:

> Projects → Workspaces → **From Git repository**

Point it at this repo's HTTPS URL and select the credential created by the
setup script.

## Fallbacks if a demo fails live

- **Cortex model unavailable in region** — `AI_COMPLETE` takes a model argument;
  swap `claude-4-sonnet` for another available model, or fall back to the
  `AI_EXTRACT` / `AI_CLASSIFY` cells, which do not name a model.
- **UDF missing** — re-run `setup/02_udf.sql`; the notebook's Python
  registration cell uses `replace=True` and is safe to re-run at any point.
- **Notebook packages missing** — `matplotlib` comes from `environment.yml`. If a
  chart cell fails, skip it; the SQL result table above it makes the same point.
- **Warehouse cold** — first query of the session pays resume latency. Run
  `SELECT 1` on `GUARDANT_DEMO_WH` a minute before you start.

## Teardown

```sql
DROP SCHEMA IF EXISTS DEMO.GUARDANT_DEMO CASCADE;
DROP WAREHOUSE IF EXISTS GUARDANT_DEMO_WH;
```
