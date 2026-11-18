-- ----------------------------------------------------------------------------------------------------
-- 1. Create Dataset and Snapshots
-- ----------------------------------------------------------------------------------------------------

-- 1a. Set up Dataset
CREATE SCHEMA IF NOT EXISTS seis732-508701.seis732_project OPTIONS(location='US');

-- 1b. Create Snapshot tables
CREATE OR REPLACE TABLE seis732-508701.seis732_project.inpatient_charges_2011_snapshot AS
SELECT *, CURRENT_TIMESTAMP() AS load_date
  FROM bigquery-public-data.cms_medicare.inpatient_charges_2011;

CREATE OR REPLACE TABLE seis732-508701.seis732_project.inpatient_charges_2012_snapshot AS
SELECT *, CURRENT_TIMESTAMP() AS load_date
  FROM bigquery-public-data.cms_medicare.inpatient_charges_2012;

CREATE OR REPLACE TABLE seis732-508701.seis732_project.inpatient_charges_2013_snapshot AS
SELECT *, CURRENT_TIMESTAMP() AS load_date
  FROM bigquery-public-data.cms_medicare.inpatient_charges_2013;

CREATE OR REPLACE TABLE seis732-508701.seis732_project.inpatient_charges_2014_snapshot AS
SELECT *, CURRENT_TIMESTAMP() AS load_date
  FROM bigquery-public-data.cms_medicare.inpatient_charges_2014;

CREATE OR REPLACE TABLE seis732-508701.seis732_project.inpatient_charges_2015_snapshot AS
SELECT *, CURRENT_TIMESTAMP() AS load_date
  FROM bigquery-public-data.cms_medicare.inpatient_charges_2015;

CREATE OR REPLACE TABLE seis732-508701.seis732_project.hospital_general_info_snapshot AS
SELECT *, CURRENT_TIMESTAMP() AS load_date
  FROM bigquery-public-data.cms_medicare.hospital_general_info;

-- ----------------------------------------------------------------------------------------------------
-- 2. Verification queries
-- ----------------------------------------------------------------------------------------------------

-- 2a. Row count per snapshot vs. source table, should all equal between source and raw
SELECT table_id, 'source' AS src, row_count, TIMESTAMP_MILLIS(last_modified_time) AS last_modified
  FROM `bigquery-public-data.cms_medicare.__TABLES__`
 WHERE table_id LIKE 'inpatient_charges_20%' OR table_id = 'hospital_general_info'
UNION ALL
SELECT table_id, 'raw' AS src, row_count, TIMESTAMP_MILLIS(last_modified_time) AS last_modified
  FROM `seis732-508701.seis732_project.__TABLES__`
 WHERE table_id LIKE 'inpatient_charges_20%' OR table_id LIKE 'hospital_general_info_%'
ORDER BY table_id, src;

-- 2b. Sum of the five charge snapshot tables, should = 878,944
SELECT SUM(row_cnt) AS total_rows
FROM (
  SELECT COUNT(*) AS row_cnt FROM `seis732-508701.seis732_project.inpatient_charges_2011_snapshot`
  UNION ALL
  SELECT COUNT(*) AS row_cnt FROM `seis732-508701.seis732_project.inpatient_charges_2012_snapshot`
  UNION ALL
  SELECT COUNT(*) AS row_cnt FROM `seis732-508701.seis732_project.inpatient_charges_2013_snapshot`
  UNION ALL
  SELECT COUNT(*) AS row_cnt FROM `seis732-508701.seis732_project.inpatient_charges_2014_snapshot`
  UNION ALL
  SELECT COUNT(*) AS row_cnt FROM `seis732-508701.seis732_project.inpatient_charges_2015_snapshot`
);

-- Snapshot vs. source content
-- Find mismatches on either side with EXCEPT DISTINCT, selecting all columns except load_date
-- Should be no rows, proving 0 differing rows both ways

