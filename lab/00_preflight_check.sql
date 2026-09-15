/* ============================================================================
   Guardant Health — Hands-On Lab
   00_preflight_check.sql

   RUN THIS IN GUARDANT'S ACCOUNT AT LEAST A WEEK BEFORE THE SESSION.

   Every check is read-only. Nothing is created, altered, or dropped.

   Purpose: find out what will block a hands-on session *before* six people are
   sitting in a room watching a red error message. Each check prints a verdict
   and, where it fails, what has to happen to fix it.

   Run as the role that will own the lab objects (see check 2).
   ============================================================================ */

SELECT '=== PREFLIGHT: ' || CURRENT_ACCOUNT() || ' as ' || CURRENT_ROLE() || ' ===' AS header;


-- ---------------------------------------------------------------------------
-- CHECK 1 — Region and edition.
--
-- Why it matters: Cortex LLM function availability is region-dependent, and
-- cross-region inference is off by default. Notebooks and Cortex both require
-- Enterprise edition or above.
-- ---------------------------------------------------------------------------
SELECT 'CHECK 1: region and edition' AS check_name,
       CURRENT_REGION()             AS region,
       CURRENT_ACCOUNT()            AS account,
       CURRENT_ORGANIZATION_NAME()  AS organization;

SHOW PARAMETERS LIKE 'CORTEX_ENABLED_CROSS_REGION' IN ACCOUNT;
-- Expect: a value. If 'DISABLED' and check 4 below fails, ask an ACCOUNTADMIN to
-- set CORTEX_ENABLED_CROSS_REGION = 'ANY_REGION' (or 'AWS_US'), or pick a model
-- that is native to this region.


-- ---------------------------------------------------------------------------
-- CHECK 2 — Can the running role create what the lab needs?
--
-- The lab needs: a database (or a schema in an existing one), a warehouse, a
-- role, and the ability to grant that role to six people.
-- ---------------------------------------------------------------------------
SELECT 'CHECK 2: role privileges' AS check_name;

-- SHOW GRANTS does not accept CURRENT_ROLE() or IDENTIFIER() — it needs a
-- literal role name. So this prints the exact statement to run next; copy the
-- output and execute it.
SELECT 'SHOW GRANTS TO ROLE ' || CURRENT_ROLE() || ';' AS run_this_next;

-- Look for, on ACCOUNT: CREATE DATABASE, CREATE WAREHOUSE, CREATE ROLE.
-- If the running role has none of these, the lab needs either SYSADMIN +
-- USERADMIN, or a purpose-made role. See PREREQUISITES.md.

-- A definitive, order-independent alternative if the role can read ACCOUNT_USAGE:
--   SELECT DISTINCT privilege, granted_on
--   FROM SNOWFLAKE.ACCOUNT_USAGE.GRANTS_TO_ROLES
--   WHERE grantee_name = CURRENT_ROLE()
--     AND granted_on = 'ACCOUNT'
--     AND deleted_on IS NULL;


-- ---------------------------------------------------------------------------
-- CHECK 3 — Are Notebooks available?
--
-- Why it matters: three of the six stations are notebooks. If Notebooks are not
-- enabled, the session structure has to change, not just the scripts.
-- ---------------------------------------------------------------------------
SELECT 'CHECK 3: notebooks' AS check_name;

SHOW NOTEBOOKS IN ACCOUNT LIMIT 1;
-- A clean run (even with zero rows) means the object type exists and the role
-- can see it. An "Unsupported feature" error is the blocker.


-- ---------------------------------------------------------------------------
-- CHECK 4 — Do the Cortex functions actually work here?
--
-- This is the check most likely to fail, and the one people assume will pass.
-- Each is a real call against a literal string, so it costs a negligible
-- amount of credit and tells you the truth.
-- ---------------------------------------------------------------------------
SELECT 'CHECK 4: cortex functions' AS check_name;

-- 4a — AI_COMPLETE with the model the notebooks name by default.
SELECT AI_COMPLETE('claude-4-sonnet',
                   'Reply with exactly the word: OK') AS ai_complete_claude4;
-- If this errors with "unknown model" or a region message, either enable
-- cross-region inference (check 1) or change the model in the notebooks.
-- Alternatives to try, in order of preference:
--   SELECT AI_COMPLETE('llama3.1-70b', 'Reply with exactly the word: OK');
--   SELECT AI_COMPLETE('mistral-large2', 'Reply with exactly the word: OK');

