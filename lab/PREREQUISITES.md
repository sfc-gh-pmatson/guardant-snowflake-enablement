# Prerequisites — Hands-On Lab in Guardant's Account

Six participants will be running this themselves, in Guardant Health's own
Snowflake account, during a 60-minute in-person session.

**Everything in this document needs to be settled before the session, not on the
day.** The failure mode this exists to prevent is six people watching a red error
message while someone hunts for an admin.

---

## Step 1 — Run the preflight (do this first, ideally a week out)

```bash
snow sql -c <guardant-connection> --role <admin-role> -f lab/00_preflight_check.sql
```

Every statement is read-only. It creates nothing. Record the answers below and
send them to Peter Matson before the session.

| Check | Question | Answer | Blocker if it fails? |
|---|---|---|---|
| 1 | Region and edition | | Cortex needs Enterprise+ |
| 2 | Does the admin role have CREATE DATABASE / WAREHOUSE / ROLE? | | Yes — see Step 2 |
| 3 | Are Notebooks available? | | **Yes — 3 of 6 stations are notebooks** |
| 4a | Does `AI_COMPLETE('claude-4-sonnet', …)` work? | | No — swap the model |
| 4b–d | Do AI_EXTRACT / AI_CLASSIFY / AI_AGG work? | | Yes for the Cortex station |
| 5 | Is outbound access to github.com permitted? | | No — demo that station instead |
| 6 | Is Cortex Code visible in Snowsight? | | No — demo that station instead |
| 7 | Is a SMALL+ warehouse available for six concurrent users? | | Yes — six on an XSMALL will queue |

---

## Step 2 — Privileges the setup role needs

The admin running `lab/01_admin_setup.sql` needs, on the account:

- `CREATE DATABASE` — or an existing database they own, plus `CREATE SCHEMA` on it
- `CREATE WAREHOUSE` — or an existing SMALL-or-larger warehouse the six can use
- `CREATE ROLE` and `GRANT ROLE` — to create `GUARDANT_LAB` and give it to six people

In most accounts `SYSADMIN` covers the first two and `USERADMIN` covers the
third. `ACCOUNTADMIN` covers all of it but is usually unnecessary.

**Participants themselves need almost nothing.** They need the `GUARDANT_LAB`
role and a Snowsight login. They do not need `CREATE SCHEMA` — the setup script
installs a stored procedure that creates each person's private schema on their
behalf, running with owner's rights.

If creating a database, warehouse, or role is not permitted at all, tell Peter:
the lab can be retargeted at an existing database and warehouse by editing the
variables at the top of `lab/01_admin_setup.sql`.

---

## Step 3 — Collect the six usernames

The setup script grants the lab role to named users. Have these ready:

```
1. ________________  4. ________________
2. ________________  5. ________________
3. ________________  6. ________________
```

Include anyone who might join late. Granting a role to a spare user costs
nothing; interrupting the session to add one costs several minutes.

---

## Step 4 — Run the setup

```bash
# 1. Infrastructure, lab role, per-participant schema procedure
snow sql -c <guardant-connection> --role <admin-role> -f lab/01_admin_setup.sql

# 2. The synthetic dataset (~20M rows, about 30s on a MEDIUM warehouse)
snow sql -c <guardant-connection> --role <admin-role> -f setup/01_synthetic_data.sql

# 3. The confidence-score UDF used in the Snowpark station
snow sql -c <guardant-connection> --role <admin-role> -f setup/02_udf.sql
```

Then verify as described at the end of `lab/01_admin_setup.sql`.

### About the data

All of it is synthetic and generated in-database from `GENERATOR` and `RANDOM`.
There are **no data files** in this repo and **no Guardant data is used**. It is a
plausible liquid-biopsy shape — patients, serial blood draws, ~20M raw variant
calls, and 2,000 free-text pathology narratives — but every value is invented.

Worth saying out loud to whoever approves this: nothing here reads Guardant
patient data, and the dataset can be dropped in one statement afterwards.

Storage is roughly 0.3 GB compressed. Generation and a one-hour session for six
people on a MEDIUM warehouse is a negligible amount of credit.

---

## Step 5 — If the GitHub station is blocked

The GitHub station uses this public repo as its own subject. It needs an
`API INTEGRATION` reaching `https://github.com/sfc-gh-pmatson`. In a regulated
healthcare account this is the single most likely thing to be refused.

Because the repo is **public**, no credential or secret is required — which
removes the usual objection. But egress may still be blocked by policy.

If it is refused, that station becomes a demo from Peter's account rather than
hands-on, and the participants watch. Nothing else in the lab depends on it.

---

## Step 6 — Teardown

After the session, all of it comes out in three statements:

```sql
DROP DATABASE IF EXISTS GUARDANT_LAB;          -- or just the schemas, if retargeted
DROP WAREHOUSE IF EXISTS GUARDANT_LAB_WH;
DROP ROLE IF EXISTS GUARDANT_LAB;
```

---

## Known scope risk

Six hands-on topics in 60 minutes will overrun. Hands-on runs roughly three
times slower than a demo, and that is before questions.

The workbook is built to absorb this: every station has a checkpoint and a
paste-and-move-on escape, so a participant who falls behind on one station still
starts the next one in the right place. But expect to reach four stations
properly rather than six, and decide in advance which two you are willing to
compress. `lab/FACILITATOR_RUNBOOK.md` names the recommended cut points.