-- 2c. inpatient_charges_*
WITH snapshots AS (
  SELECT * EXCEPT (load_date) FROM `seis732-508701.seis732_project.inpatient_charges_2011_snapshot` UNION ALL
  SELECT * EXCEPT (load_date) FROM `seis732-508701.seis732_project.inpatient_charges_2012_snapshot` UNION ALL
  SELECT * EXCEPT (load_date) FROM `seis732-508701.seis732_project.inpatient_charges_2013_snapshot` UNION ALL
  SELECT * EXCEPT (load_date) FROM `seis732-508701.seis732_project.inpatient_charges_2014_snapshot` UNION ALL
  SELECT * EXCEPT (load_date) FROM `seis732-508701.seis732_project.inpatient_charges_2015_snapshot`
),
source_data AS (
  SELECT * FROM `bigquery-public-data.cms_medicare.inpatient_charges_2011` UNION ALL
  SELECT * FROM `bigquery-public-data.cms_medicare.inpatient_charges_2012` UNION ALL
  SELECT * FROM `bigquery-public-data.cms_medicare.inpatient_charges_2013` UNION ALL
  SELECT * FROM `bigquery-public-data.cms_medicare.inpatient_charges_2014` UNION ALL
  SELECT * FROM `bigquery-public-data.cms_medicare.inpatient_charges_2015`
)
-- Symmetric difference query showing mismatch from either direction
(SELECT * FROM snapshots EXCEPT DISTINCT SELECT * FROM source_data)
UNION ALL
(SELECT * FROM source_data EXCEPT DISTINCT SELECT * FROM snapshots)
;

-- 2d. hospital_general_info
WITH snapshot AS (
  SELECT * EXCEPT (load_date) FROM `seis732-508701.seis732_project.hospital_general_info_snapshot`
),
source_data AS (
  SELECT * FROM `bigquery-public-data.cms_medicare.hospital_general_info`
)
(SELECT * FROM snapshot EXCEPT DISTINCT SELECT * FROM source_data)
UNION ALL
(SELECT * FROM source_data EXCEPT DISTINCT SELECT * FROM snapshot);

-- 2e. load_date populated and single-valued per table
-- 1 distinct count value
SELECT DISTINCT cnt
  FROM (SELECT COUNT(DISTINCT load_date) AS cnt FROM `seis732-508701.seis732_project.inpatient_charges_2011_snapshot` UNION ALL
        SELECT COUNT(DISTINCT load_date) FROM `seis732-508701.seis732_project.inpatient_charges_2012_snapshot` UNION ALL
        SELECT COUNT(DISTINCT load_date) FROM `seis732-508701.seis732_project.inpatient_charges_2013_snapshot` UNION ALL
        SELECT COUNT(DISTINCT load_date) FROM `seis732-508701.seis732_project.inpatient_charges_2014_snapshot` UNION ALL
        SELECT COUNT(DISTINCT load_date) FROM `seis732-508701.seis732_project.inpatient_charges_2015_snapshot` UNION ALL
        SELECT COUNT(DISTINCT load_date) AS cnt FROM `seis732-508701.seis732_project.hospital_general_info_snapshot`);

-- 2f. Confirm range of load_dates < 5 minutes apart
SELECT MIN(load_date) AS min_load, MAX(load_date) AS max_load
  FROM (SELECT DISTINCT load_date FROM `seis732-508701.seis732_project.inpatient_charges_2011_snapshot` UNION ALL
        SELECT DISTINCT load_date FROM `seis732-508701.seis732_project.inpatient_charges_2012_snapshot` UNION ALL
        SELECT DISTINCT load_date FROM `seis732-508701.seis732_project.inpatient_charges_2013_snapshot` UNION ALL
        SELECT DISTINCT load_date FROM `seis732-508701.seis732_project.inpatient_charges_2014_snapshot` UNION ALL
        SELECT DISTINCT load_date FROM `seis732-508701.seis732_project.inpatient_charges_2015_snapshot` UNION ALL
        SELECT DISTINCT load_date FROM `seis732-508701.seis732_project.hospital_general_info_snapshot`);