-- 4b — AI_EXTRACT: used in the Cortex station to pull fields out of prose.
SELECT AI_EXTRACT(
         text => 'Sequencing identified a missense variant in KRAS at 4.2% VAF.',
         responseFormat => {'gene': 'Which gene was altered?'}
       ) AS ai_extract_result;

-- 4c — AI_CLASSIFY: used for report triage.
SELECT AI_CLASSIFY('An actionable EGFR alteration was identified.',
                   ['actionable alteration found', 'no actionable alteration']
       ) AS ai_classify_result;

-- 4d — AI_AGG: reasons across a group of rows at once.
SELECT AI_AGG(txt, 'Summarise these findings in one short sentence.') AS ai_agg_result
FROM (SELECT 'KRAS G12C detected.' AS txt
      UNION ALL SELECT 'TP53 alteration detected.');


-- ---------------------------------------------------------------------------
-- CHECK 5 — Is outbound access to GitHub permitted?
--
-- THIS IS THE MOST LIKELY HARD BLOCKER IN A REGULATED HEALTHCARE ACCOUNT.
-- The GitHub station needs an API INTEGRATION reaching github.com. Many
-- life-sciences accounts restrict integration creation or egress entirely.
--
-- Read-only evidence first:
-- ---------------------------------------------------------------------------
SELECT 'CHECK 5: github egress' AS check_name;

SHOW API INTEGRATIONS;
-- Any existing GIT_HTTPS_API integration pointing at github.com is strong
-- evidence this is permitted. None at all is not proof it is blocked, but it
-- means nobody has done it before, so assume it needs approval.

SHOW NETWORK POLICIES IN ACCOUNT;
-- An egress-restricting policy here is a signal to ask the platform team
-- directly rather than discovering it live.

/* The only definitive test is to create one. Ask a Guardant admin to run:

     CREATE OR REPLACE API INTEGRATION GUARDANT_LAB_GITHUB_TEST
       API_PROVIDER = GIT_HTTPS_API
       API_ALLOWED_PREFIXES = ('https://github.com/sfc-gh-pmatson')
       ENABLED = TRUE;

     CREATE OR REPLACE GIT REPOSITORY GUARDANT_LAB_GIT_TEST
       API_INTEGRATION = GUARDANT_LAB_GITHUB_TEST
       ORIGIN = 'https://github.com/sfc-gh-pmatson/guardant-snowflake-enablement.git';

     ALTER GIT REPOSITORY GUARDANT_LAB_GIT_TEST FETCH;
     LS @GUARDANT_LAB_GIT_TEST/branches/main/notebooks/;

     -- then clean up:
     DROP GIT REPOSITORY GUARDANT_LAB_GIT_TEST;
     DROP API INTEGRATION GUARDANT_LAB_GITHUB_TEST;

   No credentials are needed: the demo repo is public.
   If FETCH fails, drop the GitHub station and demo it from Peter's account. */


-- ---------------------------------------------------------------------------
-- CHECK 6 — Is Cortex Code / CoCo reachable in Snowsight?
--
-- Not testable from SQL. Confirm by opening Snowsight as a participant and
-- looking for the Cortex Code entry point. If it is absent, the CoCo station
-- becomes a demo from Peter's laptop rather than hands-on.
-- ---------------------------------------------------------------------------
SELECT 'CHECK 6: cortex code — verify manually in Snowsight, not testable in SQL' AS check_name;


-- ---------------------------------------------------------------------------
-- CHECK 7 — Warehouse the participants can actually use.
-- ---------------------------------------------------------------------------
SELECT 'CHECK 7: warehouses visible to this role' AS check_name;

SHOW WAREHOUSES;
-- Six people running notebooks concurrently on one XSMALL will queue. The lab
-- setup creates its own MEDIUM warehouse; if creating one is not permitted,
-- identify an existing warehouse of at least SMALL that all six can use, and
-- set it in 01_admin_setup.sql.


-- ---------------------------------------------------------------------------
-- SUMMARY — record the answers here and send them to Peter before the session.
-- ---------------------------------------------------------------------------
SELECT 'PREFLIGHT COMPLETE — record results in PREREQUISITES.md' AS status,
       'Blockers to report: Cortex model (4a), GitHub egress (5), Notebooks (3)' AS attention;
