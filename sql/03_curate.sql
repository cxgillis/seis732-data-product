--
-- 1. Set up Staging and Curated tables for initial run.
--

CREATE OR REPLACE TABLE `seis732-508701.seis732_project.union_charges_stg` (
    `year` INT, provider_id_std STRING, provider_name STRING, provider_city STRING, provider_state STRING,
    drg_code STRING, drg_label STRING, drg_definition STRING, total_discharges INT64, average_covered_charges FLOAT64,
    average_total_payments FLOAT64, average_medicare_payments FLOAT64,
    rej_missing_key BOOL, rej_drg_pattern BOOL, rej_missing_measure BOOL, rej_nonpositive_payment BOOL,
    source_table STRING, load_date TIMESTAMP
);

CREATE OR REPLACE TABLE `seis732-508701.seis732_project.hospital_stg` (
    provider_id_std STRING, hospital_name STRING, city STRING, state STRING, hospital_type STRING,
    hospital_ownership STRING, rej_missing_key BOOL, source_table STRING, load_date TIMESTAMP,
    lookup_source STRING, src_rank INT, src_row_rnk INT
);

CREATE OR REPLACE TABLE `seis732-508701.seis732_project.rejected_rows` (
    source_table STRING, load_date TIMESTAMP, reject_reasons STRING, row_json STRING
);

CREATE OR REPLACE TABLE `seis732-508701.seis732_project.hospital_dim` (
    hospital_key INT NOT NULL, provider_id_std STRING, hospital_name STRING, city STRING, state STRING,
    hospital_type STRING, hospital_ownership STRING, lookup_source STRING
);

CREATE OR REPLACE TABLE `seis732-508701.seis732_project.drg_dim` (
    drg_id INT NOT NULL, drg_code STRING, drg_label STRING, first_year INT, last_year INT
);

CREATE OR REPLACE TABLE `seis732-508701.seis732_project.inpatient_charges_fact` (
    hospital_key INT NOT NULL, drg_id INT NOT NULL, year INT NOT NULL, total_discharges INT,
    average_covered_charges FLOAT64, total_covered_charges FLOAT64,
    average_medicare_payments FLOAT64, total_medicare_payments FLOAT64
);

--
-- 2. Load Staging Tables
--

-- Load the Charges union staging table for all years, along with quality check results
INSERT INTO `seis732-508701.seis732_project.union_charges_stg`
SELECT `year`, LPAD(provider_id, 6, '0') AS provider_id_std, provider_name, provider_city, provider_state
     , SUBSTR(drg_definition,1,3) as drg_code, TRIM(REGEXP_EXTRACT(drg_definition, r'^\d{3} - (.*)$')) AS drg_label
     , drg_definition, total_discharges, average_covered_charges, average_total_payments, average_medicare_payments
     -- Rule 1: key fields present
     , (year IS NULL OR provider_id IS NULL OR TRIM(provider_id) = '' OR drg_definition IS NULL) AS rej_missing_key
     -- Rule 2: DRG definition matches "NNN - label"
     , NOT IFNULL(REGEXP_CONTAINS(drg_definition, r'^\d{3} - .+'), FALSE) AS rej_drg_pattern
     -- Rule 3: discharges and charge fields present
     , (   total_discharges IS NULL OR average_covered_charges IS NULL OR average_total_payments IS NULL
        OR average_medicare_payments IS NULL) AS rej_missing_measure
     -- Rule 4: Medicare payments greater than zero
     , IFNULL(average_medicare_payments <= 0, FALSE) AS rej_nonpositive_payment
     , source_table, load_date
  FROM (SELECT 2011 AS `year`, provider_id, provider_name, provider_city, provider_state, drg_definition
             , total_discharges, average_covered_charges, average_total_payments, average_medicare_payments
             , 'inpatient_charges_2011_snapshot' AS source_table, load_date
          FROM `seis732-508701.seis732_project.inpatient_charges_2011_snapshot`
        UNION ALL
        SELECT 2012 AS `year`, provider_id, provider_name, provider_city, provider_state, drg_definition
             , total_discharges, average_covered_charges, average_total_payments, average_medicare_payments
             , 'inpatient_charges_2012_snapshot' AS source_table, load_date
        FROM `seis732-508701.seis732_project.inpatient_charges_2012_snapshot`
        UNION ALL
        SELECT 2013 AS `year`, provider_id, provider_name, provider_city, provider_state, drg_definition
             , total_discharges, average_covered_charges, average_total_payments, average_medicare_payments
             , 'inpatient_charges_2013_snapshot' AS source_table, load_date
        FROM `seis732-508701.seis732_project.inpatient_charges_2013_snapshot`
        UNION ALL
        SELECT 2014 AS `year`, provider_id, provider_name, provider_city, provider_state, drg_definition
             , total_discharges, average_covered_charges, average_total_payments, average_medicare_payments
             , 'inpatient_charges_2014_snapshot' AS source_table, load_date
        FROM `seis732-508701.seis732_project.inpatient_charges_2014_snapshot`
        UNION ALL
        SELECT 2015 AS `year`, provider_id, provider_name, provider_city, provider_state, drg_definition
             , total_discharges, average_covered_charges, average_total_payments, average_medicare_payments
             , 'inpatient_charges_2015_snapshot' AS source_table, load_date
        FROM `seis732-508701.seis732_project.inpatient_charges_2015_snapshot`
       ) all_years
