# Facilitator Runbook — Guardant Hands-On Lab

For Peter Matson. Not for distribution to participants.

**Session:** 17 September 2026, 11:00–12:00 PDT · 6 participants, hands-on · Guardant's own Snowflake account

---

## The honest timing problem

Six hands-on stations do not fit in 60 minutes. Hands-on runs roughly three times
slower than demoing, and that is before questions or a single login problem.

The stated plan is 53 minutes of station time in a 60-minute slot with
introductions. Realistically you will complete **four stations properly**.

This is fine, provided you choose which two to compress **before** you walk in
rather than discovering it at minute 45. Two things are true and worth holding
onto: a room that does two stations properly leaves convinced, and a room that
half-does six leaves confused.

### Recommended cut order

Cut from the bottom up:

1. **Station 3 (Cortex Code)** — cut to a 3-minute demo on your screen. It is the
   most impressive to watch and the least necessary to do yourself.
2. **Station 2 (GitHub)** — cut to a 3-minute demo. It may be blocked by policy
   anyway, in which case the decision is made for you.

**Never cut Stations 1, 4, or 5.** They are the actual argument: notebooks in the
platform, Snowpark at scale, AI on unstructured text. Station 6 is only 3 minutes
and lands the governance point, so keep it.

### If you are running behind at the 30-minute mark

You should have finished Station 1 and be inside Station 4. If you are not,
announce the change rather than silently dropping things:

> "I'm going to demo the GitHub and Cortex Code pieces rather than have you do
> them, so we've got proper time on Snowpark and the AI functions."

---

## Before the day

| When | What |
|---|---|
| A week out | Guardant admin runs `lab/00_preflight_check.sql`, sends you the results |
| A week out | Confirm the three likely blockers: Notebooks enabled, Cortex model available, GitHub egress permitted |
| A week out | Collect six usernames (`lab/PREREQUISITES.md` step 3) |
| 2 days out | Admin runs `lab/01_admin_setup.sql`, then `setup/01_synthetic_data.sql`, then `setup/02_udf.sql` |
| 2 days out | Verify: `SELECT COUNT(*) FROM GUARDANT_LAB.GUARDANT_DEMO.VARIANT_CALLS` = 20,000,000 |
| 1 day out | Rehearse the whole workbook yourself, end to end, as the `GUARDANT_LAB` role — not as ACCOUNTADMIN |
| Morning of | Resume `GUARDANT_LAB_WH` with `SELECT 1` so the first participant query is not a cold start |
| Morning of | Send participants the guide and the setup script in advance |

**Rehearse as the participant role, not as an admin.** Almost every hands-on lab
failure is a grant that the facilitator's role happens to have and the
participants' role does not.

You can rehearse in your own demo account with `lab/99_rehearsal_shortcut.sql`,
which stands up `GUARDANT_LAB` over the existing `DEMO.GUARDANT_DEMO` dataset in
about ten seconds.

---

## Room open (first 5 minutes)

Do not start with slides. Start by getting all six people set up, because setup
failures discovered at minute 20 cost you a station.

1. "Open Snowsight, new worksheet, paste this script, run it."
2. Walk the room. Look for anyone whose `USE ROLE GUARDANT_LAB` failed.
3. Only when all six show `Setup complete`, start talking.

Ask out loud: **"Everyone seeing 20 million?"** Wait for six answers. Do not
proceed on silence.

---

## The framing to open with

Say this before Station 1, in roughly these words:

> "Today you query Snowflake, pull the answer down to your laptop, work on it in
> pandas, and push results back. Everything we do in the next hour is about
> deleting the middle two steps. Not replacing your tools — your notebook, your
> Python, your Git. Just moving where the work happens."

That is the whole session. Every station is a variation on it.

---

## Station-by-station notes

### Station 1 — Notebooks (~10 min)
**The moment that lands:** `sql_s1_burden.to_pandas()`. A SQL cell addressable
from Python by name, with no connector and no credentials. Pause there.

Say the numbers out loud: 20 million rows scanned, 15 rows returned.

