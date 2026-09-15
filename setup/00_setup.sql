/* ============================================================================
   Guardant Health — Snowflake Enablement Session
   00_setup.sql — database, schema, warehouse, and role grants

   Run first. Idempotent: safe to re-run.
   Requires ACCOUNTADMIN (or a role with CREATE DATABASE / CREATE WAREHOUSE).
   ============================================================================ */

USE ROLE ACCOUNTADMIN;

-- ---------------------------------------------------------------------------
-- Warehouse. MEDIUM is enough to generate ~20M variant rows in a couple of
-- minutes and to run every demo query interactively. Auto-suspend keeps the
-- credit cost of a one-hour session negligible.
-- ---------------------------------------------------------------------------
CREATE WAREHOUSE IF NOT EXISTS GUARDANT_DEMO_WH
  WAREHOUSE_SIZE = 'MEDIUM'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Guardant enablement session — demo compute';

CREATE DATABASE IF NOT EXISTS DEMO
  COMMENT = 'Shared demo database';

CREATE SCHEMA IF NOT EXISTS DEMO.GUARDANT_DEMO
  COMMENT = 'Synthetic liquid-biopsy genomics data for the Guardant Health enablement session';

USE WAREHOUSE GUARDANT_DEMO_WH;
USE SCHEMA DEMO.GUARDANT_DEMO;

-- ---------------------------------------------------------------------------
-- A stage for anything we need to land as a file (not required by the demos,
-- but handy if you want to show file-based ingest live).
-- ---------------------------------------------------------------------------
CREATE STAGE IF NOT EXISTS DEMO.GUARDANT_DEMO.DEMO_STAGE
  DIRECTORY = (ENABLE = TRUE)
  COMMENT = 'Scratch stage for the enablement session';

SELECT 'Setup complete' AS status,
       CURRENT_ACCOUNT() AS account,
       CURRENT_WAREHOUSE() AS warehouse,
       CURRENT_DATABASE() || '.' || CURRENT_SCHEMA() AS target_schema;
