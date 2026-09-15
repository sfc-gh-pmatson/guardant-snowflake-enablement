/* ============================================================================
   Guardant Health — Hands-On Lab
   01_admin_setup.sql

   Run ONCE by a Guardant admin, before the session.
   Run lab/00_preflight_check.sql first.

   Creates:
     - a database and a shared data schema
     - a warehouse sized for six concurrent notebook users
     - the GUARDANT_LAB role, granted to the six participants
     - CLAIM_MY_LAB_SCHEMA(), a procedure that gives each participant their own
       private scratch schema WITHOUT granting them CREATE SCHEMA

   Then run, in this order:
     setup/01_synthetic_data.sql    (the ~20M row dataset)
     setup/02_udf.sql               (the confidence-score UDF)

   ------------------------------------------------------------------------
   ROLE: this script does NOT issue USE ROLE. Supply the role on the command
   line (snow sql --role <role>) or with USE ROLE before running. That keeps it
   usable by SYSADMIN/USERADMIN rather than demanding ACCOUNTADMIN.
   ------------------------------------------------------------------------

   RETARGETING: if creating a database or warehouse is not permitted, change the
   variables below to point at objects that already exist, and comment out the
   corresponding CREATE statements.
   ============================================================================ */

-- ---------------------------------------------------------------------------
-- Configuration. Edit these four lines and nothing else.
-- ---------------------------------------------------------------------------
SET lab_db        = 'GUARDANT_LAB';
SET lab_data_schema = 'GUARDANT_DEMO';   -- shared, read-only to participants
SET lab_wh        = 'GUARDANT_LAB_WH';
SET lab_role      = 'GUARDANT_LAB';

-- IDENTIFIER() will not accept a concatenation, so build the fully-qualified
-- schema name into its own variable and use that everywhere.
SET lab_data_fq   = $lab_db || '.' || $lab_data_schema;

-- ---------------------------------------------------------------------------
-- 1. Database and shared data schema
-- ---------------------------------------------------------------------------
CREATE DATABASE IF NOT EXISTS IDENTIFIER($lab_db)
  COMMENT = 'Guardant Health hands-on enablement lab — synthetic data only';

CREATE SCHEMA IF NOT EXISTS IDENTIFIER($lab_data_fq)
  COMMENT = 'Shared synthetic liquid-biopsy dataset — read-only to participants';

-- ---------------------------------------------------------------------------
-- 2. Warehouse.
--
-- MEDIUM, not XSMALL: six people running notebook cells at the same time on an
-- XSMALL will queue, and queueing during a hands-on session reads to the room
-- as "Snowflake is slow". Auto-suspend keeps the cost of that trivial.
-- ---------------------------------------------------------------------------
CREATE WAREHOUSE IF NOT EXISTS IDENTIFIER($lab_wh)
  WAREHOUSE_SIZE = 'MEDIUM'
  AUTO_SUSPEND = 120
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Guardant hands-on lab — six concurrent participants';

-- ---------------------------------------------------------------------------
-- 3. The participant role
-- ---------------------------------------------------------------------------
CREATE ROLE IF NOT EXISTS IDENTIFIER($lab_role)
  COMMENT = 'Guardant hands-on enablement lab participant';

GRANT USAGE ON WAREHOUSE IDENTIFIER($lab_wh)          TO ROLE IDENTIFIER($lab_role);
GRANT OPERATE ON WAREHOUSE IDENTIFIER($lab_wh)        TO ROLE IDENTIFIER($lab_role);
GRANT USAGE ON DATABASE IDENTIFIER($lab_db)           TO ROLE IDENTIFIER($lab_role);
GRANT USAGE ON SCHEMA IDENTIFIER($lab_data_fq)
  TO ROLE IDENTIFIER($lab_role);

-- Read-only on the shared dataset, including anything created later by the
-- data-generation script.
GRANT SELECT ON ALL TABLES IN SCHEMA IDENTIFIER($lab_data_fq)
  TO ROLE IDENTIFIER($lab_role);
GRANT SELECT ON FUTURE TABLES IN SCHEMA IDENTIFIER($lab_data_fq)
  TO ROLE IDENTIFIER($lab_role);
GRANT SELECT ON ALL VIEWS IN SCHEMA IDENTIFIER($lab_data_fq)
  TO ROLE IDENTIFIER($lab_role);
GRANT SELECT ON FUTURE VIEWS IN SCHEMA IDENTIFIER($lab_data_fq)
  TO ROLE IDENTIFIER($lab_role);
GRANT USAGE ON ALL FUNCTIONS IN SCHEMA IDENTIFIER($lab_data_fq)
  TO ROLE IDENTIFIER($lab_role);
