/* ============================================================================
   Guardant Health — Hands-On Lab
   02_participant_setup.sql

   ===> RUN THIS FIRST, AT YOUR OWN KEYBOARD. Takes about 20 seconds. <===

   Open a Snowsight worksheet, paste this whole file in, and run it top to
   bottom. It gives you your own private working area so that nothing you do can
   affect anyone else in the room.

   If any step fails, put your hand up rather than trying to fix it — it is
   almost always a grant that needs adding, and that is a 10-second job.
   ============================================================================ */

-- ---------------------------------------------------------------------------
-- STEP 1 — Switch to the lab role and warehouse.
--
-- If USE ROLE fails: you have not been granted GUARDANT_LAB. Put your hand up.
-- ---------------------------------------------------------------------------
USE ROLE GUARDANT_LAB;
USE WAREHOUSE GUARDANT_LAB_WH;
USE SCHEMA GUARDANT_LAB.GUARDANT_DEMO;

-- ---------------------------------------------------------------------------
-- STEP 2 — Confirm you can see the shared dataset.
--
-- CHECKPOINT: you should get exactly 20,000,000.
-- ---------------------------------------------------------------------------
SELECT COUNT(*) AS variant_calls_i_can_see
FROM GUARDANT_LAB.GUARDANT_DEMO.VARIANT_CALLS;

-- ---------------------------------------------------------------------------
-- STEP 3 — Claim your own private schema.
--
-- This derives the name from your username, so you cannot collide with anyone
-- else and there is nothing to choose. Read the message it returns — it tells
-- you your schema name.
-- ---------------------------------------------------------------------------
CALL GUARDANT_LAB.GUARDANT_DEMO.CLAIM_MY_LAB_SCHEMA();

-- ---------------------------------------------------------------------------
-- STEP 4 — Move into your schema.
--
-- Paste the USE SCHEMA statement that step 3 gave you. It looks like:
--     USE SCHEMA GUARDANT_LAB.LAB_<YOUR_USERNAME>
--
-- Or just run this, which works it out for you:
-- ---------------------------------------------------------------------------
SET my_schema = 'GUARDANT_LAB.LAB_'
                || UPPER(REGEXP_REPLACE(CURRENT_USER(), '[^A-Za-z0-9]', '_'));

USE SCHEMA IDENTIFIER($my_schema);

-- ---------------------------------------------------------------------------
-- STEP 5 — Prove you can write in your own space.
--
-- CHECKPOINT: this should return one row saying 'ready'.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE MY_FIRST_TABLE AS
SELECT 'ready' AS status, CURRENT_USER() AS me, CURRENT_SCHEMA() AS my_schema;

SELECT * FROM MY_FIRST_TABLE;

-- ---------------------------------------------------------------------------
-- YOU ARE SET UP.
--
-- Your working area:  GUARDANT_LAB.LAB_<YOUR_USERNAME>   (you can write here)
-- The shared data:    GUARDANT_LAB.GUARDANT_DEMO         (read-only, 20M rows)
--
-- Now open lab/PARTICIPANT_GUIDE.md and go to Station 1.
-- ---------------------------------------------------------------------------
SELECT 'Setup complete'                     AS status,
       CURRENT_USER()                       AS you,
       CURRENT_ROLE()                       AS role,
       CURRENT_WAREHOUSE()                  AS warehouse,
       CURRENT_DATABASE() || '.' || CURRENT_SCHEMA() AS your_working_area;
