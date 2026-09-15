/* ============================================================================
   Guardant Health — Snowflake Enablement Session
   02_udf.sql — pre-seed the variant confidence UDF

   Run after 01_synthetic_data.sql.

   WHY THIS EXISTS: notebook 2 registers this same UDF live, from Python, which
   is the point being demonstrated. But if you jump straight to the SQL cell
   that calls it — or run the notebooks out of order in front of the customer —
   the call would fail on a missing function. Pre-seeding it here makes every
   cell independently runnable. The Python registration in the notebook uses
   replace=True, so it simply overwrites this definition.
   ============================================================================ */

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE GUARDANT_DEMO_WH;
USE SCHEMA DEMO.GUARDANT_DEMO;

CREATE OR REPLACE FUNCTION VARIANT_CONFIDENCE_SCORE(
    vaf        FLOAT,
    depth      INT,
    alt_reads  INT,
    mapq       INT,
    actionable BOOLEAN
)
RETURNS FLOAT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
HANDLER = 'confidence_score'
COMMENT = 'Composite confidence that a call is a true somatic variant worth reporting (0-100)'
AS
$$
def confidence_score(vaf, depth, alt_reads, mapq, actionable):
    if vaf is None or depth is None or alt_reads is None or mapq is None:
        return 0.0
    score = 0.0
    score += min(vaf / 0.10, 1.0) * 35                  # allele fraction
    score += min(depth / 5000.0, 1.0) * 25              # coverage
    score += min(alt_reads / 50.0, 1.0) * 20            # supporting reads
    score += min(max(mapq - 20, 0) / 40.0, 1.0) * 15    # mapping quality
    if actionable:
        score += 5                                      # clinical relevance nudge
    return round(min(score, 100.0), 2)
$$;

SELECT 'UDF registered' AS status,
       VARIANT_CONFIDENCE_SCORE(0.12, 6000, 720, 55, TRUE) AS example_high_confidence,
       VARIANT_CONFIDENCE_SCORE(0.003, 1200, 4, 25, FALSE) AS example_low_confidence;
