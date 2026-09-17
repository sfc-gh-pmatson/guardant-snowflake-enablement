# Facilitator Runbook — Guardant Developer Surface Tour

For Peter Matson. Not for distribution.

**Session:** 17 September 2026, 11:00–12:00 PDT · in person · you drive throughout
**Audience:** bioinformatics and data science team. They currently pull data out of
Snowflake into local Jupyter, process it, and write results back.

Run `demo/demo.sql` top to bottom. Every query in it has a measured result in the
comment above it, so you know what right looks like before you press run.

---

## The one thing that breaks this demo

**Your secondary roles are set to `ALL`, and `ACCOUNTADMIN` is one of them.**

So `USE ROLE GUARDANT_ANALYST` restricts nothing. The analyst appears able to read
the raw tables, and the governance argument in segment 7 — the strongest moment in
the session — collapses into a shrug.

You must run `USE SECONDARY ROLES NONE` in the same worksheet before the role
switch. It is already in `demo.sql`. Do not skip it.

Verified both ways: without it the analyst counts all 20,000,000 rows. With it,
`DEMO.GUARDANT_DEMO.VARIANT_CALLS` "does not exist or not authorized".

Reset with `USE SECONDARY ROLES ALL` afterwards or the rest of the script fails.

---

## Timing, and what you cut

Budgeted at ~66 minutes of content in a 60-minute invite. You accepted running to
~70. Attendees with a midday commitment will start leaving at the hour regardless
of what is on screen, so the order is arranged to land the payoff before then.

| # | Segment | Budget | Cut policy |
|---|---|---|---|
| 1 | Overview, CoCo, CoCo Desktop | 8 min | Keep |
| 2 | Claude Code plugin + VS Code | 5 min | **First cut** → 3 min |
| 3 | Notebooks + compute pool | 9 min | Keep |
| 4 | Snowflake-Labs GitHub | 6 min | **Second cut** → 3 min |
| 5 | Local model → Model Registry | 12 min | **Never cut** |
| 6 | Semantic view | 8 min | **Never cut** |
| 7 | Cortex Agent + the share | 8 min | **Never cut** |
| 8 | Commit artifacts, redeploy from git | 10 min | **The drop** if the room thins |

Segments 5, 6 and 7 are the half of this session that no earlier version of the
deck reached. They are the platform argument rather than the tooling argument.

**Checkpoint: at 30 minutes you should be starting segment 5.** If you are not,
announce the change rather than silently dropping things — "I'm going to move
faster through the GitHub piece so we've got proper time on the model and the
semantic layer."

---

## Before the day

| When | What |
|---|---|
| 2 days out | Run `demo/build.sql`. Check every VERIFY result matches. |
| 2 days out | Train the model: `.venv-ml/bin/python tools/train_and_register_model.py`. **Do this off-camera** — it needs a browser OAuth round trip. |
| 1 day out | Open the agent in Snowsight and ask all four sample questions. Note which answers are weak. |
| 1 day out | Rehearse segment 7 with `USE SECONDARY ROLES NONE` and confirm the error appears. |
| Morning of | Resume `GUARDANT_NOTEBOOK_POOL`, confirm `ACTIVE`. Run `SELECT 1` to wake the warehouse. |
| Morning of | Confirm `pct_flagged` is ~64% and **not 0.0%** (see build.sql VERIFY). |

The local Python environment is a prerequisite, not a nicety:

```bash
uv venv --python 3.11 .venv-ml
VIRTUAL_ENV=.venv-ml uv pip install "snowflake-ml-python==1.9.2" \
    "scikit-learn==1.5.2" "joblib==1.5.3" pandas
```

Your system Python is 3.14 and cannot run `snowflake-ml-python` at all. The
scikit-learn pin is 1.5.2 because `snowflake-ml-python` 1.9.2 requires `<1.6` and
Snowflake's Anaconda channel has 1.5.2 — so the version that writes the pickle is
the version that reads it.

---

## The frame to open with

Say this before segment 1, in roughly these words:

