# Guardant Health — Snowflake Enablement

Everything from the in-person enablement session, packaged so you can rebuild it in
your own Snowflake account and keep working with it.

**All data here is synthetic.** There are no data files — the entire ~20M row
dataset is generated in-database from Snowflake's `GENERATOR` and `RANDOM`
functions, so it is reproducible from SQL alone and contains nothing patient-derived.

## The problem this addresses

Today the loop is: query Snowflake, **download the result**, process it in a local
Jupyter notebook, write results back. That download step is the bottleneck. It caps
analysis at local RAM, requires every teammate to maintain an identical Python
environment, and puts patient-adjacent data on laptops.

Everything in this repo runs the same workload *inside* the platform instead.

## Start here

Run these in order with a role that can create databases, warehouses and roles
(ACCOUNTADMIN is simplest). All of them are idempotent — re-running is safe.

```bash
snow sql -c <connection> --role ACCOUNTADMIN -f setup/00_setup.sql
snow sql -c <connection> --role ACCOUNTADMIN -f setup/01_synthetic_data.sql   # ~30s
snow sql -c <connection> --role ACCOUNTADMIN -f setup/02_udf.sql
```

That gives you the dataset in `DEMO.GUARDANT_DEMO` on warehouse `GUARDANT_DEMO_WH`.
At this point you can open the notebooks and work.

**Optional, in order, as you need them:**

| Script | What it adds | When you need it |
|---|---|---|
| `setup/03_git_integration.sql` | Secret, API integration, git repository object | To pull this repo into Snowflake |
| `setup/04_deploy_notebooks.sql` | Creates the four notebooks from the git repo | After 03 |
| `setup/05_semantic_view_and_agent.sql` | Semantic view, Cortex Agent, compute pool, consumer role | For the governed-access parts |
| `setup/99_teardown.sql` | Removes everything | When you are done |

`setup/03` needs a GitHub credential — see the placeholder inside it. If you only
want the notebooks locally, skip 03 and 04 and open the `.ipynb` files directly.

## What is in here

```
setup/
  00_setup.sql                    database, schema, warehouse, stage
  01_synthetic_data.sql           generates the entire ~20M row dataset
  02_udf.sql                      variant confidence UDF
  03_git_integration.sql          secret / API integration / git repository
  04_deploy_notebooks.sql         creates the notebooks from this repo
  05_semantic_view_and_agent.sql  semantic view, agent, compute pool, roles
  99_teardown.sql                 removes everything
notebooks/
  01_snowflake_notebooks.ipynb           SQL + Python in one notebook
  02_snowpark_at_scale.ipynb             Python DataFrames over 20M rows
  03_cortex_ai_clinical_text.ipynb       LLM functions over pathology narratives
  04_train_register_in_snowflake.ipynb   train + register a model, no laptop
  05_register_model_from_git.ipynb       register a git-committed model
  environment.yml                        notebook packages
semantic/
  sv_guardant_variants.yaml       the semantic view as a versioned file
model/
  variant_clf.joblib              RandomForest (registry V1)
  variant_clf_gb.joblib           HistGradientBoosting (registry V2)
tools/
  train_and_register_model.py     train locally and register
  train_second_model.py           train the gradient-boosting variant
  deploy_local_model.py           push a .joblib to the registry as a new version
  deploy_semantic_view.py         deploy the semantic view from its YAML
  build_notebooks.py              regenerates the .ipynb files from plain text
  verify_sql_cells.py             executes every notebook SQL cell
```

## The notebooks

Built to be read in order — each closes by pointing at the next — but any one of
them stands alone.

1. **Snowflake Notebooks** — the same interface, with compute you choose. SQL and
   Python cells side by side, no local environment to maintain.
2. **Snowpark at scale** — pandas-shaped DataFrame code executing as SQL over 20M
   rows. Nothing is pulled down to be processed.
3. **Cortex AI on clinical text** — `AI_EXTRACT`, `AI_CLASSIFY`, `AI_COMPLETE` and
   `AI_AGG` over free-text pathology narratives, without calling an external API.
