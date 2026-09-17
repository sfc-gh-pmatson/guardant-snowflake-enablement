/* ============================================================================
   Guardant Health — Snowflake Enablement Session
   04_deploy_notebooks.sql — create the notebooks from the git repository

   Run after 03_git_integration.sql.

   This deploys the notebooks straight from the GitHub repo, which is also the
   story being told in the GitHub segment of the session: the repo is the source
   of truth, Snowflake fetches from it.

   After a `git push`, refresh a notebook. Note that ADD LIVE VERSION fails with
   "There is already a live version" unless you drop the existing one first:

       ALTER GIT REPOSITORY GUARDANT_ENABLEMENT_REPO FETCH;
       ALTER NOTEBOOK <name> DROP LIVE VERSION;
       ALTER NOTEBOOK <name> ADD LIVE VERSION FROM LAST;

   Re-running the CREATE OR REPLACE below achieves the same thing and is the
   simpler option if you have just pushed changes to several notebooks.
   ============================================================================ */

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE GUARDANT_DEMO_WH;
USE SCHEMA DEMO.GUARDANT_DEMO;

ALTER GIT REPOSITORY GUARDANT_ENABLEMENT_REPO FETCH;

-- 1 — Snowflake Notebooks ---------------------------------------------------
CREATE OR REPLACE NOTEBOOK GUARDANT_01_NOTEBOOKS
  FROM '@GUARDANT_ENABLEMENT_REPO/branches/main/notebooks'
  MAIN_FILE = '01_snowflake_notebooks.ipynb'
  QUERY_WAREHOUSE = GUARDANT_DEMO_WH
  COMMENT = 'Guardant session 1/3 — Snowflake Notebooks';
ALTER NOTEBOOK GUARDANT_01_NOTEBOOKS ADD LIVE VERSION FROM LAST;

-- 2 — Snowpark --------------------------------------------------------------
CREATE OR REPLACE NOTEBOOK GUARDANT_02_SNOWPARK
  FROM '@GUARDANT_ENABLEMENT_REPO/branches/main/notebooks'
  MAIN_FILE = '02_snowpark_at_scale.ipynb'
  QUERY_WAREHOUSE = GUARDANT_DEMO_WH
  COMMENT = 'Guardant session 2/3 — Snowpark at scale';
ALTER NOTEBOOK GUARDANT_02_SNOWPARK ADD LIVE VERSION FROM LAST;

-- 3 — Cortex AI -------------------------------------------------------------
CREATE OR REPLACE NOTEBOOK GUARDANT_03_CORTEX_AI
  FROM '@GUARDANT_ENABLEMENT_REPO/branches/main/notebooks'
  MAIN_FILE = '03_cortex_ai_clinical_text.ipynb'
  QUERY_WAREHOUSE = GUARDANT_DEMO_WH
  COMMENT = 'Guardant session 3/3 — Cortex AI on clinical text';
ALTER NOTEBOOK GUARDANT_03_CORTEX_AI ADD LIVE VERSION FROM LAST;

-- 4 — Train + register a model inside Snowflake -----------------------------
--   Container runtime, not warehouse runtime, for one reason: snowflake-ml-python
--   is already present there, so nothing has to be chosen in the Packages picker
--   before the notebook will run. That matters for a notebook deployed from git,
--   because the picker is a UI action that no script can perform for you.
--
--   The trade-off is encoded in the notebook itself: on container runtime,
--   log_model defaults to Snowpark Container Services only, so the model would
--   register and then MODEL!PREDICT would fail to resolve from SQL. The notebook
--   passes target_platforms=["WAREHOUSE"] explicitly to avoid that.
CREATE OR REPLACE NOTEBOOK GUARDANT_04_MODEL_REGISTRY
  FROM '@GUARDANT_ENABLEMENT_REPO/branches/main/notebooks'
  MAIN_FILE = '04_train_register_in_snowflake.ipynb'
  QUERY_WAREHOUSE = GUARDANT_DEMO_WH
  RUNTIME_NAME = 'SYSTEM$BASIC_RUNTIME'
  COMPUTE_POOL = 'GUARDANT_NOTEBOOK_POOL'
  COMMENT = 'Guardant Part 5 — train and register a model without leaving Snowflake';
ALTER NOTEBOOK GUARDANT_04_MODEL_REGISTRY ADD LIVE VERSION FROM LAST;

SHOW NOTEBOOKS LIKE 'GUARDANT_%' IN SCHEMA DEMO.GUARDANT_DEMO;

/* ---------------------------------------------------------------------------
   Optional smoke test — executes every cell headlessly. Worth running the
   morning of the session. Notebook 3 makes real Cortex calls, so it consumes
   a small amount of AI credit.

     EXECUTE NOTEBOOK GUARDANT_01_NOTEBOOKS();
     EXECUTE NOTEBOOK GUARDANT_02_SNOWPARK();
     EXECUTE NOTEBOOK GUARDANT_03_CORTEX_AI();

   Notebook 4 registers GUARDANT_VARIANT_CLF version V3. It is safe to re-run:
   it drops an existing V3 first rather than colliding on the version name.

     EXECUTE NOTEBOOK GUARDANT_04_MODEL_REGISTRY();
   --------------------------------------------------------------------------- */
