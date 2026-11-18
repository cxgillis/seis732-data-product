--
-- Check 1: Grain and Relationships (Risk 1)
--

-- Total Row Count verification - Raw Count = Fact + rejected
SELECT COUNT(*) AS cnt
  FROM (SELECT 1 FROM `bigquery-public-data.cms_medicare.inpatient_charges_2011`
        UNION ALL
        SELECT 1 FROM `bigquery-public-data.cms_medicare.inpatient_charges_2012`
        UNION ALL
        SELECT 1 FROM `bigquery-public-data.cms_medicare.inpatient_charges_2013`
        UNION ALL
        SELECT 1 FROM `bigquery-public-data.cms_medicare.inpatient_charges_2014`
        UNION ALL
        SELECT 1 FROM `bigquery-public-data.cms_medicare.inpatient_charges_2015`) src;
-- 878,944
SELECT COUNT(*) FROM `seis732-508701.seis732_project.inpatient_charges_fact`;
-- 878,944
SELECT COUNT(*) FROM `seis732-508701.seis732_project.rejected_rows` WHERE source_table LIKE 'inpatient_charges_%';
-- 0
-- Total = 878,944 + 0 --> MATCHES

-- Rejected hospital rows (lookup rows failing the key rule). Expect 0
SELECT COUNT(*) AS cnt
  FROM `seis732-508701.seis732_project.rejected_rows`
 WHERE source_table = 'hospital_general_info_snapshot';
-- 0

-- Check the fact count and also count by the grain
SELECT COUNT(*) AS fact_rows
     , COUNT(DISTINCT CONCAT(h.provider_id_std,'|',d.drg_code,'|',CAST(f.year AS STRING))) AS distinct_grain
  FROM `seis732-508701.seis732_project.inpatient_charges_fact` f
  JOIN `seis732-508701.seis732_project.hospital_dim` h
    ON f.hospital_key = h.hospital_key
  JOIN `seis732-508701.seis732_project.drg_dim` d
    ON f.drg_id = d.drg_id;
-- fact_rows	distinct_grain
-- 878944	878944
-- --> MATCHES

-- Dim versions fit and don't overlap
-- Check fact rows with year that doesn't match its DRG dim range
SELECT COUNT(*) AS cnt
  FROM `seis732-508701.seis732_project.inpatient_charges_fact` f
  JOIN `seis732-508701.seis732_project.drg_dim` d
    ON f.drg_id = d.drg_id
 WHERE NOT (f.year >= d.first_year AND (f.year <= d.last_year OR d.last_year IS NULL));
-- 0

-- Check if any overlapping versions of DRG dim; I got AI to help with this
SELECT COUNT(*) AS cnt
  FROM `seis732-508701.seis732_project.drg_dim` d1
  JOIN `seis732-508701.seis732_project.drg_dim` d2
    ON d1.drg_code = d2.drg_code
   AND d1.drg_id < d2.drg_id
 WHERE d1.first_year <= COALESCE(d2.last_year, 9999)
   AND COALESCE(d1.last_year, 9999) >= d2.first_year;
-- 0

-- Confirm that Dim keys are unique
SELECT COUNT(*) AS cnt
  FROM (SELECT drg_id
          FROM `seis732-508701.seis732_project.drg_dim` d
        GROUP BY d.drg_id
        HAVING COUNT(*) > 1
        UNION ALL
        SELECT hospital_key
          FROM `seis732-508701.seis732_project.hospital_dim` d
        GROUP BY d.hospital_key
        HAVING COUNT(*) > 1) d;
-- 0

