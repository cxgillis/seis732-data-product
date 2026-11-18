# P2 Build: Working Ingestion, Curation & Acceptance Checks

Audience and question: see [p1-plan.md](p1-plan.md)  
Model: [model.png](model.png)  
Code: [02_ingest.sql](../sql/02_ingest.sql), [03_curate.sql](../sql/03_curate.sql), [04_acceptance.sql](../sql/04_acceptance.sql)

# 1. Establish the input and run ingestion

## Audience, question and P2 scope

- Audience:
  - I defined my audience as employer benefits analysts, whose need is to compare the differing hospital charges
    for the same type of inpatient services and how those charges compared to what Medicare paid.
- Primary question:
  - Within a given state, which hospitals have historically charged much more or less than others in that state for
    the same type of stay?
- Part of the planned product this P2 path builds:
  - This P2 path builds the input and prep layers for the Historical Medicare Inpatient Charge and Payment Benchmarks
    data product.
  - It copies the source CMS inpatient charges and hospital general info into Raw snapshot tables, builds Curated with
    a fact table at a year/hospital/type-of-stay (DRG) grain along with dimension tables for hospital and DRG.
  - It also infers hospital dimension records missing from the hospital_general_info source by backfilling from the 
    inpatient_charges_* tables, as otherwise in-state comparisons would be incomplete and inaccurate.
  - This provides the rows the Serving output will use to let the audience compare charges and payments across year,
    hospital, and DRG dimensions later in the Serving dataset.
  - Remaining P3 items: the Serving output with the ratio of sums, rerun and changed-input demos, and history verification.
- Changes to the P1 source or grain: There are no changes to either source or grain from P1.

## Source and subset

| Source object               | Full identifier                                                            | Subset used              |
|-----------------------------|----------------------------------------------------------------------------|--------------------------|
| Inpatient charges 2011–2015 | `bigquery-public-data.cms_medicare.inpatient_charges_2011` through `_2015` | All rows, all five years |
| Hospital lookup             | `bigquery-public-data.cms_medicare.hospital_general_info`                  | All rows                 |

## Build environment

- Google Cloud project: `seis732-508701`
- BigQuery dataset: `seis732_project`
- Processing location: US (the public dataset is also in US)

## Source-to-Raw step

- What is preserved:
  - I preserve all source columns, keep names and types unchanged, and add one TIMESTAMP column named `load_date` to
    identify when the snapshot tables were loaded.
- What is deliberately not done here:
  - I do not pad the hospital ID, split the DRG code into a separate field, or calculate any totals. These are all
    handled as part of loading Curated.
- Load choices:

| Decision                               | My choice             | Why it fits this source                                                                                                                                                                      |
|----------------------------------------|-----------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Copy into my project or query in place | Copy into my project  | This ensures my results don't change if the CMS source changes.                                                                                                                              |
| Columns and types                      | Exactly mirror source | Raw mirrors the source, and the adjustments that are required will happen in Curated.                                                                                                        |
| Replace or append on rerun             | Replace               | Raw is the baseline Curated is reconciled against, and appending would inflate those counts on every rerun. The source is a fixed set of annual data, so prior copies wouldn't add anything. |
| Added column(s)                        | load_date             | Enables observability of latest refresh time of Raw from source data.                                                                                                                        |

- Code: [02_ingest.sql](../sql/02_ingest.sql)
- Raw objects created:
  - `inpatient_charges_2011_snapshot`
  - `inpatient_charges_2012_snapshot`
  - `inpatient_charges_2013_snapshot`
  - `inpatient_charges_2014_snapshot`
  - `inpatient_charges_2015_snapshot`
  - `hospital_general_info_snapshot`

## Verification of the input

- Date run / last verified: `2026-11-10 UTC`
- Run timestamps: All six Raw snapshot load_date values fall between 2026-11-10 04:09:40 and 2026-11-10 04:10:27 UTC

| Check                                                      | 02_ingest.sql section | Reference (source)                                 | Observed (Raw)                                     | Conclusion |
|------------------------------------------------------------|-----------------------|----------------------------------------------------|----------------------------------------------------|------------|
| Rows per snapshot (6 tables)                               | 2a                    | 163,065, 157,747, 153,600, 202,656, 201,876, 5,336 | 163,065, 157,747, 153,600, 202,656, 201,876, 5,336 | Matches    |
| Total charge rows                                          | 2b                    | 878,944 (from P1 profile)                          | 878,944                                            | Matches    |
| Snapshot vs source, excluding `load_date`, both directions | 2c/d                  | 0                                                  | 0                                                  | Matches    |
| `load_date` populated, one distinct value per table        | 2e                    | One distinct `load_date` per table                 | 1                                                  | Matches    |
| Confirm range of load_dates < 5 minutes apart              | 2f                    | Min and Max `load_dates` < 5 minutes apart         | Min: 2026-11-10 04:09:40, Max: 2026-11-10 04:10:27 | Matches    | 

