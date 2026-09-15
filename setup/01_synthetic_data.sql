/* ============================================================================
   Guardant Health — Snowflake Enablement Session
   01_synthetic_data.sql — generate the synthetic liquid-biopsy dataset

   Run after 00_setup.sql. Idempotent: CREATE OR REPLACE throughout, so
   re-running gives you a fresh (differently randomised) dataset.

   NOTHING HERE IS REAL PATIENT DATA. Every row is generated in-database from
   Snowflake's GENERATOR / RANDOM functions. There are no data files in this
   repo, which is deliberate — the whole dataset is reproducible from SQL.

   Target scale (~20M variant rows) is chosen so that the "just pull it into
   pandas on my laptop" approach is genuinely infeasible.

   Runtime on a MEDIUM warehouse: roughly 1-3 minutes.
   ============================================================================ */

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE GUARDANT_DEMO_WH;
USE SCHEMA DEMO.GUARDANT_DEMO;

/* ---------------------------------------------------------------------------
   1. GENE_PANEL — reference data.

   A plausible solid-tumour ctDNA panel. Ordered deliberately: the most
   frequently mutated drivers come first, because the variant generator skews
   its gene draw toward low row numbers. That gives a realistic long-tail
   mutation frequency distribution instead of a flat one.
   --------------------------------------------------------------------------- */
CREATE OR REPLACE TABLE GENE_PANEL (
    gene_idx            NUMBER(4)     NOT NULL,
    gene_symbol         VARCHAR(20)   NOT NULL,
    chromosome          VARCHAR(5)    NOT NULL,
    region_start        NUMBER(12)    NOT NULL,
    region_length       NUMBER(9)     NOT NULL,
    is_actionable       BOOLEAN       NOT NULL,
    targeted_therapy    VARCHAR(120)
)
COMMENT = 'Synthetic ctDNA gene panel definition';

INSERT INTO GENE_PANEL
    (gene_idx, gene_symbol, chromosome, region_start, region_length, is_actionable, targeted_therapy)