;

-- Next load Hospital staging table and quality checks
INSERT INTO `seis732-508701.seis732_project.hospital_stg`
SELECT LPAD(provider_id, 6, '0') AS provider_id_std, hospital_name, city, state, hospital_type, hospital_ownership
     -- Rule 1: key fields present
     , (provider_id IS NULL OR TRIM(provider_id) = '') AS rej_missing_key
     , 'hospital_general_info_snapshot' AS source_table, load_date
     , 'lookup' AS lookup_source, 1 AS src_rank
     , ROW_NUMBER() OVER (PARTITION BY LPAD(provider_id, 6, '0')
         ORDER BY hospital_name ASC, TO_HEX(SHA256(TO_JSON_STRING(s))) DESC) AS src_row_rnk
  FROM `seis732-508701.seis732_project.hospital_general_info_snapshot` s
;

INSERT INTO `seis732-508701.seis732_project.hospital_stg`
SELECT provider_id_std, provider_name AS hospital_name, provider_city AS city, provider_state AS state
     , 'Unknown' AS hospital_type, 'Unknown' AS hospital_ownership
     -- Rule 1: key fields present
     , FALSE AS rej_missing_key
     , source_table, load_date
     , 'charges' AS lookup_source, 2 AS src_rank, 1 AS src_row_rnk
  FROM `seis732-508701.seis732_project.union_charges_stg` s
 WHERE NOT (rej_missing_key OR rej_drg_pattern OR rej_missing_measure OR rej_nonpositive_payment)
QUALIFY ROW_NUMBER() OVER (PARTITION BY provider_id_std
         ORDER BY year DESC, provider_name ASC, TO_HEX(SHA256(TO_JSON_STRING(s))) DESC)=1
;

--
-- 3. Apply Quality Checks and Capture Rejected Rows
--

-- Now select any Charge rows that fail quality checks and capture any violations to rejected_rows
INSERT INTO `seis732-508701.seis732_project.rejected_rows`
SELECT source_table, load_date
     , ARRAY_TO_STRING([IF(rej_missing_key,'missing_key',NULL),
                        IF(rej_drg_pattern,'drg_pattern',NULL),
                        IF(rej_missing_measure,'missing_measure',NULL),
                        IF(rej_nonpositive_payment,'nonpositive_payment',NULL)], ', ') AS reject_reasons
     , TO_JSON_STRING(s) AS row_json
  FROM `seis732-508701.seis732_project.union_charges_stg` s
 WHERE rej_missing_key OR rej_drg_pattern OR rej_missing_measure OR rej_nonpositive_payment;

-- Repeat rejected row handling for Hospital
INSERT INTO `seis732-508701.seis732_project.rejected_rows`
SELECT source_table, load_date
     , ARRAY_TO_STRING([IF(rej_missing_key,'missing_key',NULL)], ', ') AS reject_reasons
     , TO_JSON_STRING(s) AS row_json
  FROM `seis732-508701.seis732_project.hospital_stg` s
 WHERE rej_missing_key;

--
-- 4. Load Curated Fact and Dim tables
--

-- Start with Hospital Dim from hospital_general_info_snapshot
-- Set up Temp table to streamline MERGE statement, this will pull all hospitals from either source
-- FARM_FINGERPRINT() was suggested by AI as a deterministic way to create surrogate keys in BigQuery
CREATE OR REPLACE TEMP TABLE incoming_hospitals AS
SELECT FARM_FINGERPRINT(provider_id_std) AS hospital_key, provider_id_std, hospital_name
     , city, state, hospital_type, hospital_ownership, lookup_source
  FROM `seis732-508701.seis732_project.hospital_stg` s
 WHERE NOT rej_missing_key
