/* ============================================================================
   Guardant Health — Hands-On Lab
   99_rehearsal_shortcut.sql

   FOR THE FACILITATOR ONLY. Do not run this in Guardant's account.

   Stands up a complete, working `GUARDANT_LAB` in your own demo account in about
   ten seconds, so you can rehearse the participant experience end to end.

   The shortcut: instead of regenerating 20M rows, the shared schema is built as
   VIEWS over the DEMO.GUARDANT_DEMO dataset you already have. Every object name
   the participants use resolves identically, so the workbook and the participant
   script run unchanged.

   PREREQUISITE: DEMO.GUARDANT_DEMO already populated (setup/00, 01, 02).

   REHEARSE AS THE PARTICIPANT ROLE, NOT AS ACCOUNTADMIN. Almost every hands-on
   lab failure is a grant your admin role happens to have and theirs does not.
   Section 5 shows how.
   ============================================================================ */

USE ROLE ACCOUNTADMIN;

-- 1. Infrastructure ---------------------------------------------------------
CREATE DATABASE IF NOT EXISTS GUARDANT_LAB
  COMMENT = 'Guardant hands-on lab — REHEARSAL (views over DEMO.GUARDANT_DEMO)';
CREATE SCHEMA IF NOT EXISTS GUARDANT_LAB.GUARDANT_DEMO
  COMMENT = 'Shared dataset — rehearsal views, not real tables';
CREATE WAREHOUSE IF NOT EXISTS GUARDANT_LAB_WH
  WAREHOUSE_SIZE = 'MEDIUM' AUTO_SUSPEND = 120 AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE;
CREATE ROLE IF NOT EXISTS GUARDANT_LAB
  COMMENT = 'Guardant hands-on lab participant';

-- 2. Views standing in for the generated tables -----------------------------
CREATE OR REPLACE VIEW GUARDANT_LAB.GUARDANT_DEMO.VARIANT_CALLS         AS SELECT * FROM DEMO.GUARDANT_DEMO.VARIANT_CALLS;
CREATE OR REPLACE VIEW GUARDANT_LAB.GUARDANT_DEMO.SPECIMENS             AS SELECT * FROM DEMO.GUARDANT_DEMO.SPECIMENS;
CREATE OR REPLACE VIEW GUARDANT_LAB.GUARDANT_DEMO.PATIENTS              AS SELECT * FROM DEMO.GUARDANT_DEMO.PATIENTS;
CREATE OR REPLACE VIEW GUARDANT_LAB.GUARDANT_DEMO.GENE_PANEL            AS SELECT * FROM DEMO.GUARDANT_DEMO.GENE_PANEL;
CREATE OR REPLACE VIEW GUARDANT_LAB.GUARDANT_DEMO.PATHOLOGY_REPORTS     AS SELECT * FROM DEMO.GUARDANT_DEMO.PATHOLOGY_REPORTS;
CREATE OR REPLACE VIEW GUARDANT_LAB.GUARDANT_DEMO.V_REPORTABLE_VARIANTS AS SELECT * FROM DEMO.GUARDANT_DEMO.V_REPORTABLE_VARIANTS;

-- 3. Grants -----------------------------------------------------------------
GRANT USAGE, OPERATE ON WAREHOUSE GUARDANT_LAB_WH        TO ROLE GUARDANT_LAB;
GRANT USAGE ON DATABASE GUARDANT_LAB                     TO ROLE GUARDANT_LAB;
GRANT USAGE ON SCHEMA GUARDANT_LAB.GUARDANT_DEMO         TO ROLE GUARDANT_LAB;
GRANT SELECT ON ALL VIEWS IN SCHEMA GUARDANT_LAB.GUARDANT_DEMO     TO ROLE GUARDANT_LAB;
GRANT SELECT ON FUTURE VIEWS IN SCHEMA GUARDANT_LAB.GUARDANT_DEMO  TO ROLE GUARDANT_LAB;
GRANT SELECT ON ALL TABLES IN SCHEMA GUARDANT_LAB.GUARDANT_DEMO    TO ROLE GUARDANT_LAB;
GRANT SELECT ON FUTURE TABLES IN SCHEMA GUARDANT_LAB.GUARDANT_DEMO TO ROLE GUARDANT_LAB;
GRANT CREATE SCHEMA ON DATABASE GUARDANT_LAB             TO ROLE GUARDANT_LAB;

-- Grant yourself the participant role so you can rehearse as one.
-- GRANT ROLE does not accept IDENTIFIER() or CURRENT_USER() — it needs a literal
-- username. This derives the statement for you; copy the output and run it.
SET grant_me = 'GRANT ROLE GUARDANT_LAB TO USER "' || CURRENT_USER() || '";';
SELECT $grant_me AS run_this_next;

-- 4. The claim-your-schema procedure ----------------------------------------
CREATE OR REPLACE PROCEDURE GUARDANT_LAB.GUARDANT_DEMO.CLAIM_MY_LAB_SCHEMA()
RETURNS STRING
LANGUAGE SQL
COMMENT = 'Creates and grants the calling user their own private lab schema'
EXECUTE AS OWNER
AS
$$
DECLARE
    target_schema STRING;
    full_name     STRING;
    lab_database  STRING;
    participant   STRING;
BEGIN
    participant   := CURRENT_USER();
    target_schema := 'LAB_' || UPPER(REGEXP_REPLACE(:participant, '[^A-Za-z0-9]', '_'));
    lab_database  := CURRENT_DATABASE();
    full_name     := :lab_database || '.' || :target_schema;

    EXECUTE IMMEDIATE 'CREATE SCHEMA IF NOT EXISTS ' || :full_name
        || ' COMMENT = ''Private lab scratch schema for ' || :participant || '''';

    EXECUTE IMMEDIATE 'GRANT ALL ON SCHEMA ' || :full_name || ' TO ROLE GUARDANT_LAB';

    RETURN 'Your lab schema is ready: ' || :full_name
        || ' — run: USE SCHEMA ' || :full_name;
END;
$$;

GRANT USAGE ON PROCEDURE GUARDANT_LAB.GUARDANT_DEMO.CLAIM_MY_LAB_SCHEMA()
  TO ROLE GUARDANT_LAB;

-- 5. Now rehearse as a participant ------------------------------------------
/* Switch roles and run lab/02_participant_setup.sql exactly as an attendee
   would, then work through notebooks/00_lab_workbook.ipynb:

     USE ROLE GUARDANT_LAB;
     USE WAREHOUSE GUARDANT_LAB_WH;
     USE SCHEMA GUARDANT_LAB.GUARDANT_DEMO;
     SELECT COUNT(*) FROM VARIANT_CALLS;              -- expect 20,000,000
     CALL CLAIM_MY_LAB_SCHEMA();                       -- creates LAB_<you>

   If anything fails while you are in the GUARDANT_LAB role but works as
   ACCOUNTADMIN, that is exactly the bug this rehearsal exists to catch. Fix the
   grant in 01_admin_setup.sql, not just here.                              */

SELECT 'Rehearsal lab ready' AS status,
       'Now: USE ROLE GUARDANT_LAB and run lab/02_participant_setup.sql' AS next_step;

-- 6. Teardown ---------------------------------------------------------------
/*  DROP DATABASE IF EXISTS GUARDANT_LAB;
    DROP WAREHOUSE IF EXISTS GUARDANT_LAB_WH;
    DROP ROLE IF EXISTS GUARDANT_LAB;                                        */
