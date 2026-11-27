-- 01_load_raw.sql
-- Load every CSV as-is into the raw schema. Rebuilt on every run.
-- Rules: explicit types (no guessing), explicit CSV format, no cleaning here.

CREATE SCHEMA IF NOT EXISTS raw;

-- Reusable loader: fixed CSV format + 3 tracking columns.
-- TEMP = exists only for this connection, not saved in bright.duckdb.
CREATE OR REPLACE TEMP MACRO raw_csv(path, cols) AS TABLE
  SELECT * RENAME (filename AS _source_file),
         row_number() OVER () AS _row_num,
         now()               AS _loaded_at
  FROM read_csv(path, header=true, delim=',', quote='"', escape='"',
                filename=true, columns=cols);

-- ── Transaction tables ────────────────────────────────────────────────
CREATE OR REPLACE TABLE raw.bills AS
SELECT * FROM raw_csv('Bright-Case-Study-Dataset-CSV/bills.csv', {
  'bill_id':'VARCHAR', 'date':'DATE', 'weekday':'VARCHAR', 'hour':'INTEGER',
  'duration_min':'DOUBLE', 'primary_staff':'VARCHAR', 'request_tag':'VARCHAR',
  'customer_id':'VARCHAR', 'is_first_visit':'BOOLEAN', 'total_thb':'DOUBLE',
  'discount_thb':'DOUBLE', 'main_service':'VARCHAR', 'main_category':'VARCHAR',
  'item_count':'INTEGER', 'has_student_item':'BOOLEAN', 'has_foreigner_tag':'BOOLEAN'});

CREATE OR REPLACE TABLE raw.bill_items AS
SELECT * FROM raw_csv('Bright-Case-Study-Dataset-CSV/bill_items.csv', {
  'bill_id':'VARCHAR', 'date':'DATE', 'staff':'VARCHAR', 'request_tag':'VARCHAR',
  'category':'VARCHAR', 'subcategory':'VARCHAR', 'item':'VARCHAR',
  'qty':'INTEGER', 'revenue_thb':'DOUBLE'});

CREATE OR REPLACE TABLE raw.promotions AS
SELECT * FROM raw_csv('Bright-Case-Study-Dataset-CSV/promotions.csv', {
  'bill_id':'VARCHAR', 'kind':'VARCHAR', 'action':'VARCHAR', 'campaign':'VARCHAR',
  'member_tier':'VARCHAR', 'discount_thb':'DOUBLE'});

-- ── Reference tables ──────────────────────────────────────────────────
CREATE OR REPLACE TABLE raw.customers AS
SELECT * FROM raw_csv('Bright-Case-Study-Dataset-CSV/customers.csv', {
  'customer_id':'VARCHAR', 'gender':'VARCHAR', 'age_band':'VARCHAR',
  'member_tier':'VARCHAR', 'in_crm':'BOOLEAN', 'member_since_month':'VARCHAR',
  'pos_bills':'INTEGER', 'pos_visit_days':'INTEGER', 'pos_spend_thb':'DOUBLE',
  'first_visit':'DATE', 'last_visit':'DATE'});

CREATE OR REPLACE TABLE raw.staff AS
SELECT * FROM raw_csv('Bright-Case-Study-Dataset-CSV/staff.csv', {
  'code':'VARCHAR', 'role':'VARCHAR', 'first_month':'VARCHAR',
  'last_month':'VARCHAR', 'active_last_90d':'BOOLEAN'});

-- ── Pre-aggregated tables ─────────────────────────────────────────────
CREATE OR REPLACE TABLE raw.daily AS
SELECT * FROM raw_csv('Bright-Case-Study-Dataset-CSV/daily.csv', {
  'date':'DATE', 'weekday':'VARCHAR', 'revenue_thb':'DOUBLE',
  'bills':'INTEGER', 'new_customers':'INTEGER'});

CREATE OR REPLACE TABLE raw.monthly_summary AS
SELECT * FROM raw_csv('Bright-Case-Study-Dataset-CSV/monthly_summary.csv', {
  'month':'VARCHAR', 'days_open':'INTEGER', 'revenue_thb':'DOUBLE',
  'revenue_per_day':'DOUBLE', 'bills':'INTEGER', 'avg_bill_thb':'DOUBLE',
  'discount_thb':'DOUBLE', 'customers':'INTEGER', 'new_customers':'INTEGER',
  'bills_R':'INTEGER', 'bills_N':'DOUBLE', 'bills_student':'INTEGER'});

CREATE OR REPLACE TABLE raw.channels AS
SELECT * FROM raw_csv('Bright-Case-Study-Dataset-CSV/channels.csv', {
  'ym':'VARCHAR', 'Nรวม':'DOUBLE', 'Rรวม':'DOUBLE', 'รวมลูกค้า':'DOUBLE',
  'M':'DOUBLE', 'โทร':'DOUBLE', 'หน้าร้าน':'DOUBLE', 'LINE':'DOUBLE',
  'IG/FB':'DOUBLE', 'ช่าง':'DOUBLE', 'รวมBooking':'DOUBLE',
  'คูปองแทนเงินสด':'DOUBLE', 'คูปอง Gowabi':'DOUBLE',
  'Total Money':'DOUBLE', 'days':'INTEGER'});

-- ── Marketing tables ──────────────────────────────────────────────────
CREATE OR REPLACE TABLE raw.marketing_ads AS
SELECT * FROM raw_csv('Bright-Case-Study-Dataset-CSV/marketing_ads.csv', {
  'month':'VARCHAR', 'meta_ads_thb':'DOUBLE', 'tiktok_ads_thb':'DOUBLE',
  'google_ads_thb':'DOUBLE', 'other_ads_thb':'DOUBLE',
  'source (est = estimated)':'VARCHAR'});

CREATE OR REPLACE TABLE raw.sponsorships AS
SELECT * FROM raw_csv('Bright-Case-Study-Dataset-CSV/sponsorships.csv', {
  'month':'VARCHAR', 'organisation_type':'VARCHAR', 'status':'VARCHAR',
  'stage':'VARCHAR', 'coupon_face_value_thb':'DOUBLE', 'water_packs':'DOUBLE',
  'cash_thb':'DOUBLE', 'total_value_thb':'DOUBLE', 'content_delivered':'BOOLEAN'});

-- ── Documentation ─────────────────────────────────────────────────────
CREATE OR REPLACE TABLE raw.readme AS
SELECT filename AS _source_file, content, now() AS _loaded_at
FROM read_text('Bright-Case-Study-Dataset-CSV/README.txt');