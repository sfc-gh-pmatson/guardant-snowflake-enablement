-- =====================================================================
--  GUARDANT HEALTH — DEVELOPER SURFACE TOUR
--  17 Sep 2026 · bioinformatics + data science team
--
--  Run this top to bottom during the session. Every query has been executed
--  and its measured result is in the comment above it, so you know what
--  "right" looks like before you press run.
--
--  Companion files:  runbook.md    — talk track, timings, cut order
--                    build.sql     — creates every object from scratch
--                    teardown.sql  — remove / suspend
--
--  ###################################################################
--  ##  THE ONE THING THAT BREAKS THIS DEMO                          ##
--  ##                                                                ##
--  ##  Your secondary roles are set to ALL, and ACCOUNTADMIN is one  ##
--  ##  of them. So `USE ROLE GUARDANT_ANALYST` RESTRICTS NOTHING —   ##
--  ##  the analyst appears able to read the raw tables, and the      ##
--  ##  entire governance argument in segment 7 collapses.           ##
--  ##                                                                ##
--  ##  You MUST run `USE SECONDARY ROLES NONE` in the same worksheet ##
--  ##  before the segment 7 role switch. It is in the script below.  ##
--  ##  Do not skip it. VERIFIED: without it the analyst counts all   ##
--  ##  20,000,000 rows; with it the table "does not exist".          ##
--  ###################################################################
--
--  ALL DATA IS SYNTHETIC. No Guardant patient data is used anywhere.
-- =====================================================================


-- =====================================================================
--  PRE-FLIGHT — run 10 minutes before, not during
-- =====================================================================
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE GUARDANT_DEMO_WH;
USE SCHEMA DEMO.GUARDANT_DEMO;

-- Wake the warehouse so the first query of the session is not a cold start.
SELECT 1 AS warm;

-- Pre-warm the compute pool the notebook runs on. This is the segment 3
-- insurance policy: a pool takes MINUTES to reach ACTIVE, so the pool you
-- demo CREATE on is NOT the pool your notebook uses.
-- Expect state = ACTIVE or IDLE before you start.
SHOW COMPUTE POOLS LIKE 'GUARDANT_NOTEBOOK_POOL';

-- Everything present? Expect 20,000,000 / 1 semantic view / 1 agent / 1 model.
SELECT (SELECT COUNT(*) FROM DEMO.GUARDANT_DEMO.VARIANT_CALLS) AS variant_calls;
SHOW SEMANTIC VIEWS LIKE 'SV_GUARDANT_VARIANTS' IN SCHEMA DEMO.GUARDANT_DEMO;
SHOW AGENTS LIKE 'GUARDANT_VARIANT_AGENT' IN SCHEMA DEMO.GUARDANT_DEMO;
SHOW MODELS LIKE 'GUARDANT_VARIANT_CLF' IN SCHEMA DEMO.GUARDANT_DEMO;


-- =====================================================================
--  SEGMENT 1 — SNOWFLAKE OVERVIEW, CoCo AND CoCo DESKTOP   (~8 min)
--  Mostly UI. No SQL. See runbook.md for the talk track.
--
--  OPEN WITH THE FRAME, in roughly these words:
--    "Today you query Snowflake, pull the answer down to your laptop, work
--     on it in pandas, and push results back. Everything in the next hour
--     is about deleting the middle two steps. Not replacing your tools —
--     your notebook, your Python, your Git. Just moving where work happens."
--
--  ASK: how big does a typical analysis extract get, and how long does the
--       environment setup take a new starter?
-- =====================================================================


-- =====================================================================
--  SEGMENT 2 — CLAUDE CODE PLUGIN + VS CODE EXTENSION      (~5 min)
--  Your laptop. No SQL. FIRST CUT CANDIDATE — see runbook.md.
--
--  The point that lands with this audience is onboarding, not autocomplete:
--  a new joiner asks what a query does instead of finding whoever wrote it.
-- =====================================================================