> "Today you query Snowflake, pull the answer down to your laptop, work on it in
> pandas, and push results back. Everything in the next hour is about deleting the
> middle two steps. Not replacing your tools — your notebook, your Python, your
> Git. Just moving where the work happens."

Every segment is a variation on that sentence.

---

## Segment notes

### 3 — Notebooks + compute pool
The moment that lands is a SQL cell being addressable from Python **by cell name**,
with no connector and no credentials. Pause there. Say the numbers: 20 million rows
scanned, 15 rows returned.

Two pools exist on purpose. You `CREATE` a throwaway one live so the room sees the
statement; the notebook runs on a pool you warmed earlier. Say so — "this takes a
couple of minutes to come up, so the notebook I'm about to open is already attached
to one I started earlier." That is honest and costs no dead air.

**Do not claim the table is too big for a laptop on storage grounds.** It is 0.304 GB
compressed. The argument is row count, the uncompressed pandas footprint, and that
they do this repeatedly. If someone checks the size and you have overclaimed, you
lose the room.

### 4 — Snowflake-Labs
Be accurate about what is in that repo: notebooks, scripts, a requirements file.
**No data files** — its loader stages Excel from S3. So what you pull from the repo
is code. Do not say "and here's the data coming from GitHub", because someone will
look. Frame it as the resource plus the mechanic, and point forward to segment 8 for
the write direction.

### 5 — Local model → Model Registry
Three things to say unprompted, because this audience will find them:

1. This is **synthetic** data, so any model is partly learning the generator. The
   segment is about registry and server-side scoring mechanics, not model quality.
2. AUC is ~0.69 and it flags 64% of calls to catch 98% of the pathogenic ones. That
   is a recall-first triage screen. Do not oversell it. Prefer the
   `PREDICT_PROBA` ranking query (5c) over the binary label.
3. **The first version of this model scored AUC 1.0** — because the label I chose
   was derived from exactly the four features I gave it. Textbook leakage. Saying
   you caught it buys more credibility than a clean number would have.

#### The recommended path, if they ask

They will ask, because their instinct will be that the model belongs in git next to
the code. The answer to give:

> **Log it to the Model Registry directly from wherever you trained it. Not git.**

Git holds the code that trains a model. The registry holds the model. A `.joblib`
committed to a repo gives you no signature, no metrics, no versioning and no access
control — and a binary that bloats history and cannot be meaningfully diffed. The
same model in the registry is a schema-level object with all four, callable from SQL.

Both `.joblib` files are committed in this repo anyway, so a clean clone can replay
either path. That is a teaching decision, not a recommendation — say so if it comes up.

The minimal shape, and the thing people miss is that **you never upload the file** —
`log_model` takes the in-memory Python object and handles serialization, environment
capture and staging:

```python
clf = joblib.load("model/variant_clf_gb.joblib")   # must load in YOUR env first
reg = Registry(session=session, database_name="DEMO", schema_name="GUARDANT_DEMO")
mv  = reg.log_model(clf, model_name="GUARDANT_VARIANT_CLF", version_name="V2",
                    sample_input_data=train_features)   # required for sklearn
```

Four things actually break this:

| Gotcha | Symptom | Fix |
|---|---|---|
| Local env cannot load the pickle | `joblib.load` fails before Snowflake is involved | Pin sklearn to a version in Snowflake's channel — 1.5.2 here |
| No `sample_input_data` or `signatures` | `log_model` refuses sklearn models outright | Pass a small training frame |
| Model not runnable in a warehouse | `log_model` **fails**, since the default targets both | `target_platforms=["SNOWPARK_CONTAINER_SERVICES"]` for GPU or large models |
| `pip_requirements` with no repository | Warehouse cannot install them | `artifact_repository_map={"pip": "snowflake.snowpark.pypi_shared_repository"}` |

Dependencies are auto-populated from the local environment when targeting a
warehouse, which is exactly why the version pin matters: your machine's environment
becomes the model's contract. Warehouse-deployed models cap at 15 GB.

One deviation to own: `tools/deploy_local_model.py` sets `relax_version: False`,
where Snowflake defaults to `True`. That was chosen for demo determinism — it forces
the warehouse to resolve the identical sklearn build. Tell them to leave it at the
default in production, because a channel change would otherwise break logging.

