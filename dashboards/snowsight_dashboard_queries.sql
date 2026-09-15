/* ============================================================================
   Guardant Health — Snowflake Enablement Session
   dashboards/snowsight_dashboard_queries.sql

   Six tiles for the Snowsight segment of the session (~3 min).

   These are deliberately NOT built as a script to run end to end. Paste each
   block into its own Snowsight dashboard tile, pick the chart type noted in the
   comment, and you have a dashboard over the same governed data the notebooks
   used — no CSV export anywhere in the chain.

   The message for the analysts in the room: same data, same permissions, no
   Python required.
   ============================================================================ */

-- ---------------------------------------------------------------------------
-- TILE 1 — Cohort scale.  Chart: scorecard (one per metric, or a single row)
-- ---------------------------------------------------------------------------
SELECT
    (SELECT COUNT(*) FROM DEMO.GUARDANT_DEMO.PATIENTS)       AS patients,
    (SELECT COUNT(*) FROM DEMO.GUARDANT_DEMO.SPECIMENS)      AS blood_draws,
    (SELECT COUNT(*) FROM DEMO.GUARDANT_DEMO.VARIANT_CALLS)  AS raw_variant_calls,
    (SELECT COUNT(*) FROM DEMO.GUARDANT_DEMO.PATHOLOGY_REPORTS) AS pathology_reports;


-- ---------------------------------------------------------------------------
-- TILE 2 — Actionable findings by cancer type.  Chart: horizontal bar
-- The clinically meaningful view: how many patients have something targetable.
-- ---------------------------------------------------------------------------
SELECT
    primary_cancer_type,
    COUNT(DISTINCT patient_id) AS patients_with_actionable_variant
FROM DEMO.GUARDANT_DEMO.V_REPORTABLE_VARIANTS
WHERE is_actionable
  AND vaf >= 0.05
GROUP BY primary_cancer_type
ORDER BY patients_with_actionable_variant DESC
LIMIT 12;


-- ---------------------------------------------------------------------------
-- TILE 3 — Mutation burden by gene.  Chart: bar
-- ---------------------------------------------------------------------------
SELECT
    gene_symbol,
    COUNT(*)                    AS reportable_calls,
    COUNT(DISTINCT specimen_id) AS specimens_affected
FROM DEMO.GUARDANT_DEMO.V_REPORTABLE_VARIANTS
GROUP BY gene_symbol
ORDER BY reportable_calls DESC
LIMIT 15;


-- ---------------------------------------------------------------------------
-- TILE 4 — Specimen QC over time.  Chart: line, series = qc_status
-- An operational view a lab ops lead would actually want on a wall.
-- ---------------------------------------------------------------------------
SELECT
    DATE_TRUNC('week', collection_date) AS week,
    qc_status,
    COUNT(*)                            AS specimens
FROM DEMO.GUARDANT_DEMO.SPECIMENS
WHERE collection_date >= DATEADD(month, -12, CURRENT_DATE())
GROUP BY week, qc_status
ORDER BY week, qc_status;


-- ---------------------------------------------------------------------------
-- TILE 5 — Tumour fraction vs detection yield.  Chart: bar
-- Makes the assay-sensitivity relationship visible: low tumour fraction draws
-- yield fewer reportable calls. This is the kind of question that currently
-- requires an extract.
-- ---------------------------------------------------------------------------
SELECT
    CASE
        WHEN tumor_fraction < 0.001 THEN '1. <0.1%'
        WHEN tumor_fraction < 0.005 THEN '2. 0.1-0.5%'
        WHEN tumor_fraction < 0.02  THEN '3. 0.5-2%'
        WHEN tumor_fraction < 0.10  THEN '4. 2-10%'
        ELSE                             '5. >10%'
    END                                          AS tumor_fraction_band,
    COUNT(DISTINCT specimen_id)                  AS specimens,
    ROUND(AVG(calls_per_specimen), 1)            AS avg_reportable_calls
FROM (
    SELECT s.specimen_id,
           s.tumor_fraction,
           COUNT(v.variant_call_id) AS calls_per_specimen
    FROM DEMO.GUARDANT_DEMO.SPECIMENS s
    LEFT JOIN DEMO.GUARDANT_DEMO.VARIANT_CALLS v
           ON v.specimen_id = s.specimen_id
          AND v.call_filter = 'PASS'
    WHERE s.qc_status = 'PASS'
    GROUP BY s.specimen_id, s.tumor_fraction
)
GROUP BY tumor_fraction_band
ORDER BY tumor_fraction_band;


-- ---------------------------------------------------------------------------
-- TILE 6 — Therapy match list.  Chart: table
-- The output a molecular tumour board would consume directly.
-- ---------------------------------------------------------------------------
SELECT
    gene_symbol,
    targeted_therapy,
    COUNT(DISTINCT patient_id) AS patients,
    ROUND(MEDIAN(vaf) * 100, 2) AS median_vaf_pct
FROM DEMO.GUARDANT_DEMO.V_REPORTABLE_VARIANTS
WHERE is_actionable
  AND targeted_therapy IS NOT NULL
  AND vaf >= 0.05
GROUP BY gene_symbol, targeted_therapy
ORDER BY patients DESC
LIMIT 20;