4. **Train and register a model** — trains inside Snowflake and logs the result to
   the Model Registry, so the training data never moves.
5. **Register a model from git** — the counterpart: Snowflake fetches an existing
   `.joblib` off the git repository stage and registers it, with nothing uploaded
   from a laptop.

Notebooks 4 and 5 run on **container runtime** because `snowflake-ml-python` is
already present there — a notebook created from git cannot select packages from the
Snowsight dropdown for you. The working runtime configuration is recorded in
`.snowflake/settings.json` (currently Python 3.12, runtime V2.9-CPU).

## Deploying models

Three routes reach the registry, and the repo shows all of them:

| | Where training runs | How the model reaches the registry |
|---|---|---|
| **A — via git** | Your machine | Committed here; Snowflake pulls it off the git stage (notebook 5) |
| **B — from your laptop** | Your machine | `log_model` pushes it directly (`tools/deploy_local_model.py`) |
| **C — notebook 4** | Snowflake | Never leaves the platform |

### The recommended path

> **Log the model to the Model Registry directly from wherever you trained it.
> Not git.**

Git holds the code that trains a model; the registry holds the model. A `.joblib`
in a repo gives you no signature, no metrics, no versioning and no access control,
and it is a binary that cannot be meaningfully diffed. The same model in the
registry is a schema-level object with all four, callable from SQL.

Both `.joblib` files are committed here anyway so a clean clone can replay path A.
That is a teaching decision, not a recommendation.

The thing most people miss: **you never upload the file.** `log_model` takes the
in-memory Python object and handles serialization, environment capture and staging.

```python
clf = joblib.load("model/variant_clf_gb.joblib")   # must load in YOUR env first
reg = Registry(session=session, database_name="DEMO", schema_name="GUARDANT_DEMO")
mv  = reg.log_model(clf, model_name="GUARDANT_VARIANT_CLF", version_name="V2",
                    sample_input_data=train_features)   # required for sklearn
```

Four things actually break this:

| Gotcha | Symptom | Fix |
|---|---|---|
| Local env cannot load the pickle | `joblib.load` fails before Snowflake is involved | Pin scikit-learn to a version in Snowflake's channel — 1.5.2 here |
| No `sample_input_data` or `signatures` | `log_model` refuses scikit-learn models outright | Pass a small training frame |
| Model not runnable in a warehouse | `log_model` **fails**, because the default targets both platforms | `target_platforms=["SNOWPARK_CONTAINER_SERVICES"]` for GPU or large models |
| `pip_requirements` with no repository | The warehouse cannot install them | `artifact_repository_map={"pip": "snowflake.snowpark.pypi_shared_repository"}` |

Dependencies are auto-populated from your local environment when targeting a
warehouse, which is exactly why the version pin matters: your machine's environment
becomes the model's contract. Warehouse-deployed models cap at 15 GB.

One deviation to know about: `tools/deploy_local_model.py` sets
`relax_version: False`, where Snowflake defaults to `True`. That was chosen to force
the warehouse to resolve an identical scikit-learn build. **Leave it at the default
in production** — otherwise a channel change can break logging.

If you are running inside a container runtime notebook, pass
`target_platforms=["WAREHOUSE"]` explicitly. There the default is Snowpark Container
Services only, so the model registers successfully and then `MODEL!PREDICT` fails to
resolve from SQL.

### Scoring from SQL

```sql
USE SCHEMA DEMO.GUARDANT_DEMO;   -- model methods resolve against the session schema

WITH m AS MODEL GUARDANT_VARIANT_CLF VERSION V1
SELECT variant_id, m!PREDICT(vaf, read_depth, alt_read_count, mapping_quality)
FROM VARIANT_CALLS WHERE call_filter = 'PASS' LIMIT 10;
```

The model is a schema object, so a role with `USAGE` can score data without a Python
environment and without seeing the model's internals. `READ` additionally exposes
metadata and metrics.

## The semantic view

