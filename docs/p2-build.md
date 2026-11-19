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

| Risk and affected result                                                                                                  | Check code                                                                                                                                     | Expected result and why                                                                                                                                                                                                                                                                                                                                                                                                       | Observed result                                                                                                                                                       | Interpretation or action                                                                                                                                                                                                                                                        |
|---------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Risk 1: Fact rows lost, duplicated or misjoined. This would distort every hospital and state total built on the fact.     | [04_acceptance.sql](../sql/04_acceptance.sql), Check 1: row accounting, grain and join count, DRG version fit, version overlap, key uniqueness | Source charge rows (same as Raw snapshot rows) = fact rows + rejected rows. Fact rows = distinct (`year`, `provider_id_std`, `drg_code`) after joining to both dimensions. 0 fact rows outside their DRG version's years, 0 overlapping versions, 0 duplicate `hospital_key` or `drg_id`. Each source row must map to exactly one fact row, one hospital, and one DRG version, so any other value means something went wrong. | 878,944 = 878,944 + 0. 878,944 fact rows and 878,944 distinct combinations. 0 rows outside their version, 0 overlaps, 0 duplicate keys, and 0 rejected hospital rows. | The grain stayed intact after the joins. No rows were lost or duplicated and no treatment was needed. The 0 rejects agree with my P1 profile.                                                                                                                                   |
| Risk 2 (revised from Serving): Totals that feed the ratio of sums do not mean what the audience measure assumes it would. | [04_acceptance.sql](../sql/04_acceptance.sql), Check 2: per-year reconciliation of Raw to fact                                                 | For each year, Raw sums of discharges, discharges × average charges, and discharges × average Medicare payments equal the fact sums, with difference 0. The fact holds the same products, so they should be equal. Float rounding is the only reason a tiny difference could appear.                                                                                                                                          | Differences were 0 for all five years (for example, 2011 charges 245,977,915,109 on both sides).                                                                      | The Curated totals match Raw, so the joins did not distort the measures the ratio uses. This shows that the rows carry the same totals, but not that the formula is necessarily right, and I have not checked the effect of the source's rounded averages. No treatment needed. |

## Changes to the P1 risks

- Risk 1 (fact rows lost or duplicated by the dimension joins):
  - I kept this as acceptance Check 1. However, I made it more specific than I had in my original P1 plan.
  - The join test became a comparison of the fact count with the distinct (`year`, `provider_id_std`, `drg_code`)
    count after joining both dimensions.
  - I added checks that every fact row falls inside its DRG version's year range, that DRG versions never overlap,
    and that `hospital_key` and `drg_id` are unique.
  - The P1 expectation of 0 rejects held.
- Risk 2 (hospital vs state comparison is wrong):
  - This is a Serving-level check and the Serving view is not built until P3, so I moved it there. 
  - For this section I replaced it with Check 2, a per-year reconciliation of Raw sums to the fact totals, which felt
    like a good idea since the ratio of sums depends on those totals being right.
  - It is a Curated-level precursor to the P1 check, and not a replacement for it.
- Risk 3 (missing hospital attributes due to backfilling):
  - I did not use it as one of the two checks and instead used it as the Advanced case.
  - The P1 check (inferred hospitals per year against the unmatched counts) matched exactly.
  - I added the inferred hospitals' share of fact rows and discharges, which I listed in P1 as an unmeasured limitation.

## Problems found and treatment
- My first run hit an error due to using FLOAT as a datatype, but BigQuery uses FLOAT64. I fixed the SQL.
- No check result was wrong, so no data treatment was needed.
- I have no unresolved issues in these checks, and the limitations are noted above in section 2 and the advanced case below.

## Additional case (Advanced)
- Case:
  - About 9% of hospital-years have no row in `hospital_general_info`. Rather than drop them, my `03_curate.sql`
    adds an inferred `hospital_dim` row for each (407 hospitals, `lookup_source = 'charges'`), with name, city, and state
    taken from the charge data and type and ownership set to `Unknown`.