- What one Raw row represents:
  - One Raw row represents an identical copy of the original CMS table row from source, with `load_date` added.

## Reproducing the same input

- Source last-modified time and row count recorded as-of `2026-11-10`:

| Source table             | Last-modified time      | Row count |
|--------------------------|-------------------------|-----------|
| `inpatient_charges_2011` | 2024-10-11 16:01:33 UTC | 163,065   |
| `inpatient_charges_2012` | 2024-10-11 16:01:34 UTC | 157,747   |
| `inpatient_charges_2013` | 2024-10-11 16:01:30 UTC | 153,600   |
| `inpatient_charges_2014` | 2024-10-11 16:01:33 UTC | 202,656   |
| `inpatient_charges_2015` | 2024-10-11 16:01:42 UTC | 201,876   |
| `hospital_general_info`  | 2021-08-05 14:23:06 UTC | 5,336     |

- Remaining limit:
  - The public source can't be pinned to a version, there is only one set of tables in the public BigQuery copy of
    the CMS data.
  - The charge tables were rewritten on `2024-10-11`, so the source can change.
  - Here the Raw snapshots are the preserved copy. Someone rerunning should first compare their source last_modified
    and row_count values with the table above; any mismatch means they aren’t working from the same input.
  - There is the time travel functionality, but that only extends out 7 days so beyond that there is no recovery of the
    original source tables states.

# 2. Build Curated at the intended grain

## What one Curated row represents

The primary Curated grain is the `inpatient_charges_fact` row: one row per `year`, padded provider ID (`provider_id_std`),
and 3-digit DRG code (`drg_code`). The key (`year`, `provider_id_std`, `drg_code`) identifies one row, aligning with my
source profiling which did not find any repeated groups across all 878,944 charge rows. My [Check 1](../sql/04_acceptance.sql)
confirmed the same on the Curated fact table: 878,944 rows and 878,944 distinct combinations.
The `year` field is taken from the source table, and each fact row carries foreign keys to the dimension tables: 
`hospital_key` to `hospital_dim` and `drg_id` to the `drg_dim` version in effect for that row's `year`. The fact row also
carries the averages, total discharges, and totals computed as (average × discharges) so that ratios can later be computed
as a ratio of sums.

## Curated objects

| Object                   | What one row represents                                                                                                                                                | Key                                   | Built from                                                                                                                                                                                                                                                                            |
|--------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `union_charges_stg`      | One Raw charges row from any of the five years, with `year`, padded `provider_id_std`, `drg_code`, `drg_label`, and the rule flag `rej_*` fields added.                | `year`, `provider_id_std`, `drg_code` | Union of the five Raw `inpatient_charges_*_snapshot` tables.                                                                                                                                                                                                                          |
| `hospital_stg`           | One candidate hospital record: either a `hospital_general_info_snapshot` row (`lookup_source = 'lookup'`) or the best candidate for a hospital from the charge tables. | `provider_id_std`, `lookup_source`    | Raw lookup rows plus one row per hospital reference from `union_charges_stg` (candidate selected from latest year, then name, then row-hash tie-break).                                                                                                                               |
| `hospital_dim`           | One unique hospital (Type 1). Lookup rows are kept; a hospital billed in the charges but missing from the lookup gets an inferred row.                                 | `hospital_key` (surrogate)            | The surviving candidate per hospital from `hospital_stg`: the lookup row if present, otherwise the charge-derived row. The `hospital_key` is created from `FARM_FINGERPRINT(provider_id_std)`; `lookup_source` records which source was used.                                         |
| `drg_dim`                | One version of a DRG code (Type 2): a code's label over a year range.                                                                                                  | `drg_id` (surrogate)                  | Built one year at a time, 2011 to 2015, with a MERGE against each code's current version. A new version starts when the label differs from the current one (a reversion starts a new version), the old version ends the year before, and `last_year` is NULL for the current version. |
| `rejected_rows`          | One staging row (charge or hospital) that fails a validation rule, stored as a JSON string with its reject reasons, source table, and load date.                       | No key                                | Rows of `union_charges_stg` failing any of four charge rules, and rows of `hospital_stg` with a missing key. Expected to be empty.                                                                                                                                                    |
| `inpatient_charges_fact` | One year, hospital, and DRG combination.                                                                                                                               | `year`, `provider_id_std`, `drg_code` | Valid rows of `union_charges_stg` (staging minus rejected) joined to `hospital_dim` on `provider_id_std` and to `drg_dim` on `drg_code` where `first_year <= year AND (last_year IS NULL OR year <= last_year)`. The join provides `hospital_key` and `drg_id`.                       |

