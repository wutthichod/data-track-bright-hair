-- 02_stg.sql : one cleaned table per raw table. Same row count as raw.
CREATE SCHEMA IF NOT EXISTS stg;

-- Text cleaner: drop zero-width chars, stray leading Thai vowel/tone marks,
-- collapse whitespace, trim, '' -> NULL
CREATE OR REPLACE TEMP MACRO clean_text(x) AS
  NULLIF(trim(regexp_replace(
    regexp_replace(
      regexp_replace(x, '[\x{200B}-\x{200D}\x{FEFF}]', '', 'g'),
      '^[\x{0E31}\x{0E34}-\x{0E3A}\x{0E47}-\x{0E4E}]+', ''),
    '\s+', ' ', 'g')), '');

-- 'YYYY-MM' -> DATE (first of month)
CREATE OR REPLACE TEMP MACRO ym_to_date(x) AS
  CAST(clean_text(x) || '-01' AS DATE);

-- ── bills ─────────────────────────────────────────────────────────────
CREATE OR REPLACE TABLE stg.bills AS
SELECT
  clean_text(bill_id)                         AS bill_id,
  date                                        AS bill_date,
  CAST(date_trunc('month', date) AS DATE)     AS bill_month,
  clean_text(weekday)                         AS weekday,
  hour,
  duration_min,
  clean_text(primary_staff)                   AS staff_code,
  CASE left(clean_text(primary_staff), 1)
       WHEN 'S' THEN 'stylist' WHEN 'T' THEN 'assistant_other'
       ELSE 'unmapped' END                    AS staff_type,
  upper(clean_text(request_tag))              AS request_tag,     -- 'R' / 'N' / NULL
  clean_text(customer_id)                     AS customer_id,
  clean_text(customer_id) IS NOT NULL         AS has_customer_id,
  is_first_visit,
  total_thb,
  discount_thb,
  total_thb + discount_thb                    AS gross_thb,
  clean_text(main_service)                    AS main_service,
  CASE clean_text(main_category)
       WHEN 'อื่นๆ' THEN 'OTHER' WHEN 'ของแถมฟรี' THEN 'FREE GIFT'
       ELSE upper(clean_text(main_category)) END AS main_category,
  item_count,
  has_student_item,
  has_foreigner_tag,
  _row_num, _source_file
FROM raw.bills;

-- ── bill_items ────────────────────────────────────────────────────────
CREATE OR REPLACE TABLE stg.bill_items AS
SELECT
  _row_num                                    AS bill_item_id,    -- no natural key
  clean_text(bill_id)                         AS bill_id,
  date                                        AS item_date,
  clean_text(staff)                           AS staff_code,
  upper(clean_text(request_tag))              AS request_tag,
  clean_text(category)                        AS category_raw,
  CASE clean_text(category)
       WHEN 'อื่นๆ' THEN 'OTHER' WHEN 'ของแถมฟรี' THEN 'FREE GIFT'
       ELSE upper(clean_text(category)) END   AS category,
  clean_text(subcategory)                     AS subcategory,
  clean_text(item)                            AS item,
  qty,
  revenue_thb,
  _row_num, _source_file
FROM raw.bill_items;

-- ── promotions ────────────────────────────────────────────────────────
CREATE OR REPLACE TABLE stg.promotions AS
SELECT
  _row_num                                    AS promo_use_id,
  clean_text(bill_id)                         AS bill_id,
  clean_text(kind)                            AS kind_th,
  CASE clean_text(kind)
       WHEN 'สิทธิ์สมาชิก'   THEN 'member_benefit'
       WHEN 'ส่วนลดหน้าร้าน' THEN 'store_discount'
       WHEN 'แพ็กเกจ'       THEN 'package'
       WHEN 'คูปอง/รางวัล'  THEN 'coupon_reward'
       ELSE 'unmapped' END                    AS kind,
  CASE clean_text(action)
       WHEN 'ใช้สิทธิ์'   THEN 'redeem'
       WHEN 'ซื้อแพ็กเกจ' THEN 'buy_package'
       ELSE 'unmapped' END                    AS action,
  campaign                                    AS campaign_raw,    -- untouched, join key for step 3 map
  clean_text(campaign)                        AS campaign,
  CASE lower(clean_text(member_tier))
       WHEN 'standard' THEN 'Standard' WHEN 'silver' THEN 'Silver'
       WHEN 'gold' THEN 'Gold' WHEN 'platinum' THEN 'Platinum'
       WHEN 'vip' THEN 'VIP' END              AS member_tier,
  discount_thb,
  _row_num, _source_file
FROM raw.promotions;

-- ── customers ─────────────────────────────────────────────────────────
CREATE OR REPLACE TABLE stg.customers AS
SELECT
  clean_text(customer_id)                     AS customer_id,
  upper(clean_text(gender))                   AS gender,          -- 'M' / 'F' / NULL
  clean_text(age_band)                        AS age_band,
  CASE lower(clean_text(member_tier))
       WHEN 'standard' THEN 'Standard' WHEN 'silver' THEN 'Silver'
       WHEN 'gold' THEN 'Gold' WHEN 'platinum' THEN 'Platinum'
       WHEN 'vip' THEN 'VIP' END              AS member_tier,
  in_crm,
  ym_to_date(member_since_month)              AS member_since_month,
  pos_bills,
  pos_visit_days,
  pos_spend_thb,
  first_visit                                 AS first_visit_date,
  last_visit                                  AS last_visit_date,
  _row_num, _source_file
FROM raw.customers;