- Check:
  - Found in [04_acceptance.sql](../sql/04_acceptance.sql) - Advanced Case
  - Shows the distinct fact hospitals with `lookup_source = 'charges'` per year and their share of fact rows and discharges.
- Expected:
  - For each year, the distinct fact hospitals with `lookup_source = 'charges'` equal the unmatched-hospital counts from my 
    P1 match query (370, 337, 299, 258, 212), since both count the hospitals billed that year that are absent from the lookup.
  - So any discrepancy would mean a hospital was mislabeled or lost in the dimension build.
- Result:

  | Year | Hospitals | Inferred hospitals (share) | Inferred fact rows (share) | Inferred discharges (share) |
  |------|-----------|----------------------------|----------------------------|-----------------------------|
  | 2011 | 3,337     | 370 (11.1%)                | 9,153 (5.6%)               | 283,906 (4.1%)              |
  | 2012 | 3,317     | 337 (10.2%)                | 7,508 (4.8%)               | 232,217 (3.5%)              |
  | 2013 | 3,289     | 299 (9.1%)                 | 6,227 (4.1%)               | 188,144 (2.9%)              |
  | 2014 | 3,276     | 258 (7.9%)                 | 5,600 (2.8%)               | 158,137 (2.2%)              |
  | 2015 | 3,231     | 212 (6.6%)                 | 4,755 (2.4%)               | 136,943 (1.8%)              |
  - The inferred hospital counts match the unmatched-hospital counts from my P1 match query exactly
    (370, 337, 299, 258, 212 = 1,476 total hospital-years), so the dimension covers every hospital that has charges.
- How it affects the Curated result:
  - Over the five years the inferred hospitals account for 33,243 of 878,944 fact rows (3.8%) and 999,347 of
    34,886,548 discharges (2.9%).
  - Without them, the inner join to the lookup would silently drop that amount from every state comparison.
  - The share is smaller than the 9% of hospital-years because these hospitals are smaller on average (in 2011, about
    770 discharges per inferred hospital against about 2,090 for all hospitals).
  - The share also falls each year, from 4.1% of discharges in 2011 to 1.8% in 2015.
  - This is consistent with my P1 hypothesis that older hospitals are more likely to be missing from the master list.
  - I didn't compare the charge-to-payment ratios of inferred and lookup hospitals, so I can’t say whether excluding them would change rankings.
- Chosen treatment:
  - I will keep the inferred rows.
  - The primary question (hospital against state) only needs name and state, which the charges provide.
  - The supporting question (type and ownership) can't use these hospitals, so views that filter on type or ownership
    will be labeled to say that some charge data is excluded.
  - The `lookup_source` column I added lets an analyst filter these out.

# 4. Make the run reproducible and record the next step

## Run order

Run in the listed order. Each step reads the objects created by the step before.

| Step                                                      | Code                                                            | Must already exist                                                                                     | Effect                                                                                                                                                                                                                                   | Result to save before the next step                                                              |
|-----------------------------------------------------------|-----------------------------------------------------------------|--------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------|
| 1. Create the dataset and Raw snapshots, then verify them | [02_ingest.sql](../sql/02_ingest.sql): sections 1 and 2 (2a–2f) | Read access to `bigquery-public-data.cms_medicare`; project `seis732-508701`; location US              | Creates dataset `seis732_project` if it doesn't exist. Creates or replaces the six `_snapshot` tables with new `load_date` values.                                                                                                       | Verification results (2a–2f): source `last_modified` and row counts, and the `load_date` window. |
| 2. Build staging and Curated                              | [03_curate.sql](../sql/03_curate.sql): run as one script        | The six Raw snapshot tables                                                                            | Replaces `union_charges_stg`, `hospital_stg`, `rejected_rows`, `hospital_dim`, `drg_dim`, and `inpatient_charges_fact`, then loads them in order. Everything overwrites, so a rerun gives the same result when using the same Raw input. | The row counts per object (staging, rejects, dimensions, fact).                                  |
| 3. Run the acceptance checks                              | [04_acceptance.sql](../sql/04_acceptance.sql)                   | The Curated objects from step 2, the Raw snapshots, and read access to the public source (for Check 1) | These are read-only and change no objects.                                                                                                                                                                                               | The results of each check (recorded in Section 3)                                                |