-- =====================================================================
--  SEGMENT 3 — NOTEBOOKS + COMPUTE POOL                    (~9 min)
-- =====================================================================
USE ROLE ACCOUNTADMIN;

-- 3a. The mechanic, shown honestly. This creates a SECOND, throwaway pool so
--     the room sees the statement and the state transition without watching a
--     spinner for three minutes.
--     SAY THIS: "this takes a couple of minutes to come up, so the notebook
--     I'm about to open is already attached to one I started earlier."
CREATE COMPUTE POOL IF NOT EXISTS GUARDANT_DEMO_POOL_THROWAWAY
  MIN_NODES = 1 MAX_NODES = 1
  INSTANCE_FAMILY = CPU_X64_XS
  AUTO_SUSPEND_SECS = 300
  COMMENT = 'Created live during the session to show the mechanic. Dropped in teardown.sql.';

-- STARTING -> ACTIVE. Point at instance_family and auto_suspend_secs.
SHOW COMPUTE POOLS LIKE 'GUARDANT_%';

-- 3b. Now open the notebook in Snowsight (it runs on the PRE-WARMED pool):
--       Projects -> Notebooks -> GUARDANT_01_NOTEBOOKS
--     Run the first few cells. The moment worth pausing on is the SQL cell
--     being handed to Python BY CELL NAME, with no connector and no
--     credentials: sql_gene_burden.to_pandas()
--
--     MEASURED: 20,000,000 rows scanned, 15 rows returned to Python.
--
--  DO NOT CLAIM the table is too big for a laptop on storage grounds — it is
--  only 0.304 GB compressed. The argument is row count, the uncompressed
--  pandas footprint, and that they do this repeatedly. If someone checks the
--  size and you have overclaimed, you lose the room.
--
--  ASK: what is the largest dataframe they currently hold in memory?
-- =====================================================================


-- =====================================================================
--  SEGMENT 4 — SNOWFLAKE-LABS GITHUB                       (~6 min)
--  SECOND CUT CANDIDATE.
--
--  Two git repository objects, each with one job:
--    GUARDANT_LABS_REPO       - read-only, the quickstarts resource
--    GUARDANT_ENABLEMENT_REPO - yours, writable, where segment 8 deploys from
-- =====================================================================
USE ROLE ACCOUNTADMIN;

-- 4a. In the browser: github.com/Snowflake-Labs — this is the resource. Say
--     they can send their team here; it is where the quickstarts live.

-- 4b. Wire it in. No credential: the repo is public.
ALTER GIT REPOSITORY DEMO.GUARDANT_DEMO.GUARDANT_LABS_REPO FETCH;

-- Snowflake can now browse the repo's contents as a stage.
LS @DEMO.GUARDANT_DEMO.GUARDANT_LABS_REPO/branches/main/;

--  BE ACCURATE ABOUT WHAT IS IN THERE. This repo contains notebooks, scripts
--  and a requirements.txt — NO data files. Its loader stages Excel from S3.
--  So what you pull from the repo is CODE. Do not say "and here's the data
--  coming from GitHub", because someone will look.
--
--  SAY THIS: "the mechanic is the point — any repo, public or private,
--  becomes a stage your notebooks and scripts can run from. In segment 8
--  I'll use my own repo to show the write direction."
--
--  ASK: where does their notebook code live today, and is it reviewed?
-- =====================================================================


-- =====================================================================
--  SEGMENT 5 — LOCAL MODEL -> MODEL REGISTRY               (~12 min)
--  NEVER CUT THIS.
--
--  Run tools/train_and_register_model.py on your laptop BEFORE the session
--  (it needs a browser OAuth round trip and you do not want that on screen).
--  MEASURED: 50,000 rows sampled, 7.9% pathogenic, holdout ROC AUC 0.6896,
--            predicted-positive rate 63.0%, model file 130 KB.
-- =====================================================================
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE GUARDANT_DEMO_WH;
USE SCHEMA DEMO.GUARDANT_DEMO;