#### Path C — never touches a laptop (notebook 4)

`GUARDANT_04_MODEL_REGISTRY`, run from Snowsight, trains a scaled
`LogisticRegression` and registers it as **V3**. Use this when someone objects that
paths A and B both still start on a laptop — here the training data never moves at
all.

Two details in that notebook are worth showing on screen rather than skipping:

- It runs on **container runtime**, where `snowflake-ml-python` is already present,
  so nothing has to be picked in the Packages dropdown. A notebook deployed from git
  cannot select packages for you.
- Because it is container runtime, `log_model` would default to **SPCS only**, and
  `MODEL!PREDICT` from SQL would then fail to resolve. The notebook passes
  `target_platforms=["WAREHOUSE"]` explicitly. This is a good "the default is not
  always what you want" moment.

Safe to re-run: it drops an existing V3 rather than colliding on the version name.

After it runs, `GUARDANT_VARIANT_CLF` has three versions that arrived three
different ways and are all called identically from SQL. That is the segment's
closing line.

### 6 — Semantic view
The question that does the work: *"does 'reportable' mean the same thing in every
analysis you ship today?"* The answer is usually no, and that is the argument.

### 7 — Cortex Agent and the share ★
Demo it, do not present it. Snowsight → AI & ML → Agents → "Ask the Variant Cohort".

Then the governance pair, which is the strongest single screen in the session: the
analyst role **can** query the semantic view and **cannot** read the tables under
it. Show the error. Say:

> "The analyst gets the metrics and the agent, and never gets the raw table. The
> definition of 'reportable' is enforced by the engine, not by whoever wrote the
> notebook. That's the difference between publishing a number and publishing a
> definition."

### 8 — Commit and redeploy
Get ahead of the obvious objection about the model binary:

> "Committing a model to git is normally an anti-pattern — the registry is the
> artifact store. I'm doing it to show you the handoff boundary: I trained it, you
> deploy it, git is the seam."

The proof point is 8b: the same YAML file redeployed into a different schema returns
byte-identical numbers (98.616269 / 98.597465 / 98.570595). The file, not the
click-path, is the source of truth.

**Not built:** the notebook that reads the model off the git stage and re-registers
it. The artifact *is* committed and *is* visible to Snowflake as a stage file
(133,021 bytes, verified). Describe the path, show the file on the stage, and do not
pretend to run it.

---

## Triage

| Symptom | Cause | Fix |
|---|---|---|
| Analyst can read base tables | Secondary roles active | `USE SECONDARY ROLES NONE` |
| `pct_flagged` is 0.0% | Registry holds the unbalanced model | Re-run the training script |
| Model registration "succeeds" but nothing changes | `log_model` version collision, swallowed | Script now drops the model first |
| Notebook won't start | Compute pool suspended or STARTING | Resume it; wait for ACTIVE |
| First query slow | Cold warehouse | Expected. Pre-warm with `SELECT 1` |
| Agent answers vaguely | Question outside the semantic view | Re-ask using a sample question |
| Git fetch returns "up to date" after a push | Already fetched | Harmless — check the stage `sha1` |
| `GET_DDL('AGENT', ...)` errors | Not a valid object type | Use `DESCRIBE AGENT` |

---

## Close

Close on their workflow, not the product list:

> "You've seen a model trained on a laptop score twenty million rows where the data
> lives, a definition of 'reportable' that an analyst and an AI agent both inherit,
> and both of those artifacts living in git like any other code. Nothing about your
> tools changed."

Two follow-ups:

1. A working session on one real Guardant use case
2. A deep dive on whichever segment drew the most questions — **note which**

Take-home: the repo is public, and `lab/` is a complete self-serve hands-on lab if
they want to run it themselves.

    github.com/sfc-gh-pmatson/guardant-snowflake-enablement

---

## After the session

Run the SUSPEND section of `demo/teardown.sql` within minutes. Compute pools bill
while ACTIVE whether or not anything is running on them.