**Do not claim** the table is too big for a laptop on storage grounds — it is
only 0.3 GB compressed. The argument is row count, the uncompressed footprint,
and the fact that they are doing this repeatedly. If someone checks the size and
you have overclaimed, you lose the room.

### Station 2 — GitHub (~10 min, first cut candidate)
The repo is public, so there is no token step — which removes the objection you
would otherwise get about credentials in a regulated environment. Say so.

If egress is blocked: name it as a platform policy, not a product limitation,
and move on quickly. Do not litigate it in the room.

### Station 3 — Cortex Code (~10 min, first cut candidate)
The tie-in that matters to a bioinformatics lead is onboarding: a new joiner can
ask what a query does instead of finding whoever wrote it. Say that explicitly —
it is a headcount argument, not a developer-convenience argument.

### Station 4 — Snowpark (~10 min, never cut)
**The moment that lands:** printing the generated SQL from a DataFrame. It makes
"lazy" concrete rather than abstract.

The window function on serial draws is the genomics-credible bit — rising VAF
across blood draws is a real clinical question, and it is the operation that
hurts most in pandas because it needs the whole partition in memory.

Expect a question about UDF governance. Answer: it is a schema-level object,
versioned, granted like a table.

### Station 5 — Cortex AI (~10 min, never cut)
**Make the governance point out loud:** no report text left the account. In
healthcare that is often the deciding factor, and it will not occur to them
unless you say it.

`AI_AGG` is the one with no laptop equivalent at all — it reasons over a group of
rows, not row by row. Lead with that if time is short.

### Station 6 — Snowsight (~3 min, keep)
The point is not the chart. It is that the dashboard reads the same tables under
the same permissions. One copy of the data, one set of controls, no CSV.

---

## Triage — failures and the fix

| Symptom | Cause | Fix |
|---|---|---|
| `USE ROLE GUARDANT_LAB` fails | Role not granted to that user | `GRANT ROLE GUARDANT_LAB TO USER "<name>"` |
| Count query returns nothing | Missing SELECT grant | Re-run the grant block in `01_admin_setup.sql` §3 |
| `CLAIM_MY_LAB_SCHEMA` not found | Procedure usage not granted | `GRANT USAGE ON PROCEDURE …CLAIM_MY_LAB_SCHEMA() TO ROLE GUARDANT_LAB` |
| Cannot create a table in own schema | Claim procedure not run | Re-run step 3 of the participant script |
| Everything is slow for everyone | Six users on one small warehouse | Resize `GUARDANT_LAB_WH` up — it is one statement, do it live |
| First query of the day is slow | Cold warehouse | Expected. Pre-warm with `SELECT 1` |
| `AI_COMPLETE` unknown model | Model not available in region | Swap to `llama3.1-70b`, or enable cross-region inference |
| Chart cell fails | `matplotlib` missing from the notebook environment | Skip it; the table above makes the point |
| GitHub fetch fails | Egress policy | Demo it from your account |
| Someone is three stations behind | Normal | Point them at that station's ESCAPE cell |

**Warehouse resize is your main live lever.** If the room is queueing:

```sql
ALTER WAREHOUSE GUARDANT_LAB_WH SET WAREHOUSE_SIZE = 'LARGE';
```

---

## Close (last 5 minutes)

Do not close on the product list. Close on their own workflow:

> "You pulled 20 million rows' worth of analysis without downloading anything,
> ran a window function that would have hit your laptop's memory, and queried
> free text that you currently read by hand. All in your own account, on your own
> data model, with your own permissions."

Then land the two follow-ups from the deck:

1. A longer hands-on workshop on one real Guardant use case
2. A deep dive on whichever station drew the most questions — note which that was

Tell them the repo is public and the dataset regenerates in 30 seconds, so they
can keep going without you.

---

## After the session

- Note which station drew the most questions — that is your next meeting
- Decide whether to leave the participant schemas in place (default: yes, they
  cost nothing and people keep experimenting)
- Teardown, when wanted, is in `lab/PREREQUISITES.md` step 6