GRANT USAGE ON FUTURE FUNCTIONS IN SCHEMA IDENTIFIER($lab_data_fq)
  TO ROLE IDENTIFIER($lab_role);

-- Participants create notebooks, so they need to be able to create them
-- somewhere. Their own schema (created in section 4) is where.
GRANT CREATE SCHEMA ON DATABASE IDENTIFIER($lab_db) TO ROLE IDENTIFIER($lab_role);
/* NOTE: if handing out CREATE SCHEMA is not acceptable, revoke the grant above.
   CLAIM_MY_LAB_SCHEMA() runs with owner's rights and does not depend on it —
   the grant is here only so participants can also create notebooks and tables
   inside the schema they are given. Revoking it means the admin must pre-create
   the six schemas by calling the procedure for each user (see section 5). */


-- ---------------------------------------------------------------------------
-- 4. Per-participant private schema, without handing out account privileges.
--
-- Each participant calls this once. It derives the schema name from
-- CURRENT_USER(), so nobody can collide with anyone else and nobody needs to be
-- told which schema is theirs.
--
-- EXECUTE AS OWNER means the schema is created with this admin role's
-- authority, not the participant's.
-- ---------------------------------------------------------------------------
USE DATABASE IDENTIFIER($lab_db);
USE SCHEMA IDENTIFIER($lab_data_schema);

CREATE OR REPLACE PROCEDURE CLAIM_MY_LAB_SCHEMA()
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
    -- Snowflake usernames can contain characters that are awkward in an
    -- identifier (dots, hyphens, @). Normalise them to underscores.
    participant   := CURRENT_USER();
    target_schema := 'LAB_' || UPPER(REGEXP_REPLACE(:participant, '[^A-Za-z0-9]', '_'));
    lab_database  := CURRENT_DATABASE();
    full_name     := :lab_database || '.' || :target_schema;

    EXECUTE IMMEDIATE 'CREATE SCHEMA IF NOT EXISTS ' || :full_name
        || ' COMMENT = ''Private lab scratch schema for ' || :participant || '''';

    -- Give the lab role full control of this schema so the participant can
    -- create notebooks, tables, and UDFs inside it.
    EXECUTE IMMEDIATE 'GRANT ALL ON SCHEMA ' || :full_name || ' TO ROLE GUARDANT_LAB';

    RETURN 'Your lab schema is ready: ' || :full_name
        || ' — run: USE SCHEMA ' || :full_name;
END;
$$;

GRANT USAGE ON PROCEDURE CLAIM_MY_LAB_SCHEMA() TO ROLE IDENTIFIER($lab_role);


-- ---------------------------------------------------------------------------
-- 5. Grant the role to the six participants.
--
-- REPLACE THESE with the real usernames from PREREQUISITES.md step 3.
-- Add spares — granting a role costs nothing, interrupting the session does.
--
-- Uncomment and edit:
-- ---------------------------------------------------------------------------
-- GRANT ROLE IDENTIFIER($lab_role) TO USER "participant_one";
-- GRANT ROLE IDENTIFIER($lab_role) TO USER "participant_two";
-- GRANT ROLE IDENTIFIER($lab_role) TO USER "participant_three";
-- GRANT ROLE IDENTIFIER($lab_role) TO USER "participant_four";
-- GRANT ROLE IDENTIFIER($lab_role) TO USER "participant_five";
-- GRANT ROLE IDENTIFIER($lab_role) TO USER "participant_six";

/* If you revoked CREATE SCHEMA in section 3, pre-create each participant's
   schema instead of having them call the procedure:

     CREATE SCHEMA IF NOT EXISTS GUARDANT_LAB.LAB_<USERNAME>;
     GRANT ALL ON SCHEMA GUARDANT_LAB.LAB_<USERNAME> TO ROLE GUARDANT_LAB;   */


-- ---------------------------------------------------------------------------
-- 6. Verify
-- ---------------------------------------------------------------------------
SELECT 'Lab infrastructure created' AS status,
       $lab_db    AS database,
       $lab_wh    AS warehouse,
       $lab_role  AS role;

SHOW GRANTS TO ROLE GUARDANT_LAB;

/* NEXT — generate the dataset. Both scripts default to DEMO.GUARDANT_DEMO, so
   set the context explicitly if your lab_db is different:

     USE SCHEMA GUARDANT_LAB.GUARDANT_DEMO;
     -- then run the body of setup/01_synthetic_data.sql and setup/02_udf.sql

   Expected result: VARIANT_CALLS = 20,000,000 rows, about 30 seconds.

   Finally, confirm a participant can actually see the data:

     SELECT COUNT(*) FROM GUARDANT_LAB.GUARDANT_DEMO.VARIANT_CALLS;   */
