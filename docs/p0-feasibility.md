# 1. Working title

Historical Medicare Inpatient Charge and Payment Benchmarks (2011-2015)

# 2. Audience and need

The audience for this would be employer benefits analysts who compare what different hospitals have historically
charged for inpatient services, to assist with prioritizing the hospitals to focus on when negotiating in-network
coverage with their health plan.

The need would be to compare the differing hospital charges for the same type of inpatient services and how those
charges compared to what Medicare paid. A data product for this would allow analysts to more easily see which
hospitals charged more or less relative to other hospitals for the same services.

This product is historical benchmarking that covers 2011 to 2015 and reports Medicare-related averages per hospital and
stay type. It does not establish current prices or what an employer plan would pay, so analysts would use it to decide
where to look more closely, not to set or evaluate negotiated rates.

# 3. Proposed analytical product and questions

My proposed analytical product would be a dashboard that provides:
- filters on type of inpatient stay (labeled with DRG in the dataset), state, hospital type, and ownership
- a view benchmarking historical hospital charges against Medicare payments
- a summary table of top and bottom hospitals in the charge to payment ratio (hospital charge / Medicare payment)

Questions:

1. For each type of inpatient stay, how large is the gap between what hospitals historically charged and what Medicare paid?
2. For each type of inpatient stay, how much did average historical charges per hospital differ across states?
3. Within a given state, which hospitals have historically charged much more or less than others in that state for the same type of stay?
4. Do hospitals with larger charge to payment gaps share traits, like hospital type or ownership?

# 4. Source identification and access

- **Source provider:** Centers for Medicare & Medicaid Services
- **Source name:** Medicare Utilization
- **Source URL:** https://console.cloud.google.com/marketplace/product/hhs/medicare
- **BigQuery project and dataset IDs:** `bigquery-public-data.cms_medicare`
- **Source tables (all in `US` location):**
  - `inpatient_charges_2011`
  - `inpatient_charges_2012`
  - `inpatient_charges_2013`
  - `inpatient_charges_2014`
  - `inpatient_charges_2015`
  - `hospital_general_info`
- **Access:** I was able to confirm that I can query these tables from my course environment.
- **Use constraints:** The source catalog page indicates that the dataset is publicly available for anyone to use.

# 5. Quick source profile

- **Row meaning:**
  - `inpatient_charges_*`: One row is one hospital (`provider_id`) and one type of stay (`drg_definition`)
  - `hospital_general_info`: One row is a single hospital (`provider_id`)
- **Row counts:**
  - `inpatient_charges_2011`: 163,065
  - `inpatient_charges_2012`: 157,747
  - `inpatient_charges_2013`: 153,600
  - `inpatient_charges_2014`: 202,656
  - `inpatient_charges_2015`: 201,876
  - `hospital_general_info`:    5,336
- **Time coverage:**
  - 2011-2015 for charges
  - The as-of date for hospital details is unknown, but the table was created in 2017 and last updated in 2021.
  - For charges the years only come from the table name.
- **Keys:**
  - `inpatient_charges_*`: `provider_id`, `drg_definition` -> The combination of hospital ID and the type of stay
     ID is unique within each yearly table.
  - `hospital_general_info`: `provider_id` -> appears to be the unique hospital ID with no values missing or duplicated.
- **Fields supporting the questions:**
  - `provider_id`
  - `drg_definition`
  - `average_covered_charges`
  - `average_medicare_payments`: No 0 values found in this field so my ratios should be safe.
  - `total_discharges`
  - `state`: This exists in both tables but will pull from the `hospital_general_info` table to ensure consistency.
  - `hospital_type`
  - `hospital_ownership`
- **Nulls, types, duplicates:** I did not find any unexpected NULL values in the supporting fields, and the average charges
  and payment field types are suitable float values. I do not see any duplicates on the keys.
- **Refresh behavior:**
  - The `inpatient_charges_*` tables were created in 2017 and last updated in 2024.
  - The `hospital_general_info` table was created in 2017 and last updated in 2021.
- **Interpretation concerns:**
  - Charges are what the hospital billed, but there are two payment fields with different scopes.
  - All these values are hospital averages which might hide variation within a hospital.
  - Hospital info was last updated in 2021 so it's not completely clear the point in time the details reflect.
  - The distinct DRG (stay types) has a significant count jump from 2013 to 2014, it's unclear what that signifies.

# 6. Need-to-source fit

