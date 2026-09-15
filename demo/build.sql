-- =====================================================================
--  GUARDANT HEALTH — DEVELOPER SURFACE TOUR
--  build.sql — creates every object the demo needs, from scratch
--
--  Order matters. Run top to bottom.
--  Requires ACCOUNTADMIN (or CREATE DATABASE / WAREHOUSE / ROLE / COMPUTE POOL).
--
--  Steps 1-3 are already done if you built the earlier version of this repo.
--  Everything is IF NOT EXISTS / OR REPLACE, so re-running is safe.
-- =====================================================================

USE ROLE ACCOUNTADMIN;

-- ---------------------------------------------------------------------
-- 1. Base data — run these three files first (they are unchanged):
--      setup/00_setup.sql            database, schema, warehouse, stage
--      setup/01_synthetic_data.sql   the ~20M row dataset (about 30s)
--      setup/02_udf.sql              variant confidence UDF
--    Expect: DEMO.GUARDANT_DEMO.VARIANT_CALLS = 20,000,000 rows.
-- ---------------------------------------------------------------------
-- Expect 20,000,000
SELECT COUNT(*) AS variant_calls FROM DEMO.GUARDANT_DEMO.VARIANT_CALLS;

-- ---------------------------------------------------------------------
-- 2. Your own git repository (segment 8) — needs a credential because the
--    repo is public but the secret is how you would do a private one.
--    See setup/03_git_integration.sql. Then:
-- ---------------------------------------------------------------------
ALTER GIT REPOSITORY DEMO.GUARDANT_DEMO.GUARDANT_ENABLEMENT_REPO FETCH;

-- ---------------------------------------------------------------------
-- 3. Notebooks deployed from git — see setup/04_deploy_notebooks.sql.
--    Segment 3 uses GUARDANT_01_NOTEBOOKS.
-- ---------------------------------------------------------------------
SHOW NOTEBOOKS LIKE 'GUARDANT_%' IN SCHEMA DEMO.GUARDANT_DEMO;

-- ---------------------------------------------------------------------
-- 4. Compute pools (segment 3).
--
--    TWO pools on purpose. A pool takes minutes to reach ACTIVE, so the one
--    your notebook runs on is pre-warmed, and the one you CREATE live is
--    disposable. Do not merge these.
-- ---------------------------------------------------------------------
CREATE COMPUTE POOL IF NOT EXISTS GUARDANT_NOTEBOOK_POOL
  MIN_NODES = 1 MAX_NODES = 1 INSTANCE_FAMILY = CPU_X64_XS
  AUTO_SUSPEND_SECS = 3600
  COMMENT = 'Pre-warmed pool for the Guardant session notebooks';

-- The throwaway pool is created DURING the session by demo.sql, not here.

-- ---------------------------------------------------------------------
-- 5. Snowflake-Labs git repository (segment 4). Read-only, public, so no
--    secret and no GIT_CREDENTIALS clause.
-- ---------------------------------------------------------------------
CREATE OR REPLACE API INTEGRATION GUARDANT_LABS_API_INTEGRATION
  API_PROVIDER = GIT_HTTPS_API
  API_ALLOWED_PREFIXES = ('https://github.com/Snowflake-Labs')
  ENABLED = TRUE
  COMMENT = 'Read-only access to the public Snowflake-Labs org';

CREATE OR REPLACE GIT REPOSITORY DEMO.GUARDANT_DEMO.GUARDANT_LABS_REPO
  API_INTEGRATION = GUARDANT_LABS_API_INTEGRATION
  ORIGIN = 'https://github.com/Snowflake-Labs/sfguide-data-engineering-with-notebooks.git'
  COMMENT = 'Snowflake-Labs quickstart repo — public, no credential needed';

ALTER GIT REPOSITORY DEMO.GUARDANT_DEMO.GUARDANT_LABS_REPO FETCH;
-- VERIFIED: 14 files visible, including notebooks/ and scripts/.
LS @DEMO.GUARDANT_DEMO.GUARDANT_LABS_REPO/branches/main/;

-- ---------------------------------------------------------------------
-- 6. The model (segment 5). Trained and registered from your laptop:
--
--      uv venv --python 3.11 .venv-ml
--      VIRTUAL_ENV=.venv-ml uv pip install "snowflake-ml-python==1.9.2" \
--          "scikit-learn==1.5.2" "joblib==1.5.3" pandas
--      .venv-ml/bin/python tools/train_and_register_model.py
--
--    THE PIN IS NOT ARBITRARY: snowflake-ml-python 1.9.2 requires
--    scikit-learn <1.6, and Snowflake's Anaconda channel has 1.5.2. Pinning
--    1.5.2 means the version that writes the pickle is the version that reads
--    it. Your system Python (3.14) cannot run snowflake-ml-python at all.
--
--    MEASURED: 50,000 rows, 7.9% pathogenic, ROC AUC 0.6896,
--              predicted-positive 63.0%, file 130 KB.
-- ---------------------------------------------------------------------
SHOW VERSIONS IN MODEL DEMO.GUARDANT_DEMO.GUARDANT_VARIANT_CLF;

-- ---------------------------------------------------------------------
-- 7. The semantic view (segment 6), deployed FROM THE YAML FILE:
--
--      .venv-ml/bin/python tools/deploy_semantic_view.py --verify-only
--      .venv-ml/bin/python tools/deploy_semantic_view.py
--
--    semantic/sv_guardant_variants.yaml is the source of truth.
-- ---------------------------------------------------------------------
DESCRIBE SEMANTIC VIEW DEMO.GUARDANT_DEMO.SV_GUARDANT_VARIANTS;

