-- ------------------------------------------------------------------------------------------
--   Grain Checks
-- ------------------------------------------------------------------------------------------

-- Create the charges table for all years
CREATE TEMP TABLE all_charges AS
SELECT 2011 AS year, provider_id, drg_definition, provider_state
  FROM `bigquery-public-data.cms_medicare.inpatient_charges_2011`
UNION ALL
SELECT 2012 AS year, provider_id, drg_definition, provider_state
  FROM `bigquery-public-data.cms_medicare.inpatient_charges_2012`
UNION ALL
SELECT 2013 AS year, provider_id, drg_definition, provider_state
  FROM `bigquery-public-data.cms_medicare.inpatient_charges_2013`
UNION ALL
  SELECT 2014 AS year, provider_id, drg_definition, provider_state
  FROM `bigquery-public-data.cms_medicare.inpatient_charges_2014`
UNION ALL
SELECT 2015 AS year, provider_id, drg_definition, provider_state
  FROM `bigquery-public-data.cms_medicare.inpatient_charges_2015`;

-- The grain check incorporates a finding for handling provider IDs and DRG codes from later queries
SELECT SUM(rows_per_key) AS source_rows
     , SUM(IF(provider_id IS NULL OR drg_code IS NULL OR year IS NULL,
              rows_per_key, 0)) AS rows_with_null_key
     , COUNTIF(rows_per_key > 1) AS repeated_key_groups
  FROM (SELECT year, LPAD(provider_id, 6, '0') AS provider_id
             , SUBSTR(drg_definition,1,3) AS drg_code, COUNT(*) AS rows_per_key
          FROM all_charges GROUP BY year, provider_id, drg_code
       ) charge_grain;
-- source_rows	rows_with_null_key	repeated_key_groups
-- 878944	0	0

-- This check verifies that my provider ID and DRG code handling won't create issues
SELECT COUNT(DISTINCT provider_id) AS raw_ids
     , COUNT(DISTINCT LPAD(provider_id, 6, '0')) AS padded_ids
     , COUNTIF(NOT REGEXP_CONTAINS(drg_definition, r'^\d{3} - ')) AS odd_labels
  FROM all_charges;
-- raw_ids	padded_ids	odd_labels
-- 3461	3461	0

-- ------------------------------------------------------------------------------------------
--   Test the hospital join i.e. are there unmatched providers
-- ------------------------------------------------------------------------------------------

-- Check the match rate
SELECT c.year
     , COUNT(*) AS charge_hospitals
     , COUNTIF(h.provider_id IS NOT NULL) AS matched
     , ROUND(SAFE_DIVIDE(COUNTIF(h.provider_id IS NOT NULL), COUNT(*)),2) AS match_rate
  FROM (SELECT DISTINCT year, provider_id FROM all_charges) c
  LEFT JOIN `bigquery-public-data.cms_medicare.hospital_general_info` h
    ON c.provider_id = h.provider_id
GROUP BY c.year ORDER BY c.year;
-- year	charge_hospitals	matched	match_rate
-- 2011	3337	2436	0.73
-- 2012	3317	2445	0.74
-- 2013	3289	2453	0.75
-- 2014	3276	2479	0.76
-- 2015	3231	2477	0.77

-- This is alarming, nearly 25% missing matches on join to hospital
-- Check a random example to see what might be going on
SELECT DISTINCT c.provider_id
  FROM (SELECT DISTINCT year, provider_id FROM all_charges) c
  LEFT JOIN `bigquery-public-data.cms_medicare.hospital_general_info` h
    ON c.provider_id = h.provider_id
 WHERE h.provider_id IS NULL LIMIT 1
;
-- Found an example ID

-- Let's inspect what's going on in the charges table for this one
SELECT DISTINCT provider_id, provider_name, provider_zipcode
  FROM `bigquery-public-data.cms_medicare.inpatient_charges_2011`
 WHERE provider_id = '80001';
-- Not copying source rows, but I see the name and ZIP

-- Now let's see if we see any hospitals in that ZIP in case it's there but being weird
SELECT provider_id, hospital_name, zip_code
  FROM `bigquery-public-data.cms_medicare.hospital_general_info`
 WHERE zip_code = '19718';
-- provider_id	hospital_name	zip_code
-- Not copying source rows, but I found the hospital with a 0-padded ID

-- Bingo, looks like provider_id might be padded in hospital_general_info
-- Let's check them all
SELECT LENGTH(provider_id) AS len, COUNT(*) AS cnt
 FROM `bigquery-public-data.cms_medicare.hospital_general_info`
GROUP BY LENGTH(provider_id);
-- len	cnt
-- 6	5336

-- I think this explains it, let's update the join and test
SELECT c.year
     , COUNT(*) AS charge_hospitals
     , COUNTIF(h.provider_id IS NOT NULL) AS matched
     , ROUND(SAFE_DIVIDE(COUNTIF(h.provider_id IS NOT NULL), COUNT(*)),2) AS match_rate
  FROM (SELECT DISTINCT year, LPAD(provider_id, 6, '0') AS provider_id FROM all_charges) c
  LEFT JOIN `bigquery-public-data.cms_medicare.hospital_general_info` h
    ON c.provider_id = h.provider_id
GROUP BY c.year ORDER BY c.year;
-- year	charge_hospitals	matched	match_rate
-- 2011	3337	2967	0.89
-- 2012	3317	2980	0.9
-- 2013	3289	2990	0.91
-- 2014	3276	3018	0.92
-- 2015	3231	3019	0.93
-- Total missing is 370, 337, 299, 258, 212

