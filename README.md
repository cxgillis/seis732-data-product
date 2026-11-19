# seis732-data-product
SEIS 732 Data Product

## Historical Medicare Inpatient Charge and Payment Benchmarks (2011-2015)

A data product that helps employer benefits analysts benchmark what hospitals billed against what Medicare paid
for the same types of inpatient stays, using the BigQuery public dataset `bigquery-public-data.cms_medicare`.
It is important to note that this describes historical Medicare data and does not establish current hospital prices
or what an employer plan would pay.

## P0 files
- [Feasibility write-up](docs/p0-feasibility.md)
- [Feasibility SQL](sql/00_feasibility.sql)
- [Feasibility results](evidence/p0-feasibility-results.md)

## P1 files
- [Plan write-up](docs/p1-plan.md)
- [Source Profile SQL](sql/01_source_profile.sql)

## P2 files
- [Build write-up](docs/p2-build.md)
- [Ingest SQL](sql/02_ingest.sql)
- [Curate SQL](sql/03_curate.sql)
- [Acceptance SQL](sql/04_acceptance.sql)