- The `03_curate.sql` code is designed to run as a single script because it uses temporary tables and a loop over the years (2011 to 2015, in order).
- Before rerunning, copy the Curated tables if the earlier result is needed for comparison.
- The `load_date` changes on every run and should be excluded from comparisons, and the surrogate keys are deterministic, so the same input produces the same keys.
- For the run instructions checked against the build I performed, I ran the steps in the order directed above:
    - First 02_ingest.sql on 2026-11-10
    - Then 03_curate.sql on 2026-11-17
    - Finally, 04_acceptance.sql on 2026-11-17
    - The table matches what I ran, and the counts in Sections 2 and 3 come from that final run.


## Main limitation of this P2 path
- Type and ownership are `Unknown` for the 407 inferred hospitals, so the supporting question can't use them.
- I measured their share of volume, but I didn't compare their charge-to-payment ratios with those of the lookup
  hospitals, so I'm not certain whether excluding them would change any rankings.
- The hospital attributes that exist also come from a lookup with an unknown as-of date, so they may not be accurate for
  the charges for any given year.

## Next P3 step
- I will build the Serving view `inpatient_charges_totals_and_ratios` (a regular view, not materialized).
- It will serve the hospital and state ratio of sums, never-billed hospitals removed, and cross-year views restricted
  to codes present in every selected year.
- I'll test it for one state, one DRG code, and one year against an independent recalculation from Raw.
- Then I'll complete the same-input rerun and changed-input demonstrations and the history verification for DRG 065.

## Model or explanation updates
- For DRG, I decided to change how `drg_dim` stores the label text without its code prefix, in a column named `drg_label`.
  - My original `model.png` shows `drg_definition`. The source `drg_definition` string is kept in staging.
  - The `drg_id` is a deterministic FARM_FINGERPRINT hash of `drg_code` and `first_year`.
- For Hospital, the `hospital_key` stays as P1 originally planned.
  - It is a deterministic FARM_FINGERPRINT hash of `provider_id_std`.
- The grain, the dimensions, and the key decisions are otherwise unchanged from P1. I didn't regenerate `model.png`.

## AI and tool assistance
- I used AI throughout P2 and treated its output as leads to check, not evidence. I remain responsible for the code,
  the decisions, and the claims I have made.
- What I used it for:
  - Outlining the P2 tasks (and drafting this AI usage note).
  - Reviewing my SQL code before I ran it.
  - Suggesting `FARM_FINGERPRINT` for deterministic surrogate keys.
  - Helping with the MERGE pattern for the Type 2 DRG dimension and the version overlap check.
  - Reviewing my wording.
- What was my own work:
  - Running every query.
  - Choosing the checks and the Advanced case.
  - Deciding to load the DRG versions year by year.
  - Verifying the numbers.
- How I verified:
  - I ran all SQL in BigQuery.
  - I compared counts with my P1 profile and with the source, recalculated the totals independently from Raw, matched
    the inferred hospital counts to my P1 numbers, and confirmed the billed and never-billed hospital split with its own query.
- Where AI output needed correcting or I did not follow it:
  - Its review caught errors in my drafts before I ran them: the fact `MERGE` pointed at the wrong table, the hospital
    selection took the lowest-ranked candidate, the lookup columns were misnamed, the fact build did not exclude rejected
    rows, and `load_date` was typed `DATETIME` against a `TIMESTAMP` source.
  - I fixed each. A separate `FLOAT` type error (GoogleSQL requires `FLOAT64`) failed my first run.
  - It suggested a one-shot load of the DRG dimension. I chose year-by-year merges so a new year can be added later.
  - It first recommended dropping the hospital surrogate key, then recommended keeping it. I kept it, to match my P1
    model.
  - It suggested a numeric tolerance for the totals comparison. I used exact equality, and the observed differences were 0.
  - It suggested a shorter positive key range for the hashed keys. I kept the full hash since it was much simpler to
    implement, and the cosmetic change wasn’t needed.