| Proposed question                                                                                                      | Needed fields or concepts                                                                                                                                         | Candidate source object(s)                                               | Why the source appears sufficient                                                                                                                                                                                                                                | Gap or assumption to test in P1                                                                                                                                                                                                                        |
|------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| 1. For each type of inpatient stay, how large is the gap between what hospitals charge and what Medicare pays?         | Stay type (`drg_definition`), covered charges (`average_covered_charges`), Medicare payments (`average_medicare_payments`), discharges (`total_discharges`), year | `inpatient_charges_2011` to `inpatient_charges_2015`                     | All fields are present in the charge tables. No missing values or zero Medicare payments were found, so the ratio can be computed. Hospital counts are stable across years (3,231 to 3,337), but distinct stay types rise from 100 (2011 to 2013) to 564 (2014). | How to combine hospitals into one figure per stay type (simple average or weighted by discharges). Which stay types appear in all years, and whether labels changed or stay types were added, so that year comparisons use only comparable stay types. |
| 2. For each type of inpatient stay, how much do average charges per hospital differ across states?                     | Stay type, state, covered charges, discharges                                                                                                                     | `inpatient_charges_*`, `hospital_general_info` (for state)               | State, stay type, and charges are available, covering 3,231 to 3,337 hospitals per year in the charge tables.                                                                                                                                                    | Whether `state` be reliably sourced from `hospital_general_info`. Using the hospital table drops unmatched hospitals, so the join match rate matters. Check whether state values agree between the two tables.                                         |
| 3. Within a given state, which hospitals charge much more or less than others in that state for the same type of stay? | Hospital ID (`provider_id`), hospital name, state, stay type, covered charges, Medicare payments, discharges                                                      | `inpatient_charges_*`, `hospital_general_info`                           | Hospital-level rows exist per stay type and year, and no duplicate hospital and stay type rows were found.                                                                                                                                                       | Hospital name will come from `hospital_general_info`. Whether low-volume hospitals distort the top and bottom lists, so a minimum discharge count may be needed. How "much more or less" is defined.                                                   |
| 4. Do hospitals with larger charge to payment gaps share traits, like hospital type or ownership?                      | Charge-to-payment ratio, hospital type (`hospital_type`), hospital ownership (`hospital_ownership`), hospital ID                                                  | `inpatient_charges_*` joined to `hospital_general_info` on `provider_id` | Hospital type and ownership columns exist and show no unexpected nulls.                                                                                                                                                                                          | Must test the join match rate for `provider_id` before comparison. Hospital attributes are from an unknown as-of date, matched to 2011 to 2015 charges.                                                                                                |

# 7. Feasibility risks and response

- **Risk 1:** Hospital general info table attributes don't have as-of information clarifying if any of those have values changed over time.
  - Evidence: Questions 2-4 use the `hospital_general_info` table, which has no missing or duplicate `provider_id` values.
    But the as-of date is not indicated on the table, and I have just inferred it from the table metadata. The charge data
    covers 2011-2015.
  - Response: I will confirm that provider_id lookups are found for all charge data records. For state, I will fall back to
    the field on the charge table if I am not able to use the `hospital_general_info` snapshot. I can also label any hospital
    attributes to indicate their unknown as-of date.
- **Risk 2:** My comparisons might be misleading depending on year-to-year row changes and skew between low and high
  volume hospitals, resulting in my comparison chart being unreliable.
  - Evidence: There is a visible jump in charge data row counts from year to year as well as in distinct DRG counts. 
    I haven't yet checked the distribution of discharge counts across the hospitals, so I am not sure what impact
    skewed-volume hospitals might have.
  - Response: I will profile the `total_discharges` counts across the hospitals and also check the year-over-year row
    count changes to look for any glaring anomalies. Will also confirm all DRGs in prior years are present in later
    years and if not, then will ensure to only compare DRGs present in the years being selected.
- **Risk 3:** The dashboard could be interpreted to be related to current prices, but all data is historical.
  - Evidence: The charges only cover 2011-2015.
  - Response: I will be explicit about the time period covered and use the "historical" label on the dashboard.
- **Fallback:** If the join to the `hospital_general_info` is not feasible due to the unknown as-of snapshot, I can drop
  or alter questions to remove those that rely on the fields in that table. For state, I can fall back on the value in the
  charges data tables. I could also narrow my data analysis target to a single year.

# 8. First P1 decision

My first consequential issue to resolve is to nail down the exact grain of my fact table and combine the multiple yearly
inpatient_charges_* data tables into a single fact table with a year attribute. I will test the grain of one hospital 
(`provider_id`), one type of stay (`drg_definition`), and one year. I already confirmed there were no duplicate candidate
key combinations within each yearly table. I will also need to confirm that the yearly charge data provider_id references
are all matched in the `hospital_general_info` table, to confirm I can use that as a source for the hospital detail lookup.
I will also check which stay types appear in every year, since distinct stay types rise from 100 in 2013 to 564 in 2014
while hospital counts stay flat.

# 9. AI/tool accountability

I used AI to suggest candidate BigQuery public datasets related to public health, draft SQL query patterns (including
the wildcard per-year profile query), and review my wording in each section. I treated its suggestions as leads and
verified them myself:
- I confirmed the dataset, table list, and location in BigQuery Studio and ran every query myself.
- I checked column names, types, and counts against my own INFORMATION_SCHEMA output and the column descriptions in the
  table metadata.
- AI suggested an overall rating field for question 4. My profiling showed it is "Not Available" for 2,006 of 5,336
  hospitals (37.6%), stored as text instead of NULL, so I left it out and kept question 4 to hospital type and
  ownership. An earlier version of this document incorrectly said it was missing for every row; I fixed that after
  re-running the query.
- AI initially described the hospital table as a single 2017 snapshot. The table metadata shows a 2021 modification
  date, so I describe the as-of date as unknown.