VALUES
    ( 1, 'TP53',   'chr17',  7668402,  25760, FALSE, NULL),
    ( 2, 'KRAS',   'chr12', 25205246,  45690, TRUE,  'sotorasib (G12C); adagrasib (G12C)'),
    ( 3, 'PIK3CA', 'chr3',  179148114, 91250, TRUE,  'alpelisib'),
    ( 4, 'EGFR',   'chr7',  55019017, 193710, TRUE,  'osimertinib; erlotinib; amivantamab'),
    ( 5, 'APC',    'chr5',  112707498,138150, FALSE, NULL),
    ( 6, 'BRAF',   'chr7',  140719327, 205400, TRUE,  'dabrafenib + trametinib (V600E); encorafenib'),
    ( 7, 'PTEN',   'chr10', 87863625, 108500, FALSE, NULL),
    ( 8, 'NRAS',   'chr1',  114704469, 12490, FALSE, NULL),
    ( 9, 'ERBB2',  'chr17', 39687914,  40390, TRUE,  'trastuzumab deruxtecan; tucatinib'),
    (10, 'BRCA1',  'chr17', 43044295,  81190, TRUE,  'olaparib; niraparib'),
    (11, 'BRCA2',  'chr13', 32315474,  84190, TRUE,  'olaparib; rucaparib'),
    (12, 'MET',    'chr7',  116672196,125980, TRUE,  'capmatinib; tepotinib'),
    (13, 'ALK',    'chr2',  29192774, 728280, TRUE,  'alectinib; lorlatinib'),
    (14, 'CDKN2A', 'chr9',  21967752,   7810, FALSE, NULL),
    (15, 'SMAD4',  'chr18', 51028394,  57990, FALSE, NULL),
    (16, 'FBXW7',  'chr4',  152320544, 40530, FALSE, NULL),
    (17, 'ARID1A', 'chr1',  26696015,  86510, FALSE, NULL),
    (18, 'CTNNB1', 'chr3',  41194741,  47990, FALSE, NULL),
    (19, 'RB1',    'chr13', 48303748, 178170, FALSE, NULL),
    (20, 'ATM',    'chr11', 108222484,146590, TRUE,  'olaparib (investigational)'),
    (21, 'IDH1',   'chr2',  208236227, 27310, TRUE,  'ivosidenib'),
    (22, 'IDH2',   'chr15', 90083045,  19240, TRUE,  'enasidenib'),
    (23, 'FGFR2',  'chr10', 121478330,119510, TRUE,  'pemigatinib; futibatinib'),
    (24, 'FGFR3',  'chr4',  1793293,   16860, TRUE,  'erdafitinib'),
    (25, 'RET',    'chr10', 43077069,  53320, TRUE,  'selpercatinib; pralsetinib'),
    (26, 'ROS1',   'chr6',  117287118,183170, TRUE,  'crizotinib; entrectinib'),
    (27, 'NTRK1',  'chr1',  156874906, 66690, TRUE,  'larotrectinib; entrectinib'),
    (28, 'KIT',    'chr4',  54657918,  82620, TRUE,  'imatinib; ripretinib'),
    (29, 'PDGFRA', 'chr4',  54229097,  71180, TRUE,  'avapritinib'),
    (30, 'AKT1',   'chr14', 104769349, 26550, TRUE,  'capivasertib'),
    (31, 'ESR1',   'chr6',  151656691,474290, TRUE,  'elacestrant'),
    (32, 'GATA3',  'chr10', 8045378,   23470, FALSE, NULL),
    (33, 'MAP2K1', 'chr15', 66386837,  103110,FALSE, NULL),
    (34, 'JAK2',   'chr9',  4984390,   148630,FALSE, NULL),
    (35, 'STK11',  'chr19', 1205778,    22940,FALSE, NULL),
    (36, 'KEAP1',  'chr19', 10486125,   21470,FALSE, NULL),
    (37, 'NF1',    'chr17', 31094927,  282750,FALSE, NULL),
    (38, 'NOTCH1', 'chr9',  136494433,  51330,FALSE, NULL),
    (39, 'MYC',    'chr8',  127735434,   6570,FALSE, NULL),
    (40, 'CCND1',  'chr11', 69641156,   13390,FALSE, NULL),
    (41, 'CDK4',   'chr12', 57747727,   10360,TRUE,  'palbociclib; abemaciclib'),
    (42, 'CDK6',   'chr7',  92604921,  231790,TRUE,  'ribociclib'),
    (43, 'MDM2',   'chr12', 68808172,   34530,FALSE, NULL),
    (44, 'TERT',   'chr5',  1253167,    41930,FALSE, NULL),
    (45, 'VHL',    'chr3',  10141778,   14500,FALSE, NULL),
    (46, 'MLH1',   'chr3',  36993350,   57910,TRUE,  'pembrolizumab (MSI-H)'),
    (47, 'MSH2',   'chr2',  47403067,   80070,TRUE,  'pembrolizumab (MSI-H)'),
    (48, 'MSH6',   'chr2',  47783145,   25350,TRUE,  'pembrolizumab (MSI-H)'),
    (49, 'PMS2',   'chr7',  5970925,    35850,TRUE,  'pembrolizumab (MSI-H)'),
    (50, 'PALB2',  'chr16', 23603160,   38160,TRUE,  'olaparib (investigational)'),
    (51, 'CHEK2',  'chr22', 28687743,   54700,FALSE, NULL),
    (52, 'RAD51C', 'chr17', 58692602,   41120,FALSE, NULL),
    (53, 'BARD1',  'chr2',  214725646,  84980,FALSE, NULL),
    (54, 'CDH1',   'chr16', 68737225,   98250,FALSE, NULL),
    (55, 'SMARCB1','chr22', 23786966,   50060,FALSE, NULL),
    (56, 'TSC1',   'chr9',  132891349,  54930,FALSE, NULL),
    (57, 'TSC2',   'chr16', 2047986,    43520,FALSE, NULL),
    (58, 'MTOR',   'chr1',  11106535,  156010,TRUE,  'everolimus'),
    (59, 'GNAS',   'chr20', 58839718,  71800, FALSE, NULL),
    (60, 'POLE',   'chr12', 132623126, 79920, TRUE,  'pembrolizumab (TMB-H)');