`semantic/sv_guardant_variants.yaml` is the source of truth. It deploys with
`SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML` and exports back out of the running object
with `SYSTEM$READ_YAML_FROM_SEMANTIC_VIEW`, so the file in git and the object in the
account are the same artifact:

```bash
python3 tools/deploy_semantic_view.py --schema DEMO.GUARDANT_DEMO
```

Redeploying it into a second schema returns byte-identical numbers, which is the
point: a metric defined once is inherited by every consumer — SQL, BI and AI alike.

## The data

A synthetic liquid-biopsy cohort:

| Table | Rows | What it is |
|---|---|---|
| `PATIENTS` | 50,000 | Demographics, primary cancer type, stage |
| `SPECIMENS` | 120,000 | Serial blood draws with assay, tumour fraction, QC |
| `VARIANT_CALLS` | **20,000,000** | Raw pre-filter calls, ~167 per specimen |
| `PATHOLOGY_REPORTS` | 2,000 | Free-text narratives for the Cortex AI notebook |
| `GENE_PANEL` | 60 | Panel definition with targeted-therapy annotations |
| `V_REPORTABLE_VARIANTS` | ~11,000,000 | The analysis-ready join (PASS calls only) |

The shaping is deliberate, not uniform noise:

- Gene mutation frequency follows a realistic long tail (TP53 ≫ KRAS ≫ PIK3CA ≫ …)
- VAF is cubed-skewed, so most calls are low-frequency and a minority are clonal
- Low tumour fraction correlates with QC trouble, as in a real assay
- ~59% of raw calls are `PASS`; the rest are the noise floor the notebooks filter out

20M rows is chosen so that "just pull it into pandas" is genuinely infeasible, while
still generating in about 30 seconds on a MEDIUM warehouse.

## Editing the notebooks

Cell content lives as plain text in `tools/build_notebooks.py`, which keeps it
reviewable in diffs and means a mangled `.ipynb` JSON blob is always recoverable.
Edit that file, then regenerate:

```bash
python3 tools/build_notebooks.py
```

Check the SQL still runs before trusting it:

```bash
python3 tools/verify_sql_cells.py
```

To catch Snowpark and Python errors you have to actually execute the notebooks,
which only Snowflake can do:

```sql
EXECUTE NOTEBOOK DEMO.GUARDANT_DEMO.GUARDANT_01_NOTEBOOKS();
```

If you changed notebooks and want Snowflake to pick them up, push, then re-run
`setup/04_deploy_notebooks.sql`.

## Connecting this repo as a Snowflake Workspace

`setup/03_git_integration.sql` creates the Snowflake-side objects (secret, API
integration, git repository). **The Workspace itself must be created in the Snowsight
UI** — there is no DDL or CLI path for a git-backed Workspace:

> Projects → Workspaces → **From Git repository**

Point it at this repo's HTTPS URL and select the credential the setup script created.

## Troubleshooting

- **Cortex model unavailable in your region** — `AI_COMPLETE` takes a model
  argument; swap `claude-4-sonnet` for another available model, or use the
  `AI_EXTRACT` / `AI_CLASSIFY` cells, which do not name a model.
- **`MODEL!PREDICT` is an unknown function** — you need `USE SCHEMA
  DEMO.GUARDANT_DEMO`; model methods resolve against the session schema.
- **A model version already exists** — registry versions are immutable. Either pick
  a new `version_name` or `ALTER MODEL ... DROP VERSION <v>` first.
- **`joblib.load` fails or warns about versions** — your scikit-learn does not match
  the one that wrote the pickle. Pin to 1.5.2.
- **UDF missing** — re-run `setup/02_udf.sql`.
- **Role restrictions appear not to work** — secondary roles. If `USE ROLE X` seems
  to restrict nothing, run `USE SECONDARY ROLES NONE` first; an inherited
  ACCOUNTADMIN secondary role silently grants everything back.

## Teardown

```bash
snow sql -c <connection> --role ACCOUNTADMIN -f setup/99_teardown.sql
```