QUALIFY ROW_NUMBER() OVER (PARTITION BY provider_id_std ORDER BY src_rank ASC, src_row_rnk ASC)=1
;

-- Using a MERGE here as good practice, even if not strictly necessary
MERGE `seis732-508701.seis732_project.hospital_dim` t
USING incoming_hospitals s
   ON t.provider_id_std = s.provider_id_std
 WHEN MATCHED THEN UPDATE SET
     hospital_name = s.hospital_name,
     city = s.city,
     state = s.state,
     hospital_type = s.hospital_type,
     hospital_ownership = s.hospital_ownership,
     lookup_source = s.lookup_source
 WHEN NOT MATCHED THEN INSERT ROW;

-- Next load DRG Dim

-- I had AI help with how to use a MERGE to build the existing year set records
-- It wanted to one-shot load, but I pushed instead of a loop to load year-by-year in order to future-proof any new years
FOR r IN (SELECT DISTINCT year FROM `seis732-508701.seis732_project.union_charges_stg` ORDER BY year)
DO
    MERGE `seis732-508701.seis732_project.drg_dim` t
    USING (
      -- this year's labels from the valid rows
      WITH src AS (
        SELECT DISTINCT drg_code, drg_label, year
          FROM `seis732-508701.seis732_project.union_charges_stg`
         WHERE year = r.year AND NOT (rej_missing_key OR rej_drg_pattern
              OR rej_missing_measure OR rej_nonpositive_payment)
      ),
      cur AS (SELECT drg_code, drg_label FROM `seis732-508701.seis732_project.drg_dim` WHERE last_year IS NULL)
      -- rows that close the current version of a changed code
      SELECT s.drg_code AS merge_key, s.drg_code, s.drg_label, s.year
        FROM src s JOIN cur c USING (drg_code)
       WHERE c.drg_label != s.drg_label
      UNION ALL
      -- rows that insert a new version (new code, or changed label)
      SELECT NULL, s.drg_code, s.drg_label, s.year
        FROM src s LEFT JOIN cur c USING (drg_code)
       WHERE c.drg_code IS NULL OR c.drg_label != s.drg_label
    ) u
       ON t.drg_code = u.merge_key AND t.last_year IS NULL
     WHEN MATCHED THEN UPDATE SET last_year = u.year - 1
     WHEN NOT MATCHED THEN INSERT (drg_id, drg_code, drg_label, first_year, last_year)
        VALUES (FARM_FINGERPRINT(CONCAT(u.drg_code, '|', CAST(u.year AS STRING))),
                u.drg_code, u.drg_label, u.year, NULL);
END FOR;

-- Lastly load the Charges Fact table
-- Create temp table from Charges Union table to ease MERGE
CREATE OR REPLACE TEMP TABLE incoming_charges AS
SELECT hosp.hospital_key, drg.drg_id, chrg.year, chrg.total_discharges, chrg.average_covered_charges
     , chrg.total_covered_charges, chrg.average_medicare_payments, chrg.total_medicare_payments
  FROM (SELECT provider_id_std, drg_code, `year`, total_discharges, average_covered_charges, average_medicare_payments
             , (total_discharges * average_covered_charges) AS total_covered_charges
             , (total_discharges * average_medicare_payments) AS total_medicare_payments
          FROM `seis732-508701.seis732_project.union_charges_stg`
          WHERE NOT (rej_missing_key OR rej_drg_pattern OR rej_missing_measure OR rej_nonpositive_payment)) chrg
  LEFT JOIN `seis732-508701.seis732_project.hospital_dim` hosp
    ON chrg.provider_id_std = hosp.provider_id_std
  LEFT JOIN `seis732-508701.seis732_project.drg_dim` drg
    ON     chrg.drg_code = drg.drg_code
       AND chrg.year >= drg.first_year AND (chrg.year <= drg.last_year OR drg.last_year IS NULL);

-- MERGE in incoming_charges into Charges Fact
MERGE `seis732-508701.seis732_project.inpatient_charges_fact` t
USING incoming_charges s
   ON t.hospital_key = s.hospital_key AND t.drg_id = s.drg_id AND t.`year` = s.`year`
 WHEN MATCHED THEN UPDATE SET
     total_discharges = s.total_discharges,
     average_covered_charges = s.average_covered_charges,
     total_covered_charges = s.total_covered_charges,
     average_medicare_payments = s.average_medicare_payments,
     total_medicare_payments = s.total_medicare_payments
 WHEN NOT MATCHED THEN INSERT ROW;