-- ---------------------------------------------------------------------
-- 8. The GitOps redeploy target (segment 8). Proves the committed file, not
--    the click-path, is authoritative.
--      .venv-ml/bin/python tools/deploy_semantic_view.py \
--           --schema DEMO.GUARDANT_GITOPS
-- ---------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS DEMO.GUARDANT_GITOPS
  COMMENT = 'Redeploy target proving the committed YAML is the source of truth';

-- ---------------------------------------------------------------------
-- 9. The Cortex Agent (segment 7), over the semantic view.
--    Recreate it with the spec in demo/agent_spec.json if needed; the
--    definition is also recoverable with DESCRIBE AGENT.
--    NOTE: GET_DDL('AGENT', ...) is NOT valid — use DESCRIBE AGENT.
-- ---------------------------------------------------------------------
SHOW AGENTS LIKE 'GUARDANT_VARIANT_AGENT' IN SCHEMA DEMO.GUARDANT_DEMO;

-- ---------------------------------------------------------------------
-- 10. The consumer role (segment 7). Deliberately minimal: usage on the
--     warehouse, database and schema, SELECT on the SEMANTIC VIEW, usage on
--     the AGENT — and NO grant on any base table. That absence is the demo.
-- ---------------------------------------------------------------------
CREATE ROLE IF NOT EXISTS GUARDANT_ANALYST
  COMMENT = 'Read-only consumer of the governed semantic layer and agent';

GRANT USAGE ON WAREHOUSE GUARDANT_DEMO_WH             TO ROLE GUARDANT_ANALYST;
GRANT USAGE ON DATABASE DEMO                          TO ROLE GUARDANT_ANALYST;
GRANT USAGE ON SCHEMA DEMO.GUARDANT_DEMO              TO ROLE GUARDANT_ANALYST;
GRANT SELECT ON SEMANTIC VIEW DEMO.GUARDANT_DEMO.SV_GUARDANT_VARIANTS
  TO ROLE GUARDANT_ANALYST;
GRANT USAGE ON AGENT DEMO.GUARDANT_DEMO.GUARDANT_VARIANT_AGENT
  TO ROLE GUARDANT_ANALYST;

-- Grant it to yourself so you can switch to it during segment 7.
-- GRANT ROLE does not accept CURRENT_USER(); this prints the statement to run.
SELECT 'GRANT ROLE GUARDANT_ANALYST TO USER "' || CURRENT_USER() || '";' AS run_this_next;


-- =====================================================================
--  VERIFY — expected results are stated. Anything else means stop.
-- =====================================================================
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE GUARDANT_DEMO_WH;
-- USE SCHEMA is required, not optional: model methods are resolved against the
-- session schema, and an unqualified GUARDANT_VARIANT_CLF!PREDICT fails with
-- "Unknown function" without it.
USE SCHEMA DEMO.GUARDANT_DEMO;
SELECT COUNT(*) AS variant_calls FROM DEMO.GUARDANT_DEMO.VARIANT_CALLS;

-- The semantic view answers. NSCLC 8,581 / 1,100,091 / 9.626
SELECT * FROM SEMANTIC_VIEW(
  DEMO.GUARDANT_DEMO.sv_guardant_variants
  DIMENSIONS patients.cancer_type
  METRICS patients.patient_count, variants.reportable_calls, variants.median_vaf_pct
  WHERE variants.is_reportable AND gene_panel.is_actionable
) ORDER BY reportable_calls DESC LIMIT 3;

-- The model scores and its predictions VARY. Expect ~63% flagged, not 0%.
-- MEASURED: 62.9%. If this reads 0.0 the registry holds a broken model.
-- If pct_flagged is 0.0 the registry holds a broken model — retrain.
WITH s AS (
  SELECT GUARDANT_VARIANT_CLF!PREDICT(vaf, read_depth, alt_read_count, mapping_quality)
           :output_feature_0::INT AS p
  FROM DEMO.GUARDANT_DEMO.VARIANT_CALLS SAMPLE (20000 ROWS) WHERE call_filter='PASS'
)
SELECT ROUND(100.0*SUM(p)/COUNT(*),1) AS pct_flagged FROM s;

-- Both git repos readable
LS @DEMO.GUARDANT_DEMO.GUARDANT_LABS_REPO/branches/main/;
LS @DEMO.GUARDANT_DEMO.GUARDANT_ENABLEMENT_REPO/branches/main/model/;

-- The GitOps copy returns IDENTICAL numbers to the original:
-- PALO-ALTO 98.616269 / REDWOOD-CITY 98.597465 / SAN-DIEGO 98.570595
SELECT * FROM SEMANTIC_VIEW(
  DEMO.GUARDANT_GITOPS.sv_guardant_variants
  DIMENSIONS specimens.lab_site
  METRICS reportable_calls_per_specimen
) ORDER BY lab_site;

-- ###  THE CHECK THAT MATTERS MOST  ###
-- Isolation only holds with secondary roles OFF. Expect the SELECT to FAIL
-- with "does not exist or not authorized". If it returns 20,000,000, your
-- secondary roles are still active and segment 7 will prove nothing.
USE ROLE GUARDANT_ANALYST;
USE SECONDARY ROLES NONE;
SELECT COUNT(*) FROM DEMO.GUARDANT_DEMO.VARIANT_CALLS;   -- expect an ERROR

USE SECONDARY ROLES ALL;
USE ROLE ACCOUNTADMIN;
SELECT 'Build verified' AS status;