-- 5a. The model is a first-class schema object, versioned, with metadata.
--     Point at: functions (PREDICT, PREDICT_PROBA, EXPLAIN), the sklearn
--     version, and runnable_in = WAREHOUSE, SNOWPARK_CONTAINER_SERVICES.
SHOW VERSIONS IN MODEL DEMO.GUARDANT_DEMO.GUARDANT_VARIANT_CLF;

-- 5b. ★ THE PAYOFF — the model trained on a laptop now scores 11.8M rows
--     where the data already is. No extract, no upload, no serving container.
--     MEASURED: 11,831,375 rows scored. 63.8% flagged, 7.7% actually
--               pathogenic, RECALL 98.4%.
WITH scored AS (
  SELECT clinical_significance,
         GUARDANT_VARIANT_CLF!PREDICT(vaf, read_depth, alt_read_count, mapping_quality)
           :output_feature_0::INT AS flagged
  FROM DEMO.GUARDANT_DEMO.VARIANT_CALLS
  WHERE call_filter = 'PASS'
)
SELECT COUNT(*)                                                      AS rows_scored,
       ROUND(100.0 * SUM(flagged) / COUNT(*), 1)                     AS pct_flagged,
       ROUND(100.0 * AVG(IFF(clinical_significance='Pathogenic',1,0)), 1) AS pct_actually_pathogenic,
       ROUND(100.0 * SUM(IFF(flagged=1 AND clinical_significance='Pathogenic',1,0))
             / NULLIF(SUM(IFF(clinical_significance='Pathogenic',1,0)),0), 1) AS recall_pct
FROM scored;

-- 5c. The better framing for this audience: use the PROBABILITY to rank calls
--     for human review, rather than a hard label. High recall, low precision
--     is a triage screen, not a diagnosis.
--     MEASURED: top scores ~0.599 on the sample checked.
SELECT gene_symbol,
       ROUND(vaf * 100, 3) AS vaf_pct,
       read_depth,
       clinical_significance,
       ROUND(GUARDANT_VARIANT_CLF!PREDICT_PROBA(vaf, read_depth, alt_read_count, mapping_quality)
             :output_feature_1::FLOAT, 4) AS pathogenicity_score
FROM DEMO.GUARDANT_DEMO.VARIANT_CALLS
WHERE call_filter = 'PASS'
QUALIFY ROW_NUMBER() OVER (ORDER BY pathogenicity_score DESC) <= 15
ORDER BY pathogenicity_score DESC;

--  ###  SAY ALL THREE OF THESE UNPROMPTED. This audience will find them.  ###
--   1. This is SYNTHETIC data, so any model is partly learning the generator.
--      The segment is about registry + server-side scoring mechanics, not
--      model quality.
--   2. AUC is ~0.69 and it flags 64% of calls to catch 98% of the pathogenic
--      ones. That is a recall-first triage screen. Do not oversell it.
--   3. My FIRST attempt predicted "is this call reportable" and scored AUC
--      1.0 — because that label is derived from exactly those four columns.
--      Textbook leakage. Telling them you caught it buys more credibility
--      than a clean number would have.
--
--  ASK: what would they actually want to predict, and where does the model
--       they use today run?
-- =====================================================================


-- =====================================================================
--  SEGMENT 6 — SEMANTIC VIEW                               (~8 min)
--  NEVER CUT THIS.
-- =====================================================================
USE ROLE ACCOUNTADMIN;

-- 6a. A schema-level object, not YAML on a stage, so it inherits RBAC,
--     sharing and the catalog. 4 logical tables, 3 relationships.
DESCRIBE SEMANTIC VIEW DEMO.GUARDANT_DEMO.SV_GUARDANT_VARIANTS;

-- 6b. "Reportable" has ONE definition here instead of one per notebook.
--     MEASURED: NSCLC 8,581 patients / 1,100,091 calls / 9.626% median VAF
--               Colorectal 4,415 / 568,884 / 9.618
--               Breast 3,337 / 436,073 / 9.618
SELECT * FROM SEMANTIC_VIEW(
  DEMO.GUARDANT_DEMO.sv_guardant_variants
  DIMENSIONS patients.cancer_type
  METRICS patients.patient_count, variants.reportable_calls, variants.median_vaf_pct
  WHERE variants.is_reportable AND gene_panel.is_actionable
) ORDER BY reportable_calls DESC LIMIT 8;