/* ---------------------------------------------------------------------------
   2. PATIENTS — 50,000 synthetic patients.

   Cancer type is drawn with a skew so that lung / colorectal / breast dominate,
   matching the case mix of a broad ctDNA testing business.
   --------------------------------------------------------------------------- */
CREATE OR REPLACE TABLE PATIENTS (
    patient_id          VARCHAR(16)   NOT NULL,
    birth_year          NUMBER(4)     NOT NULL,
    sex                 VARCHAR(10)   NOT NULL,
    primary_cancer_type VARCHAR(40)   NOT NULL,
    stage_at_diagnosis  VARCHAR(6)    NOT NULL,
    smoking_history     VARCHAR(20)   NOT NULL,
    enrollment_date     DATE          NOT NULL
)
COMMENT = 'Synthetic patient roster — no real patient data';

INSERT INTO PATIENTS
WITH raw AS (
    SELECT
        seq4()                                                        AS n,
        UNIFORM(0::FLOAT, 1::FLOAT, RANDOM())                         AS u_cancer,
        UNIFORM(0::FLOAT, 1::FLOAT, RANDOM())                         AS u_stage
    FROM TABLE(GENERATOR(ROWCOUNT => 50000))
)
SELECT
    'PT-' || LPAD(TO_VARCHAR(n + 100000), 8, '0')                     AS patient_id,
    UNIFORM(1938, 1998, RANDOM())                                     AS birth_year,
    GET(ARRAY_CONSTRUCT('Female','Male'), UNIFORM(0, 1, RANDOM()))::VARCHAR AS sex,
    -- squaring the uniform draw pushes mass toward the head of the array
    GET(
        ARRAY_CONSTRUCT(
            'Non-Small Cell Lung','Colorectal','Breast','Prostate','Pancreatic',
            'Gastroesophageal','Ovarian','Bladder','Hepatocellular','Melanoma',
            'Head and Neck','Renal Cell','Cholangiocarcinoma','Endometrial',
            'Small Cell Lung','Sarcoma','Unknown Primary'
        ),
        LEAST(FLOOR(POWER(u_cancer, 1.7) * 17)::INT, 16)
    )::VARCHAR                                                        AS primary_cancer_type,
    -- advanced disease dominates, as you would expect in a liquid-biopsy cohort
    GET(
        ARRAY_CONSTRUCT('IV','IV','IV','III','III','II','I'),
        LEAST(FLOOR(u_stage * 7)::INT, 6)
    )::VARCHAR                                                        AS stage_at_diagnosis,
    GET(
        ARRAY_CONSTRUCT('Never','Former','Current','Unknown'),
        UNIFORM(0, 3, RANDOM())
    )::VARCHAR                                                        AS smoking_history,
    DATEADD(day, UNIFORM(-1460, -1, RANDOM()), CURRENT_DATE())        AS enrollment_date
FROM raw;

/* ---------------------------------------------------------------------------
   3. SPECIMENS — 120,000 blood draws (patients are tested serially, which is
   the point of a liquid biopsy: you can re-draw as therapy progresses).

   tumor_fraction and ctdna_input_ng are the QC levers a bioinformatician
   actually cares about, so they carry realistic skew: most draws are low
   tumour fraction, a minority are rich.
   --------------------------------------------------------------------------- */
