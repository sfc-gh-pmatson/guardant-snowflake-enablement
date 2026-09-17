-- =====================================================================
--  GUARDANT HEALTH — DEVELOPER SURFACE TOUR
--  teardown.sql
--
--  Run the SUSPEND section within minutes of the session ending. Compute
--  pools bill while they are ACTIVE whether or not anything is running on
--  them, and the notebook pool has a 1-hour auto-suspend.
--
--  The DROP section is optional — keep the objects if there is a follow-up
--  session, since rebuilding the dataset takes 30 seconds but rebuilding the
--  model needs your laptop and a browser OAuth round trip.
-- =====================================================================

USE ROLE ACCOUNTADMIN;

-- ---------------------------------------------------------------------
-- SUSPEND — do this straight away. This is the part that costs money.
-- ---------------------------------------------------------------------
ALTER COMPUTE POOL IF EXISTS GUARDANT_NOTEBOOK_POOL SUSPEND;
DROP COMPUTE POOL IF EXISTS GUARDANT_DEMO_POOL_THROWAWAY;
ALTER WAREHOUSE IF EXISTS GUARDANT_DEMO_WH SUSPEND;

-- Confirm: notebook pool SUSPENDED, throwaway pool gone.
SHOW COMPUTE POOLS LIKE 'GUARDANT_%';
SHOW WAREHOUSES LIKE 'GUARDANT_DEMO_WH';


-- ---------------------------------------------------------------------
-- DROP — full removal. Only run when there is no follow-up planned.
-- ---------------------------------------------------------------------
/*
-- Demo objects
DROP AGENT         IF EXISTS DEMO.GUARDANT_DEMO.GUARDANT_VARIANT_AGENT;
DROP SEMANTIC VIEW IF EXISTS DEMO.GUARDANT_DEMO.SV_GUARDANT_VARIANTS;
DROP SEMANTIC VIEW IF EXISTS DEMO.GUARDANT_GITOPS.SV_GUARDANT_VARIANTS;
DROP MODEL         IF EXISTS DEMO.GUARDANT_DEMO.GUARDANT_VARIANT_CLF;
DROP SCHEMA        IF EXISTS DEMO.GUARDANT_GITOPS;

-- Notebooks
DROP NOTEBOOK IF EXISTS DEMO.GUARDANT_DEMO.GUARDANT_01_NOTEBOOKS;
DROP NOTEBOOK IF EXISTS DEMO.GUARDANT_DEMO.GUARDANT_02_SNOWPARK;
DROP NOTEBOOK IF EXISTS DEMO.GUARDANT_DEMO.GUARDANT_03_CORTEX_AI;

-- Git integrations
DROP GIT REPOSITORY IF EXISTS DEMO.GUARDANT_DEMO.GUARDANT_LABS_REPO;
DROP GIT REPOSITORY IF EXISTS DEMO.GUARDANT_DEMO.GUARDANT_ENABLEMENT_REPO;
DROP API INTEGRATION IF EXISTS GUARDANT_LABS_API_INTEGRATION;
DROP API INTEGRATION IF EXISTS GUARDANT_GITHUB_API_INTEGRATION;
DROP SECRET IF EXISTS DEMO.GUARDANT_DEMO.GUARDANT_GITHUB_SECRET;

-- Compute and roles
DROP COMPUTE POOL IF EXISTS GUARDANT_NOTEBOOK_POOL;
DROP WAREHOUSE    IF EXISTS GUARDANT_DEMO_WH;
DROP ROLE         IF EXISTS GUARDANT_ANALYST;

-- The dataset itself. Regenerates from setup/01_synthetic_data.sql in ~30s.
DROP SCHEMA IF EXISTS DEMO.GUARDANT_DEMO CASCADE;

-- Left over from the facilitator's rehearsal environment. These will not exist
-- in your account unless you created them yourself; the DROPs are harmless.
DROP DATABASE  IF EXISTS GUARDANT_LAB;
DROP WAREHOUSE IF EXISTS GUARDANT_LAB_WH;
DROP ROLE      IF EXISTS GUARDANT_LAB;
*/


-- ---------------------------------------------------------------------
-- NOTE ON THE GITHUB SECRET
-- If you drop and rebuild the git integration, the secret holds a GitHub
-- token. Rotate it rather than reusing an old one, and never commit it —
-- setup/03_git_integration.sql carries a placeholder only.
-- ---------------------------------------------------------------------
SELECT 'Teardown complete — check SHOW COMPUTE POOLS above' AS status;