-- That's better but still not perfect. Let's check another missing example
SELECT DISTINCT provider_id, provider_name, provider_zipcode
  FROM `bigquery-public-data.cms_medicare.inpatient_charges_2011`
 WHERE provider_id = '170195';
-- Not copying source rows, but captured the details to compare.

-- Try again looking for any similar matches for the example in the last query
SELECT provider_id, hospital_name, zip_code
  FROM `bigquery-public-data.cms_medicare.hospital_general_info`
 WHERE zip_code = '66211' OR UPPER(hospital_name) LIKE '%HEARTLAND%';
-- Not copying source rows here, but I did not see any

-- I repeated this for a few other random examples but see they are not found

-- Check for unmatched by state to see if any surprising results
SELECT c.provider_state,
       COUNT(*) AS hospital_year_combos,
       COUNTIF(h.provider_id IS NULL) AS unmatched,
       ROUND(SAFE_DIVIDE(COUNTIF(h.provider_id IS NULL), COUNT(*)),2) AS unmatched_rate
  FROM (SELECT DISTINCT year, LPAD(provider_id, 6, '0') AS provider_id, provider_state
          FROM all_charges) c
  LEFT JOIN `bigquery-public-data.cms_medicare.hospital_general_info` h
    ON c.provider_id = h.provider_id
GROUP BY c.provider_state ORDER BY unmatched_rate DESC;
-- Top 3 unmatched states
-- provider_state	hospital_years	unmatched	unmatched_rate
-- WV	152	26	0.17
-- WY	54	9	0.17
-- TX	1496	242	0.16
-- I also see 6 states have 0 unmatched hospitals.

-- Conclusion: I don't have definitive matches for all hospitals, but I can source some of the info from the charge tables.
-- A hypothesis is that these providers got removed from the master list after the last year of charges, or were never added.
-- I do see the match rate increase year-over-year which is consistent with that. Checking how this pattern
-- applies by state and I see that unmatched rates range from 0-17% by states against about 9% overall, with TX having
-- the largest unmatched count and third-highest rate at 16%. I am not able to determine the root cause for this variation.


-- ------------------------------------------------------------------------------------------
--   Test DRG coverage across the years
-- ------------------------------------------------------------------------------------------

-- Check the DRG count by year
SELECT years_present, COUNT(*) AS drg_count
FROM (
  SELECT drg_definition, COUNT(*) AS years_present
  FROM (SELECT DISTINCT year, drg_definition FROM all_charges) c
  GROUP BY drg_definition
)
GROUP BY years_present ORDER BY years_present;
-- years_present	drg_count
-- 1	63
-- 2	430
-- 3	7
-- 4	7
-- 5	91

-- DRG looks like "069 - TRANSIENT ISCHEMIA", what if we just look at the codes?
SELECT years_present, COUNT(*) AS drg_count
FROM (
  SELECT drg_code, COUNT(*) AS years_present
  FROM (SELECT DISTINCT year, SUBSTR(drg_definition,1,3) as drg_code FROM all_charges) c
  GROUP BY drg_code
)
GROUP BY years_present ORDER BY years_present;
-- years_present	drg_count
-- 1	55
-- 2	432
-- 3	6
-- 4	5
-- 5	94

-- Doesn't seem to change much, so that's not it

-- At this point I start searching the Medicare CMS resources and found that from 2011-2013 only the top 100 DRGs for
-- that year were reported:
-- https://www.cms.gov/research-statistics-data-and-systems/statistics-trends-and-reports/medicare-provider-charge-data/downloads/inpatient_methodology.pdf
-- I also found that codes are added, removed, split, and merged year-over-year:
-- https://www.cms.gov/priorities/innovation/files/x/bpciadvanced-episodecreationspecs-yr1-2-app.pdf
-- https://www.federalregister.gov/d/2014-18545/p-1236
-- So I think this adds evidence to support an expectation of DRGs fluctuating from year-to-year.

-- Another thing to check is if the same code changes its full description within or across years:
SELECT year, drg_code, COUNT(*) AS cnt
  FROM (SELECT DISTINCT year, SUBSTR(drg_definition,1,3) as drg_code, drg_definition
          FROM all_charges) c
 GROUP BY year, drg_code HAVING COUNT(*) > 1;
-- No Data
SELECT drg_code, COUNT(*) AS cnt
  FROM (SELECT DISTINCT SUBSTR(drg_definition,1,3) as drg_code, drg_definition
          FROM all_charges) c
GROUP BY drg_code HAVING COUNT(*) > 1;
-- drg_code	cnt
-- 065	2
-- 870	2
-- 872	2
-- 003	2
-- 457	2
-- 927	2
SELECT DISTINCT year, SUBSTR(drg_definition,1,3) as drg_code, drg_definition
  FROM all_charges WHERE SUBSTR(drg_definition,1,3) = '065';
-- year	drg_code	drg_definition
-- 2011	065	065 - INTRACRANIAL HEMORRHAGE OR CEREBRAL INFARCTION W CC
-- 2012	065	065 - INTRACRANIAL HEMORRHAGE OR CEREBRAL INFARCTION W CC
-- 2013	065	065 - INTRACRANIAL HEMORRHAGE OR CEREBRAL INFARCTION W CC OR TPA IN 24 HRS
-- 2014	065	065 - INTRACRANIAL HEMORRHAGE OR CEREBRAL INFARCTION W CC OR TPA IN 24 HRS
-- 2015	065	065 - INTRACRANIAL HEMORRHAGE OR CEREBRAL INFARCTION W CC OR TPA IN 24 HRS

-- From this it looks like the full DRG text can change for the same DRG code across but not within years
-- So I should stick to using a DRG code only column to allow cross-year comparisons



-- ------------------------------------------------------------------------------------------