-- ── staff ─────────────────────────────────────────────────────────────
CREATE OR REPLACE TABLE stg.staff AS
SELECT
  clean_text(code)                            AS staff_code,
  clean_text(role)                            AS role_th,
  coalesce(NULLIF(regexp_extract(role, '\(([^)]+)\)', 1), ''), 'unmapped') AS role,
  CASE left(clean_text(code), 1)
       WHEN 'S' THEN 'stylist' WHEN 'T' THEN 'assistant_other'
       ELSE 'unmapped' END                    AS staff_type,
  ym_to_date(first_month)                     AS first_month,
  ym_to_date(last_month)                      AS last_month,
  active_last_90d,
  _row_num, _source_file
FROM raw.staff;

-- ── daily ─────────────────────────────────────────────────────────────
CREATE OR REPLACE TABLE stg.daily AS
SELECT
  date                                        AS day_date,
  clean_text(weekday)                         AS weekday,
  revenue_thb,
  bills,
  new_customers,
  _row_num, _source_file
FROM raw.daily;

-- ── monthly_summary ───────────────────────────────────────────────────
CREATE OR REPLACE TABLE stg.monthly_summary AS
SELECT
  ym_to_date(month)                           AS month,
  days_open,
  revenue_thb,
  revenue_per_day,
  bills,
  avg_bill_thb,
  discount_thb,
  customers,
  new_customers,
  bills_R                                     AS bills_requested,
  CAST(bills_N AS INTEGER)                    AS bills_non_requested,
  bills_student,
  _row_num, _source_file
FROM raw.monthly_summary;

-- ── channels ──────────────────────────────────────────────────────────
CREATE OR REPLACE TABLE stg.channels AS
SELECT
  ym_to_date(ym)                              AS month,
  CAST("Nรวม"        AS INTEGER)              AS customers_non_requested,
  CAST("Rรวม"        AS INTEGER)              AS customers_requested,
  CAST("รวมลูกค้า"     AS INTEGER)              AS customers_total,
  CAST("M"           AS INTEGER)              AS col_m_unknown,   -- meaning not documented
  CAST("โทร"         AS INTEGER)              AS booking_phone,
  CAST("หน้าร้าน"      AS INTEGER)              AS booking_walk_in,
  CAST("LINE"        AS INTEGER)              AS booking_line,
  CAST("IG/FB"       AS INTEGER)              AS booking_ig_fb,
  CAST("ช่าง"         AS INTEGER)              AS booking_via_stylist,
  CAST("รวมBooking"  AS INTEGER)              AS booking_total,
  "คูปองแทนเงินสด"                             AS cash_voucher_thb,
  "คูปอง Gowabi"                              AS gowabi_coupon_thb,
  "Total Money"                               AS total_money_thb,
  days                                        AS days_recorded,
  _row_num, _source_file
FROM raw.channels;

-- ── marketing_ads ─────────────────────────────────────────────────────
CREATE OR REPLACE TABLE stg.marketing_ads AS
SELECT
  ym_to_date(month)                           AS month,
  meta_ads_thb,
  tiktok_ads_thb,
  google_ads_thb,
  other_ads_thb,
  meta_ads_thb + tiktok_ads_thb + google_ads_thb + other_ads_thb AS total_ads_thb,
  lower(clean_text("source (est = estimated)")) = 'est'          AS is_estimated,
  _row_num, _source_file
FROM raw.marketing_ads;

-- ── sponsorships ──────────────────────────────────────────────────────
CREATE OR REPLACE TABLE stg.sponsorships AS
SELECT
  _row_num                                    AS sponsorship_id,
  ym_to_date(month)                           AS month,           -- NULL when missing in source
  clean_text(organisation_type)               AS organisation_type_th,
  CASE clean_text(organisation_type)
       WHEN 'คณะ / ภาควิชา (จุฬาฯ)' THEN 'chula_faculty'
       WHEN 'ชมรม / องค์การนิสิต'   THEN 'student_club'
       WHEN 'บ้านรับน้อง'           THEN 'freshmen_house'
       WHEN 'มหาวิทยาลัยอื่น'        THEN 'other_university'
       WHEN 'ไม่ระบุ'               THEN 'unspecified'
       ELSE 'unmapped' END                    AS organisation_type,
  CASE clean_text(status)
       WHEN 'เสร็จสมบูรณ์'    THEN 'completed'
       WHEN 'กำลังดำเนินการ'  THEN 'in_progress'
       WHEN 'ยังไม่เริ่ม'      THEN 'not_started'
       WHEN 'ไม่สปอนเซอร์'    THEN 'declined'
       WHEN 'ไม่ติดต่อกลับ'    THEN 'no_response'
       WHEN 'ยกเลิก'         THEN 'cancelled'
       WHEN 'ไม่ระบุ'         THEN 'unspecified'
       ELSE 'unmapped' END                    AS status,
  CASE clean_text(stage)
       WHEN 'ให้แล้ว'               THEN 'delivered'
       WHEN 'อยู่ระหว่างทำ'          THEN 'in_progress'
       WHEN 'ไม่สปอนเซอร์'          THEN 'declined'
       WHEN 'ไม่ติดต่อกลับ/ยกเลิก'   THEN 'no_response_or_cancelled'
       WHEN 'ไม่ระบุ'               THEN 'unspecified'
       ELSE 'unmapped' END                    AS stage,
  coupon_face_value_thb,
  water_packs,
  cash_thb,
  total_value_thb,
  content_delivered,
  _row_num, _source_file
FROM raw.sponsorships;