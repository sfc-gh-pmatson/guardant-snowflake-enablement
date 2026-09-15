# Participant Guide — Snowflake Hands-On Lab

Guardant Health · 17 September 2026 · 60 minutes

You will be working in your own private area of Guardant's Snowflake account. You
cannot break anything, and you cannot affect anyone else in the room.

---

## Start here (2 minutes)

1. Open Snowsight and sign in as you normally would.
2. Open a new SQL worksheet.
3. Paste in the whole of **`lab/02_participant_setup.sql`** and run it top to bottom.
4. You should end with `Setup complete` and your own schema name.

**If `USE ROLE GUARDANT_LAB` fails**, you have not been granted the lab role. Put
your hand up — it takes ten seconds to fix.

Then open the workbook notebook: **`notebooks/00_lab_workbook.ipynb`**. Everything
below is in there too, so you can follow along in whichever you prefer.

---

## The two places you will be working

| | What it is | Can you write to it? |
|---|---|---|
| `GUARDANT_LAB.GUARDANT_DEMO` | Shared synthetic dataset, 20M variant calls | No — read only |
| `GUARDANT_LAB.LAB_<your username>` | Your own private schema | Yes — anything you like |

All the data is synthetic. No Guardant patient data is used anywhere in this lab.

---

## The six stations

Each station has a **CHECKPOINT** so you know whether you are keeping up, and an
**ESCAPE** for when you are not. Using an escape is not falling behind — it is
how the lab is designed to work. Falling behind on one station never blocks the
next one.

| # | Station | Time | Where you work |
|---|---|---|---|
| 1 | Notebooks | ~10 min | Workbook notebook |
| 2 | GitHub | ~10 min | Snowsight UI |
| 3 | Cortex Code | ~10 min | Snowsight UI |
| 4 | Snowpark | ~10 min | Workbook notebook |
| 5 | Cortex AI | ~10 min | Workbook notebook |
| 6 | Snowsight | ~3 min | Snowsight UI |

### Station 1 — Notebooks
*"Your Jupyter, but the compute is in Snowflake."*

Run a SQL cell over 20 million rows, hand the result to Python by cell name, and
plot it. Nothing is downloaded.

**Checkpoint:** a bar chart of mutation burden by gene, TP53 longest.

### Station 2 — GitHub
*"Your existing Git workflow, connected."*

Snowsight → **Projects → Workspaces → From Git repository**, pointed at
`https://github.com/sfc-gh-pmatson/guardant-snowflake-enablement.git`. The repo is
public, so no token is needed. Browse the files, make an edit, commit and push
from inside Snowsight.

**Checkpoint:** you can see the repo files and the commit button is live.

### Station 3 — Cortex Code
*"An AI assistant that already knows your schema."*

Open Cortex Code in Snowsight and ask it:

> Using GUARDANT_LAB.GUARDANT_DEMO, write me a Snowpark query that finds the
> patients whose KRAS variant allele frequency increased between two blood draws.

Then: *"Explain what that query does, line by line."*

**Checkpoint:** the query references real column names, not invented ones.

### Station 4 — Snowpark
*"Python DataFrames with no memory ceiling."*

Prove a Snowpark DataFrame is lazy by printing the SQL it generates, aggregate
20M rows, then run a window function over each patient's serial draws to find
rising VAF. Write the result into your own schema.

**Checkpoint:** `MY_ACTIONABLE_COHORT` in your schema, roughly 3–4 million rows.

### Station 5 — Cortex AI
*"The unstructured half of your data becomes queryable."*

2,000 free-text pathology narratives. Use `AI_EXTRACT` to turn prose into
columns, `AI_CLASSIFY` to triage the corpus, and `AI_AGG` to reason across a
whole cohort at once. Every call stays inside Snowflake.

**Checkpoint:** the extraction returns a gene matching the narrative, and
`AI_AGG` gives you three bullets.

### Station 6 — Snowsight
*"Your analyst colleagues get the same data, without code."*

Build a one-tile dashboard on the same tables you just queried from Python.

**Checkpoint:** a bar chart, and no CSV anywhere in the process.

---

## If something goes wrong

**Put your hand up.** Almost every failure in a lab like this is a missing grant
or a regional setting, not something you did. Do not spend three minutes
debugging quietly — that is three minutes of the station gone.

Two failures are expected and are not your fault:

- **GitHub is unreachable** — outbound access may be restricted by policy. Watch
  the facilitator instead.
- **A Cortex call reports an unavailable model** — that is a region setting. Skip
  to the next cell.

---

## Afterwards

Everything is public: **github.com/sfc-gh-pmatson/guardant-snowflake-enablement**

The whole dataset regenerates from SQL in about 30 seconds, so you can rebuild
this lab in any account you have access to.

Your private schema and anything you created in it stays put after the session
unless you ask for it to be removed.