CREATE OR REPLACE TABLE SPECIMENS (
    specimen_id      VARCHAR(20)   NOT NULL,
    patient_id       VARCHAR(16)   NOT NULL,
    collection_date  DATE          NOT NULL,
    assay            VARCHAR(30)   NOT NULL,
    draw_number      NUMBER(3)     NOT NULL,
    tumor_fraction   NUMBER(7,5)   NOT NULL,
    ctdna_input_ng   NUMBER(7,2)   NOT NULL,
    mean_depth       NUMBER(7)     NOT NULL,
    qc_status        VARCHAR(12)   NOT NULL,
    lab_site         VARCHAR(20)   NOT NULL
)
COMMENT = 'Synthetic specimen / blood-draw records';

INSERT INTO SPECIMENS
WITH raw AS (
    SELECT
        seq4()                                        AS n,
        UNIFORM(1, 50000, RANDOM())                   AS patient_n,
        UNIFORM(0::FLOAT, 1::FLOAT, RANDOM())         AS u_tf,
        UNIFORM(0::FLOAT, 1::FLOAT, RANDOM())         AS u_qc
    FROM TABLE(GENERATOR(ROWCOUNT => 120000))
),
shaped AS (
    SELECT
        n,
        patient_n,
        -- cubing the draw gives a long low-tumour-fraction tail
        ROUND(POWER(u_tf, 3) * 0.42 + 0.00050, 5)     AS tumor_fraction,
        u_qc
    FROM raw
)
SELECT
    'SPEC-' || LPAD(TO_VARCHAR(n + 500000), 9, '0')   AS specimen_id,
    'PT-'   || LPAD(TO_VARCHAR(patient_n + 99999), 8, '0') AS patient_id,
    DATEADD(day, UNIFORM(-1095, 0, RANDOM()), CURRENT_DATE()) AS collection_date,
    GET(
        ARRAY_CONSTRUCT(
            'CTDNA-360-PANEL','CTDNA-360-PANEL','CTDNA-360-PANEL',
            'SCREEN-METHYL-V2','RESPONSE-MRD-V1'
        ),
        UNIFORM(0, 4, RANDOM())
    )::VARCHAR                                        AS assay,
    UNIFORM(1, 6, RANDOM())                           AS draw_number,
    tumor_fraction                                    AS tumor_fraction,
    ROUND(UNIFORM(5::FLOAT, 95::FLOAT, RANDOM()), 2)  AS ctdna_input_ng,
    UNIFORM(1200, 9500, RANDOM())                     AS mean_depth,
    -- low tumour fraction correlates with QC trouble, as in real assays
    CASE
        WHEN u_qc < 0.02                            THEN 'FAIL'
        WHEN tumor_fraction < 0.002 AND u_qc < 0.35 THEN 'REVIEW'
        ELSE 'PASS'
    END                                               AS qc_status,
    GET(
        ARRAY_CONSTRUCT('REDWOOD-CITY','PALO-ALTO','SAN-DIEGO'),
        UNIFORM(0, 2, RANDOM())
    )::VARCHAR                                        AS lab_site
FROM shaped;

/* ---------------------------------------------------------------------------
   4. VARIANT_CALLS — ~20,000,000 rows. This is the table that makes the point.

   ~167 raw calls per specimen, which is what you get BEFORE filtering: real
   variants plus sequencing noise. The demos filter this down live, which is
   exactly the workload the team currently drags onto a laptop.

   Clustered on (chromosome, gene_symbol) so the pruning story is demonstrable.
   --------------------------------------------------------------------------- */
