-- Meaning of one row
SELECT COUNT(*) FROM `bigquery-public-data.cms_medicare.inpatient_charges_2011` GROUP BY provider_id, drg_definition HAVING COUNT(*) > 1;
SELECT COUNT(*) FROM `bigquery-public-data.cms_medicare.inpatient_charges_2012` GROUP BY provider_id, drg_definition HAVING COUNT(*) > 1;
SELECT COUNT(*) FROM `bigquery-public-data.cms_medicare.inpatient_charges_2013` GROUP BY provider_id, drg_definition HAVING COUNT(*) > 1;
SELECT COUNT(*) FROM `bigquery-public-data.cms_medicare.inpatient_charges_2014` GROUP BY provider_id, drg_definition HAVING COUNT(*) > 1;
SELECT COUNT(*) FROM `bigquery-public-data.cms_medicare.inpatient_charges_2015` GROUP BY provider_id, drg_definition HAVING COUNT(*) > 1;
SELECT COUNT(*) FROM `bigquery-public-data.cms_medicare.hospital_general_info` GROUP BY provider_id HAVING COUNT(*) > 1;

-- Relevant time coverage, row counts, and candidate identifier relevant to the idea.
-- I got help from AI to not have to repeat this for each table
SELECT
  _TABLE_SUFFIX AS data_year,
  COUNT(*) AS row_count,
  COUNT(DISTINCT provider_id) AS distinct_providers,
  COUNT(DISTINCT drg_definition) AS distinct_stay_types,
  COUNTIF(provider_id IS NULL) AS null_provider_ids,
  COUNTIF(total_discharges IS NULL) AS null_total_discharges,
  COUNTIF(average_covered_charges IS NULL) AS null_charges,
  COUNTIF(average_medicare_payments IS NULL) AS null_medicare_payments,
  COUNTIF(average_medicare_payments = 0) AS zero_medicare_payments
FROM `bigquery-public-data.cms_medicare.inpatient_charges_*`
GROUP BY data_year
ORDER BY data_year;

SELECT COUNT(*),
  COUNT(DISTINCT provider_id) AS distinct_providers,
  COUNTIF(provider_id IS NULL) AS null_provider_ids,
  COUNTIF(state IS NULL) AS null_state,
  COUNTIF(hospital_type IS NULL) AS null_hospital_type,
  COUNT(DISTINCT hospital_type) AS distinct_hospital_types,
  COUNTIF(hospital_ownership IS NULL) AS null_hospital_ownership,
  COUNT(DISTINCT hospital_ownership) AS distinct_hospital_ownership
  FROM `bigquery-public-data.cms_medicare.hospital_general_info`;

-- Record the authorized objects and inspect their definitions.
SELECT table_name, column_name, data_type, is_nullable
FROM `bigquery-public-data.cms_medicare.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name LIKE 'inpatient_charges_%' OR table_name = 'hospital_general_info'
ORDER BY table_name, ordinal_position;