Code: [03_curate.sql](../sql/03_curate.sql)

## Rules

| Area                                     | Rule                                                                                                                                                                                                                                                                            | Why it supports the question / observed evidence                                                                                                                                                                                                                                                            |
|------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Types and fields                         | Keep the source types (`total_discharges` INT64, the three `average_*` fields FLOAT64, other text fields STRING). Add `year` (INT64, taken from the source table, since the charge tables have no year column) and derived totals (FLOAT64).                                    | All five charge tables share the same schema, and the source types are already numeric where needed (my profiling did not find unexpected NULLs). The year is needed so the five tables can be combined.                                                                                                    |
| Provider ID padding                      | `provider_id_std = LPAD(provider_id, 6, '0')`.                                                                                                                                                                                                                                  | The charge tables drop leading zeros while the lookup is always six characters. Adding this padding raised the join match rate from about 75% to 89–93% per year per my P1.                                                                                                                                 |
| DRG code and label                       | `drg_code = SUBSTR(drg_definition, 1, 3)` and `drg_label = TRIM(REGEXP_EXTRACT(drg_definition, r'^\d{3} - (.*)$'))`. The original `drg_definition` is kept in staging.                                                                                                          | The code is the reliable key and the label can change across years (My P1 found six codes whose label text changed, but never within the same year). Keeping the original string preserves the evidence for any row that fails the pattern rule in the rejected table.                                      |
| Missing or invalid values (reject rules) | Four independent flags, each non-NULL: missing key; DRG definition not matching `NNN - label`; missing discharges or charge fields; Medicare payments not greater than zero. A row failing any rule goes to `rejected_rows` and is excluded from the fact and the dimensions.   | These protect the ratio (by preventing a zero payment that would break it) as well as the key. All four rules ran and rejected 0 rows, in line with my P1 and P0 profiling. I kept the rules because they are cheap and guard against a future source change, but I did not add any other cleaning.         |
| Repeated rows                            | None removed. The five tables are combined with `UNION ALL`.                                                                                                                                                                                                                    | My P1 found 0 repeated (year, hospital, DRG) groups, and Check 1 confirms the fact table has 878,944 distinct combinations for 878,944 rows. A de-dupe step would have nothing to remove.                                                                                                                   |
| Hospital relationship, inferred members  | All lookup hospitals are loaded. A hospital billed in the charges but missing from the lookup gets a row built from the charges (name, city, state from its latest year, then by name, then by row hash); type and ownership are `Unknown`; `lookup_source` records the origin. | About 9% of hospital-years had no lookup match per P1. Without these rows the hospitals would drop out of state comparisons. The end result is 407 inferred hospitals, matching the P1 per-year counts exactly (Section 3).                                                                                 |
| DRG history (Type 2 versions)            | New version when a code's label differs from its current version; the previous version ends the year before; `last_year` is NULL for the current version. Years are loaded in order.                                                                                            | Needed so each year shows the label in effect and a code spanning label changes still groups by `drg_code` per P1. The end result is 598 versions for 592 codes, so each of the six changed codes changed once. I saw no overlapping versions and no fact row outside its version's year range (Section 3). |
| Surrogate keys                           | The `hospital_key` and `drg_id` are (deterministic) hashes (`FARM_FINGERPRINT`) of the business key.                                                                                                                                                                            | The same input gives the same keys on every run, which the P3 same-input rerun comparison will need. Both are unique with no duplicates (Section 3).                                                                                                                                                        |
| Additive totals                          | `total_covered_charges = total_discharges × average_covered_charges`; `total_medicare_payments = total_discharges × average_medicare_payments`. The source averages are kept.                                                                                                   | Averages can't be summed across hospitals of different sizes; the totals can, so the later ratio is SUM(charges) / SUM(payments). Because the source averages are rounded, a derived total can differ slightly from the true total. I did not yet measure this effect.                                      |