CREATE OR REPLACE TABLE VARIANT_CALLS (
    variant_call_id       NUMBER(12)    NOT NULL,
    specimen_id           VARCHAR(20)   NOT NULL,
    gene_symbol           VARCHAR(20)   NOT NULL,
    chromosome            VARCHAR(5)    NOT NULL,
    position              NUMBER(12)    NOT NULL,
    ref_allele            VARCHAR(4)    NOT NULL,
    alt_allele            VARCHAR(4)    NOT NULL,
    variant_type          VARCHAR(12)   NOT NULL,
    consequence           VARCHAR(30)   NOT NULL,
    vaf                   NUMBER(7,5)   NOT NULL,
    read_depth            NUMBER(7)     NOT NULL,
    alt_read_count        NUMBER(7)     NOT NULL,
    mapping_quality       NUMBER(4)     NOT NULL,
    clinical_significance VARCHAR(24)   NOT NULL,
    call_filter           VARCHAR(16)   NOT NULL
)
CLUSTER BY (chromosome, gene_symbol)
COMMENT = 'Synthetic raw variant calls — ~20M rows, pre-filter';

INSERT INTO VARIANT_CALLS
WITH raw AS (
    SELECT
        seq4()                                   AS n,
        UNIFORM(1, 120000, RANDOM())             AS specimen_n,
        UNIFORM(0::FLOAT, 1::FLOAT, RANDOM())    AS u_gene,
        UNIFORM(0::FLOAT, 1::FLOAT, RANDOM())    AS u_vaf,
        UNIFORM(0::FLOAT, 1::FLOAT, RANDOM())    AS u_cons,
        UNIFORM(0::FLOAT, 1::FLOAT, RANDOM())    AS u_type,
        UNIFORM(1000, 9500, RANDOM())            AS read_depth,
        UNIFORM(20, 60, RANDOM())                AS mapping_quality,
        UNIFORM(0::FLOAT, 1::FLOAT, RANDOM())    AS u_pos
    FROM TABLE(GENERATOR(ROWCOUNT => 20000000))
),
shaped AS (
    SELECT
        n,
        specimen_n,
        -- squared draw over a panel ordered by mutation frequency
        1 + LEAST(FLOOR(POWER(u_gene, 2) * 60)::INT, 59)     AS gene_idx,
        -- cubed draw: the vast majority of calls are low-VAF, a few are clonal
        ROUND(POWER(u_vaf, 3) * 0.48 + 0.00020, 5) AS vaf,
        u_cons,
        u_type,
        read_depth,
        mapping_quality,
        u_pos
    FROM raw
)
SELECT
    s.n + 1                                                          AS variant_call_id,
    'SPEC-' || LPAD(TO_VARCHAR(s.specimen_n + 499999), 9, '0')       AS specimen_id,
    g.gene_symbol                                                    AS gene_symbol,
    g.chromosome                                                     AS chromosome,
    g.region_start + LEAST(FLOOR(s.u_pos * g.region_length)::INT, g.region_length - 1) AS position,
    GET(ARRAY_CONSTRUCT('A','C','G','T'), UNIFORM(0, 3, RANDOM()))::VARCHAR AS ref_allele,
    GET(ARRAY_CONSTRUCT('A','C','G','T'), UNIFORM(0, 3, RANDOM()))::VARCHAR AS alt_allele,
    CASE
        WHEN s.u_type < 0.86 THEN 'SNV'
        WHEN s.u_type < 0.94 THEN 'INSERTION'
        WHEN s.u_type < 0.99 THEN 'DELETION'
        ELSE 'MNV'
    END                                                              AS variant_type,
    GET(
        ARRAY_CONSTRUCT(
            'missense_variant','missense_variant','synonymous_variant',
            'intron_variant','intron_variant','stop_gained',
            'frameshift_variant','splice_site_variant','5_prime_UTR_variant'
        ),
        LEAST(FLOOR(s.u_cons * 9)::INT, 8)
    )::VARCHAR                                                       AS consequence,
    s.vaf                                                            AS vaf,
    s.read_depth                                                     AS read_depth,
    GREATEST(1, ROUND(s.read_depth * s.vaf))                         AS alt_read_count,
    s.mapping_quality                                                AS mapping_quality,
    CASE
        WHEN g.is_actionable AND s.vaf > 0.05 AND s.u_cons < 0.24 THEN 'Pathogenic'
        WHEN g.is_actionable AND s.vaf > 0.01                     THEN 'Likely pathogenic'
        WHEN s.u_cons < 0.24 AND s.vaf > 0.02                     THEN 'Likely pathogenic'
        WHEN s.u_cons > 0.66                                      THEN 'Benign'
        ELSE 'Uncertain significance'
    END                                                              AS clinical_significance,
    -- the noise floor: this is what the demos filter out
    CASE
        WHEN s.mapping_quality < 30                    THEN 'low_mapq'
        WHEN s.read_depth < 1500                       THEN 'low_depth'
        WHEN s.vaf < 0.0025                            THEN 'low_vaf'
        WHEN GREATEST(1, ROUND(s.read_depth * s.vaf)) < 5 THEN 'low_alt_reads'
        ELSE 'PASS'
    END                                                              AS call_filter
