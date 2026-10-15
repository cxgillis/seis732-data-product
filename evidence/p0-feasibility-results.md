## Meaning of one row
```sql
SELECT COUNT(*) FROM `bigquery-public-data.cms_medicare.inpatient_charges_2011` GROUP BY provider_id, drg_definition HAVING COUNT(*) > 1;
SELECT COUNT(*) FROM `bigquery-public-data.cms_medicare.inpatient_charges_2012` GROUP BY provider_id, drg_definition HAVING COUNT(*) > 1;
SELECT COUNT(*) FROM `bigquery-public-data.cms_medicare.inpatient_charges_2013` GROUP BY provider_id, drg_definition HAVING COUNT(*) > 1;
SELECT COUNT(*) FROM `bigquery-public-data.cms_medicare.inpatient_charges_2014` GROUP BY provider_id, drg_definition HAVING COUNT(*) > 1;
SELECT COUNT(*) FROM `bigquery-public-data.cms_medicare.inpatient_charges_2015` GROUP BY provider_id, drg_definition HAVING COUNT(*) > 1;
SELECT COUNT(*) FROM `bigquery-public-data.cms_medicare.hospital_general_info` GROUP BY provider_id HAVING COUNT(*) > 1;
```

### Results:
```
<No data from any of the queries>
```

### Interpretation:

Indicates that no rows were found with duplicates, so these are good candidates for the meaning of one row as:
 - inpatient_charges_* -> one hospital and one type of stay
 - hospital_general_info -> one hospital

## Relevant time coverage, row counts, and candidate identifier relevant to the idea.
```sql
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
```

### Results:
```
data_year	row_count	distinct_providers	distinct_stay_types	null_provider_ids	null_total_discharges	null_charges	null_medicare_payments	zero_medicare_payments
2011	163065	3337	100	0	0	0	0	0
2012	157747	3317	100	0	0	0	0	0
2013	153600	3289	100	0	0	0	0	0
2014	202656	3276	564	0	0	0	0	0
2015	201876	3231	563	0	0	0	0	0
```

### Interpretation:

Zero counts for null and zero values look good.

## Now check the hospital_general_info table:

```sql
SELECT COUNT(*),
  COUNT(DISTINCT provider_id) AS distinct_providers,
  COUNTIF(provider_id IS NULL) AS null_provider_ids,
  COUNTIF(state IS NULL) AS null_state,
  COUNTIF(hospital_type IS NULL) AS null_hospital_type,
  COUNT(DISTINCT hospital_type) AS distinct_hospital_types,
  COUNTIF(hospital_ownership IS NULL) AS null_hospital_ownership,
  COUNT(DISTINCT hospital_ownership) AS distinct_hospital_ownership
  FROM `bigquery-public-data.cms_medicare.hospital_general_info`;
```

### Results:

```
f0_	distinct_providers	null_provider_ids	null_state	null_hospital_type	distinct_hospital_types	null_hospital_ownership	distinct_hospital_ownership
5336	5336	0	0	0	5	0	11
```

### Interpretation:

Zero counts for nulls look good.

