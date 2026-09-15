# Guardant Health — Snowflake Enablement Session

Demo assets for the in-person session with the Guardant Health bioinformatics
and data science team.

**Session:** Thursday 17 September 2026, 11:00–12:00 PDT (in person)
**Format:** eight-segment developer surface tour — Peter drives throughout.

> **Running the session?** Start at **[`demo/runbook.md`](demo/runbook.md)**, then
> run **[`demo/demo.sql`](demo/demo.sql)** top to bottom.
> Build everything first with **[`demo/build.sql`](demo/build.sql)**.
>
> **Want a hands-on lab instead?** `lab/` is a complete self-serve lab, kept as a
> take-home. See [`lab/PREREQUISITES.md`](lab/PREREQUISITES.md).

## The problem we are addressing

The team currently queries Snowflake, **downloads the result**, processes it in
local Jupyter notebooks, and writes results back. That extract step is the
bottleneck: it caps analysis at local RAM, requires every teammate to maintain an
identical Python environment, and puts patient-adjacent data on laptops.

Every asset here demonstrates the same workload running *inside* the platform.

## What is in here

```
demo/                       THE SESSION (Peter drives, 8 segments)
  runbook.md                talk track, timings, cut order, triage — start here
  build.sql                 creates every object, with a VERIFY section
  demo.sql                  run top to bottom during the session
  teardown.sql              suspend / remove (compute pools cost money)
semantic/
  sv_guardant_variants.yaml the semantic view, as a versioned file
model/
  variant_clf.joblib        the trained model, committed for segment 8
tools/
  train_and_register_model.py  train locally, log to the Model Registry
  deploy_semantic_view.py      deploy the semantic view from its YAML
  build_notebooks.py           regenerates the .ipynb files from plain text
  verify_sql_cells.py          executes every notebook SQL cell
lab/                        TAKE-HOME hands-on lab (not used live)
  PREREQUISITES.md          what an admin must confirm and grant
  00_preflight_check.sql    read-only readiness check
  01_admin_setup.sql        lab role, warehouse, per-participant schemas
  02_participant_setup.sql  what each attendee runs
  PARTICIPANT_GUIDE.md      the six stations
  FACILITATOR_RUNBOOK.md    lab facilitation notes
  99_rehearsal_shortcut.sql stand the lab up in your own account
setup/
  00_setup.sql              database, schema, warehouse, stage
  01_synthetic_data.sql     generates the entire dataset (~20M rows)
  02_udf.sql                variant confidence UDF
  03_git_integration.sql    secret / API integration / git repository
  04_deploy_notebooks.sql   creates the notebooks from this git repo
notebooks/
  00_lab_workbook.ipynb             hands-on: all six lab stations
  01_snowflake_notebooks.ipynb      used in segment 3
  02_snowpark_at_scale.ipynb        Python DataFrames at 20M rows
  03_cortex_ai_clinical_text.ipynb  LLM functions over pathology narratives
dashboards/
  snowsight_dashboard_queries.sql   six Snowsight tiles
```

### The eight segments

| # | Segment | Budget |
|---|---|---|
| 1 | Snowflake overview, CoCo and CoCo Desktop | 8 min |
| 2 | Claude Code plugin + VS Code extension | 5 min |
| 3 | Notebooks, including creating a compute pool | 9 min |
| 4 | Snowflake-Labs GitHub, git repository objects | 6 min |
| 5 | Local model → Model Registry → inference in Snowflake | 12 min |
| 6 | Semantic view over the data | 8 min |
| 7 | Cortex Agent on the semantic view, shared to a role | 8 min |
| 8 | Commit the YAML and model, redeploy from git | 10 min |

### The GitOps loop

`semantic/sv_guardant_variants.yaml` is the source of truth for the semantic view.
It deploys with `SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML` and exports back out of the
running object with `SYSTEM$READ_YAML_FROM_SEMANTIC_VIEW`, so the file in git and
the object in the account are the same artifact. Redeploying it into a second schema
returns byte-identical numbers, which is the proof.

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