--
-- Check 2: Row Meaning w/ totals
--
SELECT COALESCE(src.`year`,fct.`year`) AS `year`
     , SUM(src.total_discharges) AS src_discharges
     , SUM(fct.total_discharges) AS fct_discharges
     , SUM(src.total_discharges - fct.total_discharges) AS discharges_diff
     , SUM(src.total_covered_charges) AS src_charges
     , SUM(fct.total_covered_charges) AS fct_charges
     , SUM(src.total_covered_charges - fct.total_covered_charges) AS charges_diff
     , SUM(src.total_medicare_payments) AS src_payments
     , SUM(fct.total_medicare_payments) AS fct_payments
     , SUM(src.total_medicare_payments - fct.total_medicare_payments) AS payments_diff
  FROM (SELECT 2011 AS `year`, SUM(total_discharges) AS total_discharges
             , SUM(total_discharges * average_covered_charges) AS total_covered_charges
             , SUM(total_discharges * average_medicare_payments) AS total_medicare_payments
          FROM `seis732-508701.seis732_project.inpatient_charges_2011_snapshot`
        UNION ALL
        SELECT 2012 AS `year`, SUM(total_discharges) AS total_discharges
             , SUM(total_discharges * average_covered_charges) AS total_covered_charges
             , SUM(total_discharges * average_medicare_payments) AS total_medicare_payments
          FROM `seis732-508701.seis732_project.inpatient_charges_2012_snapshot`
        UNION ALL
        SELECT 2013 AS `year`, SUM(total_discharges) AS total_discharges
             , SUM(total_discharges * average_covered_charges) AS total_covered_charges
             , SUM(total_discharges * average_medicare_payments) AS total_medicare_payments
          FROM `seis732-508701.seis732_project.inpatient_charges_2013_snapshot`
        UNION ALL
        SELECT 2014 AS `year`, SUM(total_discharges) AS total_discharges
             , SUM(total_discharges * average_covered_charges) AS total_covered_charges
             , SUM(total_discharges * average_medicare_payments) AS total_medicare_payments
          FROM `seis732-508701.seis732_project.inpatient_charges_2014_snapshot`
        UNION ALL
        SELECT 2015 AS `year`, SUM(total_discharges) AS total_discharges
             , SUM(total_discharges * average_covered_charges) AS total_covered_charges
             , SUM(total_discharges * average_medicare_payments) AS total_medicare_payments
          FROM `seis732-508701.seis732_project.inpatient_charges_2015_snapshot`) src
  FULL JOIN (SELECT `year`, SUM(total_discharges) AS total_discharges
                 , SUM(total_covered_charges) AS total_covered_charges
                 , SUM(total_medicare_payments) AS total_medicare_payments
              FROM `seis732-508701.seis732_project.inpatient_charges_fact`
             GROUP BY `year`) fct
    ON src.`year` = fct.`year`
GROUP BY COALESCE(src.`year`,fct.`year`);
-- year	src_discharges	fct_discharges	discharges_diff	src_charges	fct_charges	charges_diff	src_payments	fct_payments	payments_diff
-- 2011	6975318	6975318	0	245977915109.0	245977915109.0	0.0	57954455048.0	57954455048.0	0.0
-- 2012	6662965	6662965	0	249685896452.0	249685896452.0	0.0	57228792360.0	57228792360.0	0.0
-- 2013	6517112	6517112	0	261586281198.0	261586281198.0	0.0	56958463102.0	56958463102.0	0.0
-- 2014	7297885	7297885	0	356912458546.0	356912458546.0	0.0	76761605695.0	76761605695.0	0.0
-- 2015	7433268	7433268	0	379483324255.0	379483324255.0	0.0	78179949425.0	78179949425.0	0.0

--
-- Advanced Case
--

-- Check the number of inferred hospitals per year, along with impacted metrics per my P1 limitation
SELECT f.`year`
     , COUNT(DISTINCT f.hospital_key) AS hospitals
     , COUNT(DISTINCT IF(h.lookup_source = 'charges', f.hospital_key, NULL)) AS inferred_hospitals
     , COUNT(*) AS fact_rows
     , COUNTIF(h.lookup_source = 'charges') AS inferred_rows
     , SUM(f.total_discharges) AS discharges
     , SUM(IF(h.lookup_source = 'charges', f.total_discharges, 0)) AS inferred_discharges
  FROM `seis732-508701.seis732_project.inpatient_charges_fact` f
  JOIN `seis732-508701.seis732_project.hospital_dim` h
    ON f.hospital_key = h.hospital_key
GROUP BY f.`year` ORDER BY f.`year`;
-- year	hospitals	inferred_hospitals	fact_rows	inferred_rows	discharges	inferred_discharges
-- 2011	3337	370	163065	9153	6975318	283906
-- 2012	3317	337	157747	7508	6662965	232217
-- 2013	3289	299	153600	6227	6517112	188144
-- 2014	3276	258	202656	5600	7297885	158137
-- 2015	3231	212	201876	4755	7433268	136943