## Finally record the authorized objects and inspect their definitions.
```sql
SELECT table_name, column_name, data_type, is_nullable
FROM `bigquery-public-data.cms_medicare.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name LIKE 'inpatient_charges_%' OR table_name = 'hospital_general_info'
ORDER BY table_name, ordinal_position;
```

### Results:

```sql
table_name	column_name	data_type	is_nullable
hospital_general_info	provider_id	STRING	YES
hospital_general_info	hospital_name	STRING	YES
hospital_general_info	address	STRING	YES
hospital_general_info	city	STRING	YES
hospital_general_info	state	STRING	YES
hospital_general_info	zip_code	STRING	YES
hospital_general_info	county_name	STRING	YES
hospital_general_info	phone_number	STRING	YES
hospital_general_info	hospital_type	STRING	YES
hospital_general_info	hospital_ownership	STRING	YES
hospital_general_info	emergency_services	BOOL	YES
hospital_general_info	meets_criteria_for_promoting_interoperability_of_ehrs	BOOL	YES
hospital_general_info	hospital_overall_rating	STRING	YES
hospital_general_info	hospital_overall_rating_footnote	STRING	YES
hospital_general_info	mortality_group_measure_count	STRING	YES
hospital_general_info	facility_mortaility_measures_count	STRING	YES
hospital_general_info	mortality_measures_better_count	STRING	YES
hospital_general_info	mortality_measures_no_different_count	STRING	YES
hospital_general_info	mortality_measures_worse_count	STRING	YES
hospital_general_info	mortaility_group_footnote	STRING	YES
hospital_general_info	safety_measures_count	STRING	YES
hospital_general_info	facility_care_safety_measures_count	STRING	YES
hospital_general_info	safety_measures_better_count	STRING	YES
hospital_general_info	safety_measures_no_different_count	STRING	YES
hospital_general_info	safety_measures_worse_count	STRING	YES
hospital_general_info	safety_group_footnote	STRING	YES
hospital_general_info	readmission_measures_count	STRING	YES
hospital_general_info	facility_readmission_measures_count	STRING	YES
hospital_general_info	readmission_measures_better_count	STRING	YES
hospital_general_info	readmission_measures_no_different_count	STRING	YES
hospital_general_info	readmission_measures_worse_count	STRING	YES
hospital_general_info	readmission_measures_footnote	STRING	YES
hospital_general_info	patient_experience_measures_count	STRING	YES
hospital_general_info	facility_patient_experience_measures_count	STRING	YES
hospital_general_info	patient_experience_measures_footnote	STRING	YES
hospital_general_info	timely_and_effective_care_measures_count	STRING	YES
hospital_general_info	facility_timely_and_effective_care_measures_count	STRING	YES
hospital_general_info	timely_and_effective_care_measures_footnote	STRING	YES
inpatient_charges_2011	provider_id	STRING	NO
inpatient_charges_2011	provider_name	STRING	YES
inpatient_charges_2011	provider_street_address	STRING	YES
inpatient_charges_2011	provider_city	STRING	YES
inpatient_charges_2011	provider_state	STRING	YES
inpatient_charges_2011	provider_zipcode	STRING	YES
inpatient_charges_2011	drg_definition	STRING	NO
inpatient_charges_2011	hospital_referral_region_description	STRING	YES
inpatient_charges_2011	total_discharges	INT64	YES
inpatient_charges_2011	average_covered_charges	FLOAT64	YES
inpatient_charges_2011	average_total_payments	FLOAT64	YES
inpatient_charges_2011	average_medicare_payments	FLOAT64	YES
inpatient_charges_2012	provider_id	STRING	NO
inpatient_charges_2012	provider_name	STRING	YES
inpatient_charges_2012	provider_street_address	STRING	YES
inpatient_charges_2012	provider_city	STRING	YES
inpatient_charges_2012	provider_state	STRING	YES
inpatient_charges_2012	provider_zipcode	STRING	YES
inpatient_charges_2012	drg_definition	STRING	NO
inpatient_charges_2012	hospital_referral_region_description	STRING	YES
inpatient_charges_2012	total_discharges	INT64	YES
inpatient_charges_2012	average_covered_charges	FLOAT64	YES
inpatient_charges_2012	average_total_payments	FLOAT64	YES
inpatient_charges_2012	average_medicare_payments	FLOAT64	YES
inpatient_charges_2013	provider_id	STRING	NO
inpatient_charges_2013	provider_name	STRING	YES
inpatient_charges_2013	provider_street_address	STRING	YES
inpatient_charges_2013	provider_city	STRING	YES
inpatient_charges_2013	provider_state	STRING	YES
inpatient_charges_2013	provider_zipcode	STRING	YES
inpatient_charges_2013	drg_definition	STRING	NO
inpatient_charges_2013	hospital_referral_region_description	STRING	YES
inpatient_charges_2013	total_discharges	INT64	YES
inpatient_charges_2013	average_covered_charges	FLOAT64	YES
inpatient_charges_2013	average_total_payments	FLOAT64	YES
inpatient_charges_2013	average_medicare_payments	FLOAT64	YES
inpatient_charges_2014	provider_id	STRING	NO
inpatient_charges_2014	provider_name	STRING	YES
inpatient_charges_2014	provider_street_address	STRING	YES
inpatient_charges_2014	provider_city	STRING	YES
inpatient_charges_2014	provider_state	STRING	YES
inpatient_charges_2014	provider_zipcode	STRING	YES
inpatient_charges_2014	drg_definition	STRING	NO
inpatient_charges_2014	hospital_referral_region_description	STRING	YES
inpatient_charges_2014	total_discharges	INT64	YES
inpatient_charges_2014	average_covered_charges	FLOAT64	YES
inpatient_charges_2014	average_total_payments	FLOAT64	YES
inpatient_charges_2014	average_medicare_payments	FLOAT64	YES
inpatient_charges_2015	provider_id	STRING	NO
inpatient_charges_2015	provider_name	STRING	YES
inpatient_charges_2015	provider_street_address	STRING	YES
inpatient_charges_2015	provider_city	STRING	YES
inpatient_charges_2015	provider_state	STRING	YES
inpatient_charges_2015	provider_zipcode	STRING	YES
inpatient_charges_2015	drg_definition	STRING	NO
inpatient_charges_2015	hospital_referral_region_description	STRING	YES
inpatient_charges_2015	total_discharges	INT64	YES
inpatient_charges_2015	average_covered_charges	FLOAT64	YES
inpatient_charges_2015	average_total_payments	FLOAT64	YES
inpatient_charges_2015	average_medicare_payments	FLOAT64	YES
```

### Interpretation:

Columns and types seem appropriate at a glance for what I am hoping to achieve.