-- 6c. A metric that spans two logical tables, defined once.
--     MEASURED: PALO-ALTO 10.547% TF / 98.616 calls per specimen / 92.968% QC
--               REDWOOD-CITY 10.447 / 98.597 / 92.563
--               SAN-DIEGO 10.424 / 98.571 / 92.954
SELECT * FROM SEMANTIC_VIEW(
  DEMO.GUARDANT_DEMO.sv_guardant_variants
  DIMENSIONS specimens.lab_site
  METRICS specimens.avg_tumor_fraction_pct, reportable_calls_per_specimen,
          specimens.qc_pass_rate_pct
) ORDER BY lab_site;

--  ASK: does "reportable" mean the same thing in every analysis they ship
--       today? The answer is usually no, and that is the whole argument.
-- =====================================================================


-- =====================================================================
--  SEGMENT 7 — CORTEX AGENT, AND THE SHARE  ★              (~8 min)
--  NEVER CUT THIS. DEMO IT, DO NOT PRESENT IT.
--
--  PRIMARY PATH: Snowsight -> AI & ML -> Agents -> "Ask the Variant Cohort"
--    Ask: "How many patients have an actionable alteration, by cancer type?"
--    Then: "Which genes are most frequently altered, and their median VAF?"
--
--  The agent is bounded by the semantic view, so it inherits the same single
--  definition of reportable and actionable that segment 6 established.
-- =====================================================================
USE ROLE ACCOUNTADMIN;
SHOW AGENTS LIKE 'GUARDANT_VARIANT_AGENT' IN SCHEMA DEMO.GUARDANT_DEMO;

-- 7a. ###  NOW THE GOVERNANCE POINT. READ THE WARNING AT THE TOP FIRST.  ###
--     USE SECONDARY ROLES NONE is mandatory. Without it ACCOUNTADMIN is
--     active as a secondary role and this proves nothing.
USE ROLE GUARDANT_ANALYST;
USE SECONDARY ROLES NONE;                          -- <<< DO NOT SKIP

-- The analyst CAN use the governed semantic layer.
-- VERIFIED as GUARDANT_ANALYST: KRAS 632,641 / PIK3CA 483,818 / EGFR 409,715
SELECT CURRENT_ROLE() AS acting_as, * FROM SEMANTIC_VIEW(
  DEMO.GUARDANT_DEMO.sv_guardant_variants
  DIMENSIONS variants.gene
  METRICS variants.reportable_calls, variants.median_vaf_pct
  WHERE variants.is_reportable AND gene_panel.is_actionable
) ORDER BY reportable_calls DESC LIMIT 5;

-- 7b. And CANNOT read the tables underneath it.
--     VERIFIED: "Object 'DEMO.GUARDANT_DEMO.VARIANT_CALLS' does not exist or
--                not authorized."  <-- this error IS the demo. Show it.
SELECT COUNT(*) FROM DEMO.GUARDANT_DEMO.VARIANT_CALLS;

--  THE ARGUMENT, say it out loud:
--    "The analyst gets the metrics and the agent, and never gets the raw
--     table. The definition of 'reportable' is enforced by the engine, not by
--     whoever wrote the notebook. That is the difference between publishing a
--     number and publishing a definition."
--
--  Reset before continuing, or the rest of the script fails:
USE SECONDARY ROLES ALL;
USE ROLE ACCOUNTADMIN;

--  ASK: who is allowed to see row-level variant data today, and how is that
--       enforced?
-- =====================================================================