## Counts and reconciliation

| Step                                    | Count                                                     | Explanation                                                                                                                                                                                                                      |
|-----------------------------------------|-----------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Raw charge rows                         | 878,944 (163,065 / 157,747 / 153,600 / 202,656 / 201,876) | Matches the source row counts from Section 1, and `union_charges_stg` also has 878,944.                                                                                                                                          |
| Rejected                                | 0 (charge rows and hospital rows)                         | No row failed any of the four charge rules or the hospital key rule.                                                                                                                                                             |
| Curated fact rows                       | 878,944 (same per year as Raw)                            | Raw = fact + rejected (878,944 = 878,944 + 0). No rows were lost or added.                                                                                                                                                       |
| Effect of hospital join on row count    | 0                                                         | The `hospital_dim` has one row per `provider_id_std`, including the inferred members, so every fact row matches exactly one hospital. The inner-joined count equals the fact count (878,944).                                    |
| Effect of DRG version join on row count | 0                                                         | Version ranges for a code never overlap and cover every year a code appears, so each row matches exactly one version. 0 fact rows fall outside their version's range, and the 878,944 distinct combinations equal the row count. |
| `hospital_dim` rows (lookup / charges)  | 5,743 (5,336 / 407)                                       | All 5,336 lookup hospitals plus 407 billed hospitals missing from the lookup. Of the 3,461 distinct billed hospitals, 3,054 are in the lookup; 2,282 lookup hospitals were never billed.                                         |
| `drg_dim` rows (versions)               | 598                                                       | 592 distinct codes plus the 6 expected additional versions for the codes whose label changed.                                                                                                                                    |

## Field trace

| Step                                              | Value                                                                                                                                                                                            |
|---------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Source field                                      | `average_covered_charges` and `total_discharges` in `bigquery-public-data.cms_medicare.inpatient_charges_2011` through `_2015`                                                                   |
| Raw field                                         | The same names in `inpatient_charges_YYYY_snapshot`, which was copied unchanged.                                                                                                                 |
| Curated expression or rule                        | `total_discharges * average_covered_charges AS total_covered_charges` ([03_curate.sql](../sql/03_curate.sql), `incoming_charges`), loaded into `inpatient_charges_fact.total_covered_charges`    |
| Observed value or count                           | 2011: Raw sum of discharges × average charges = 245,977,915,109; fact `SUM(total_covered_charges)` = 245,977,915,109 (difference 0). Same result for 2012 to 2015 (Section 3, Check 2).          |
| Planned audience measure (planned, not yet built) | Serving view `inpatient_charges_totals_and_ratios`: `SUM(total_covered_charges) / SUM(total_medicare_payments)`, hospital against state, for a chosen DRG code and year(s). Will be built in P3. |

# 3. Run and interpret two acceptance checks

Code: [04_acceptance.sql](../sql/04_acceptance.sql)

| Risk and affected result | Check code | Expected result and why | Observed result | Interpretation or action |
|---|---|---|---|---|
| Grain / relationship: TODO | TODO | TODO | TODO | TODO |
| Row meaning: TODO | TODO | TODO | TODO | TODO |

## Changes to the P1 risks
- TODO

## Problems found and treatment
- TODO (result after any correction; any unresolved issue)

## Additional case (Advanced)
- Case: TODO (e.g., DRG 065 label change, or inferred hospital members)
- How it affects the Curated result: TODO
- Evidence and chosen treatment: TODO

# 4. Make the run reproducible and record the next step

## Run order

| Step | Code | Must already exist | Effect | Result to save before the next step |
|---|---|---|---|---|
| 1. Create dataset and Raw | [02_ingest.sql](../sql/02_ingest.sql) | Source access | TODO (replaces) | TODO |
| 2. Build Curated | [03_curate.sql](../sql/03_curate.sql) | Raw snapshots | TODO | TODO |
| 3. Run checks | [04_acceptance.sql](../sql/04_acceptance.sql) | Curated objects | TODO (read-only) | TODO |

- Run instructions checked against the build I performed: TODO (date)

## Main limitation of this P2 path
- TODO

## Next P3 step
- TODO (Serving output, rerun and changed-input demos, history verification)

## Model or explanation updates
- TODO

## AI and tool assistance
- TODO (what was used, how I checked it)
