# Guardant Health — Snowflake Enablement Session

Demo assets for the in-person session with the Guardant Health bioinformatics
and data science team.

**Session:** Thursday 17 September 2026, 11:00–12:00 PDT (1 hour, in person)
**Format:** hands-on — six participants work through it themselves, in Guardant's
own Snowflake account.

> **Running the hands-on lab?** Start at **[`lab/PREREQUISITES.md`](lab/PREREQUISITES.md)**,
> then **[`lab/FACILITATOR_RUNBOOK.md`](lab/FACILITATOR_RUNBOOK.md)**.
> Participants get **[`lab/PARTICIPANT_GUIDE.md`](lab/PARTICIPANT_GUIDE.md)**.

## The problem we are addressing

The team currently queries Snowflake, **downloads the result**, processes it in
local Jupyter notebooks, and writes results back. That extract step is the
bottleneck: it caps analysis at local RAM, requires every teammate to maintain an
identical Python environment, and puts patient-adjacent data on laptops.

Every asset here demonstrates the same workload running *inside* the platform.

## What is in here

```
lab/                        HANDS-ON LAB (participants run this themselves)
  PREREQUISITES.md          what Guardant IT must confirm and grant — start here
  00_preflight_check.sql    read-only: privileges, Cortex, Notebooks, git egress
  01_admin_setup.sql        lab role, warehouse, per-participant schemas
  02_participant_setup.sql  each attendee runs this at their own keyboard
  PARTICIPANT_GUIDE.md      the six stations, for attendees
  FACILITATOR_RUNBOOK.md    your script: timings, cut points, live triage
  99_rehearsal_shortcut.sql stand the lab up in your own account to rehearse
setup/
  00_setup.sql              database, schema, warehouse, stage
  01_synthetic_data.sql     generates the entire dataset (~20M rows)
  02_udf.sql                pre-seeds the variant confidence UDF
  03_git_integration.sql    secret / API integration / git repository
  04_deploy_notebooks.sql   creates the notebooks from this git repo
notebooks/
  00_lab_workbook.ipynb             HANDS-ON: all six stations, one notebook
  01_snowflake_notebooks.ipynb      demo: "your Jupyter, but in Snowflake"
  02_snowpark_at_scale.ipynb        demo: Python DataFrames at 20M rows
  03_cortex_ai_clinical_text.ipynb  demo: LLM functions over pathology narratives
  environment.yml                   notebook package requirements
dashboards/
  snowsight_dashboard_queries.sql   six tiles for the Snowsight segment
tools/
  build_notebooks.py        regenerates the .ipynb files from plain text
  verify_sql_cells.py       executes every SQL cell and reports failures
```

### Demo notebooks vs the lab workbook

Both are here on purpose. `notebooks/01`–`03` are paced for **you** driving while
people watch. `notebooks/00_lab_workbook.ipynb` is paced for **them** typing:
one notebook instead of three, a checkpoint at every station, and an escape cell
so falling behind on one topic never blocks the next.

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

Two layers, both worth running the morning of the session.

**SQL cells** — executes every SQL cell in all three notebooks and reports
pass/fail per cell:

```bash
python3 tools/verify_sql_cells.py
```

**Whole notebooks, including the Python cells** — runs them headlessly in
Snowflake, which is the only way to catch Snowpark errors:

```sql
EXECUTE NOTEBOOK DEMO.GUARDANT_DEMO.GUARDANT_01_NOTEBOOKS();
EXECUTE NOTEBOOK DEMO.GUARDANT_DEMO.GUARDANT_02_SNOWPARK();
EXECUTE NOTEBOOK DEMO.GUARDANT_DEMO.GUARDANT_03_CORTEX_AI();
```

All three currently pass end to end. Notebook 3 makes real Cortex calls, so it
consumes a small amount of AI credit.

A notebook that only looks right is worthless in front of a customer.

If you edit notebook content, edit `tools/build_notebooks.py` and regenerate:

```bash
python3 tools/build_notebooks.py
```

Cell content lives as plain text in that script, which keeps it reviewable in
diffs and means a mangled `.ipynb` JSON blob is always recoverable.

After pushing notebook changes, redeploy so Snowflake picks them up:

```bash
snow sql -c <connection> --role ACCOUNTADMIN -f setup/04_deploy_notebooks.sql
```

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