FROM shaped s
JOIN GENE_PANEL g
  ON g.gene_idx = s.gene_idx;

/* ---------------------------------------------------------------------------
   5. PATHOLOGY_REPORTS — 2,000 free-text reports for the Cortex AI demo.

   Deliberately narrative and inconsistent, the way real dictated reports are:
   the facts are in prose, not columns. That is the whole reason to reach for
   AI_EXTRACT / AI_COMPLETE rather than regex.
   --------------------------------------------------------------------------- */
CREATE OR REPLACE TABLE PATHOLOGY_REPORTS (
    report_id       VARCHAR(20)   NOT NULL,
    specimen_id     VARCHAR(20)   NOT NULL,
    patient_id      VARCHAR(16)   NOT NULL,
    report_date     DATE          NOT NULL,
    pathologist     VARCHAR(40)   NOT NULL,
    report_text     VARCHAR(4000) NOT NULL
)
COMMENT = 'Synthetic free-text pathology narratives for Cortex AI demos';

INSERT INTO PATHOLOGY_REPORTS
WITH picked AS (
    SELECT
        s.specimen_id,
        s.patient_id,
        s.collection_date,
        s.assay,
        s.tumor_fraction,
        p.primary_cancer_type,
        p.stage_at_diagnosis,
        p.birth_year,
        p.sex,
        ROW_NUMBER() OVER (ORDER BY s.specimen_id) AS rn
    FROM SPECIMENS s
    JOIN PATIENTS  p ON p.patient_id = s.patient_id
    WHERE s.qc_status = 'PASS'
    LIMIT 2000
),
top_variant AS (
    SELECT
        v.specimen_id,
        v.gene_symbol,
        v.consequence,
        v.vaf,
        ROW_NUMBER() OVER (PARTITION BY v.specimen_id ORDER BY v.vaf DESC) AS vrn
    FROM VARIANT_CALLS v
    JOIN picked pk ON pk.specimen_id = v.specimen_id
    WHERE v.call_filter = 'PASS'
)
SELECT
    'RPT-' || LPAD(TO_VARCHAR(pk.rn + 700000), 9, '0')  AS report_id,
    pk.specimen_id                                      AS specimen_id,
    pk.patient_id                                       AS patient_id,
    DATEADD(day, UNIFORM(2, 14, RANDOM()), pk.collection_date) AS report_date,
    GET(
        ARRAY_CONSTRUCT(
            'Dr. A. Reyes','Dr. M. Okonkwo','Dr. S. Lindqvist',
            'Dr. J. Nakamura','Dr. P. Ferreira','Dr. H. Bakshi'
        ),
        UNIFORM(0, 5, RANDOM())
    )::VARCHAR                                          AS pathologist,
    'CLINICAL HISTORY: '
      || (YEAR(pk.collection_date) - pk.birth_year) || '-year-old '
      || LOWER(pk.sex) || ' with stage ' || pk.stage_at_diagnosis || ' '
      || pk.primary_cancer_type || '. '
      || GET(ARRAY_CONSTRUCT(
             'Progression on first-line therapy. ',
             'Referred for therapy selection at progression. ',
             'Surveillance draw, no clinical evidence of progression. ',
             'Rising tumour marker prompted repeat testing. ',
             'Post-operative baseline draw. '
         ), UNIFORM(0, 4, RANDOM()))::VARCHAR
      || CHR(10) || CHR(10)
      || 'SPECIMEN: Peripheral blood, ' || pk.assay
      || ', collected ' || TO_VARCHAR(pk.collection_date, 'DD Mon YYYY') || '. '
      || 'Estimated circulating tumour fraction ' || TO_VARCHAR(ROUND(pk.tumor_fraction * 100, 2)) || '%.'
      || CHR(10) || CHR(10)
      || 'FINDINGS: Cell-free DNA sequencing identified a '
      || REPLACE(LOWER(tv.consequence), '_', ' ')
      || ' in ' || tv.gene_symbol
      || ' at a variant allele frequency of ' || TO_VARCHAR(ROUND(tv.vaf * 100, 2)) || '%. '
      || GET(ARRAY_CONSTRUCT(
             'Additional low-level alterations of uncertain significance were observed and are not reported individually. ',
             'No other reportable alterations were detected above the assay threshold. ',
             'Several subclonal alterations were noted; correlation with prior tissue results is advised. ',
             'Copy-number analysis was non-contributory in this specimen. '
         ), UNIFORM(0, 3, RANDOM()))::VARCHAR
      || CHR(10) || CHR(10)
      || 'INTERPRETATION: '
      || GET(ARRAY_CONSTRUCT(
             'The detected alteration is associated with sensitivity to targeted therapy. Referral to molecular tumour board is recommended. ',
             'The detected alteration has no currently approved targeted therapy in this tumour type. Clinical trial enrolment may be appropriate. ',
             'Findings are consistent with the previously characterised tumour genotype; no new actionable alteration identified. ',
             'Findings suggest emergence of a resistance mechanism. Consideration of an alternative agent is advised. '
         ), UNIFORM(0, 3, RANDOM()))::VARCHAR
      || CHR(10) || CHR(10)
      || 'NOTE: Absence of a detectable alteration does not exclude its presence below the limit of detection of this assay. '
      || 'This is SYNTHETIC data generated for demonstration purposes and must not be used clinically.'
                                                        AS report_text