-- =====================================================================
--  SEGMENT 8 — COMMIT THE ARTIFACTS, REDEPLOY FROM GIT    (~10 min)
--  THIS IS THE DROP if the room thins at the hour. See runbook.md.
--
--  On your laptop, in the repo:
--    git add semantic/sv_guardant_variants.yaml model/variant_clf.joblib
--    git commit -m "Add semantic view spec and trained model"
--    git push
--
--  SAY THIS ABOUT THE MODEL FILE, BEFORE ANYONE ASKS:
--    "Committing a model binary to git is normally an anti-pattern — the
--     registry is the artifact store. I'm doing it here to show you the
--     handoff boundary: I trained it, you deploy it, git is the seam."
--   The file is 130 KB, which is why this is tolerable at all.
-- =====================================================================
USE ROLE ACCOUNTADMIN;

-- 8a. Snowflake pulls the new commit.
ALTER GIT REPOSITORY DEMO.GUARDANT_DEMO.GUARDANT_ENABLEMENT_REPO FETCH;

-- Both artifacts are now visible to Snowflake as files on a stage.
LS @DEMO.GUARDANT_DEMO.GUARDANT_ENABLEMENT_REPO/branches/main/semantic/;
LS @DEMO.GUARDANT_DEMO.GUARDANT_ENABLEMENT_REPO/branches/main/model/;

-- 8b. Redeploy the semantic view FROM THE COMMITTED FILE into a different
--     schema. Same YAML, new object — which is the proof that the file, not
--     the click-path, is the source of truth.
--     Run the notebook cell in GUARDANT_08_GITOPS, or from your laptop:
--       .venv-ml/bin/python tools/deploy_semantic_view.py \
--            --schema DEMO.GUARDANT_GITOPS
--     MEASURED: "Semantic view was successfully created."
SHOW SEMANTIC VIEWS IN SCHEMA DEMO.GUARDANT_GITOPS;

-- 8c. The round trip. Export the running object back to YAML and diff it
--     against the file in git. This is what makes it version control rather
--     than a one-way export.
SELECT SYSTEM$READ_YAML_FROM_SEMANTIC_VIEW('DEMO.GUARDANT_DEMO.SV_GUARDANT_VARIANTS') AS yaml_from_object;

-- 8d. The model, loaded from the repo rather than from a laptop. Open
--     GUARDANT_08_GITOPS in Snowsight and run it: it reads
--     model/variant_clf.joblib off the git stage, asserts the scikit-learn
--     version matches, and registers it as a new version.
--
--  THE VERSION TRAP, worth saying: joblib.load needs compatible scikit-learn
--  between where the model was written and where it is read. We pin 1.5.2
--  locally BECAUSE Snowflake's channel has 1.5.2. Mismatch here can fail
--  loudly or, worse, quietly.
SHOW VERSIONS IN MODEL DEMO.GUARDANT_DEMO.GUARDANT_VARIANT_CLF;

--  CLOSE ON THEIR WORKFLOW, not the product list:
--    "You've seen a model trained on a laptop score twenty million rows
--     where the data lives, a definition of 'reportable' that an analyst and
--     an AI agent both inherit, and both of those artifacts living in git
--     like any other code. Nothing about your tools changed."
--
--  THE TWO FOLLOW-UPS:
--    1. A working session on one real Guardant use case
--    2. A deep dive on whichever segment drew the most questions — note which
--
--  TAKE-HOME: the repo is public, and lab/ is a full self-serve hands-on lab
--  if they want to run it themselves.
--    github.com/sfc-gh-pmatson/guardant-snowflake-enablement
-- =====================================================================


-- =====================================================================
--  AFTER THE SESSION — run this within minutes. See teardown.sql.
-- =====================================================================
USE ROLE ACCOUNTADMIN;
ALTER COMPUTE POOL IF EXISTS GUARDANT_NOTEBOOK_POOL SUSPEND;
DROP COMPUTE POOL IF EXISTS GUARDANT_DEMO_POOL_THROWAWAY;
ALTER WAREHOUSE GUARDANT_DEMO_WH SUSPEND;

-- Confirm
SHOW COMPUTE POOLS LIKE 'GUARDANT_%';