FROM picked pk
JOIN top_variant tv
  ON tv.specimen_id = pk.specimen_id AND tv.vrn = 1;

/* ---------------------------------------------------------------------------
   6. Convenience view — the "analysis-ready" join the team would otherwise
   rebuild by hand in pandas every time.
   --------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW V_REPORTABLE_VARIANTS
COMMENT = 'PASS-filter variant calls joined to specimen, patient, and panel context'
AS
SELECT
    v.variant_call_id,
    v.specimen_id,
    s.patient_id,
    p.primary_cancer_type,
    p.stage_at_diagnosis,
    s.collection_date,
    s.assay,
    s.tumor_fraction,
    s.lab_site,
    v.gene_symbol,
    v.chromosome,
    v.position,
    v.variant_type,
    v.consequence,
    v.vaf,
    v.read_depth,
    v.alt_read_count,
    v.mapping_quality,
    v.clinical_significance,
    g.is_actionable,
    g.targeted_therapy
FROM VARIANT_CALLS v
JOIN SPECIMENS  s ON s.specimen_id = v.specimen_id
JOIN PATIENTS   p ON p.patient_id  = s.patient_id
JOIN GENE_PANEL g ON g.gene_symbol = v.gene_symbol
WHERE v.call_filter = 'PASS'
  AND s.qc_status   = 'PASS';
