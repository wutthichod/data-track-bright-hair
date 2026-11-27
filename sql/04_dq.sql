-- 04_dq.sql : data-quality rules, issues, summary. Reads stg only; changes nothing.
BEGIN TRANSACTION;

-- ── 4.1 Rule catalogue ────────────────────────────────────────────────
CREATE OR REPLACE TABLE stg.dq_rules AS
SELECT * FROM (VALUES
  -- keys
  ('K01','bills',          'bill_id is unique',                                   'error','exclude'),
  ('K02','bill_items',     'bill_items.bill_id exists in bills',                  'error','exclude'),
  ('K03','promotions',     'promotions.bill_id exists in bills',                  'error','exclude'),
  ('K04','bills',          'bills.customer_id exists in customers',               'warn', 'flag'),
  ('K05','customers',      'customer_id is unique',                               'error','exclude'),
  ('K06','bills',          'bills.staff_code exists in staff',                    'warn', 'flag'),
  ('K07','bills',          'bill has at least one item',                          'warn', 'flag'),
  -- reconciliation
  ('R01','bills',          'sum(item revenue) = bill total (±1 THB)',             'error','flag'),
  ('R02','bills',          'item_count = number of item rows or total qty',       'warn', 'flag'),
  ('R03','daily',          'daily revenue = sum(bill totals) (±1 THB)',           'error','flag'),
  ('R04','daily',          'daily bills = count(bills)',                          'error','flag'),
  ('R05','monthly_summary','monthly revenue = sum(daily revenue) (±1 THB)',       'error','flag'),
  ('R06','channels',       'booking channels sum to booking_total',               'warn', 'flag'),
  ('R07','channels',       'total_money within 2% of monthly revenue',            'warn', 'flag'),
  ('R08','channels',       'requested + non_requested = customers_total',         'warn', 'flag'),
  ('R09','bills',          'sum(promo discounts) = bill discount (±1 THB)',       'warn', 'flag'),
  ('R10','bill_items',     'item date = bill date',                               'error','flag'),
  ('R11','daily',          'daily new_customers = count(first-visit bills)',      'warn', 'flag'),
  -- value ranges
  ('V01','bills',          'hour within opening hours 9-21',                      'warn', 'flag'),
  ('V02','bills',          'total_thb >= 0',                                      'error','exclude'),
  ('V03','bills',          'discount_thb >= 0',                                   'error','exclude'),
  ('V04','bills',          'duration_min in (0, 480]',                            'warn', 'flag'),
  ('V05','bills',          'weekday matches date',                                'error','fix'),
  ('V06','raw',            'count columns stored as DOUBLE are whole numbers',    'error','fix'),
  ('V07','customers',      'first_visit_date <= last_visit_date',                 'error','flag'),
  ('V08','bills',          'request_tag in (R, N) or NULL',                       'error','flag'),
  ('V09','bill_items',     'qty > 0',                                             'warn', 'flag'),
  ('V10','customers',      'pos_visit_days <= pos_bills',                         'warn', 'flag'),
  ('V11','bills',          'zero-value bill (free service)',                      'info', 'flag'),
  -- completeness
  ('C01','bills',          'calendar day with no bills',                          'info', 'flag'),
  ('C02','channels',       'month missing between first and last channel month',  'warn', 'flag'),
  ('C03','channels',       'month only partially recorded (days < days in month)','warn', 'flag'),
  ('C04','sponsorships',   'sponsorship has no month',                            'warn', 'exclude'),
  ('C05','bills',          'bill has no customer_id (customer gave no phone)',    'info', 'flag'),
  -- known issues (README)
  ('KI01','bills',         'first-visit unreliable 2025-10-13..2025-11-02',       'warn', 'flag'),
  ('KI02','bills',         'N tag incomplete before 2023-08-20',                  'info', 'flag'),
  ('KI03','bills',         'first visit in warm-up (data starts 2022-08; before 2023-02 many "new" are old)', 'warn','flag'),
  ('KI04','marketing_ads', 'ad spend is estimated (clicks x CPC)',                'info', 'flag'),
  ('KI05','bills',         'has_foreigner_tag not recorded before 2026-10-12',    'info', 'flag'),
  -- mapping
  ('M01','promotions',     'campaign exists in campaign_map',                     'error','fix'),
  ('M02','campaign_map',   'campaign_family / goal are valid values',             'error','fix'),
  ('M03','stg',            'no unmapped code values',                             'error','fix'),
  ('M04','campaign_map',   'campaign key is unique in seed',                      'error','fix')
) t(rule_id, table_name, description, severity, default_action);

-- ── 4.2 Issues: every check returns (rule_id, record_key, observed, expected) ──
CREATE OR REPLACE TABLE stg.dq_issues AS
WITH
item_tot   AS (SELECT bill_id, sum(revenue_thb) AS rev, count(*) AS n_rows, sum(qty) AS qty
               FROM stg.bill_items GROUP BY bill_id),
bill_day   AS (SELECT bill_date, sum(total_thb) AS rev, count(*) AS n,
                      sum(is_first_visit::INT) AS n_new
               FROM stg.bills GROUP BY bill_date),
daily_mon  AS (SELECT CAST(date_trunc('month', day_date) AS DATE) AS month, sum(revenue_thb) AS rev
               FROM stg.daily GROUP BY 1),
promo_bill AS (SELECT bill_id, sum(discount_thb) AS disc FROM stg.promotions GROUP BY bill_id),
all_days   AS (SELECT CAST(unnest(generate_series(min(bill_date), max(bill_date), INTERVAL 1 DAY)) AS DATE) AS d
               FROM stg.bills),
ch_months  AS (SELECT CAST(unnest(generate_series(min(month), max(month), INTERVAL 1 MONTH)) AS DATE) AS m
               FROM stg.channels)

-- K: keys
SELECT 'K01' AS rule_id, bill_id AS record_key, count(*)::VARCHAR AS observed, '1' AS expected
  FROM stg.bills GROUP BY bill_id HAVING count(*) > 1
UNION ALL
SELECT 'K02', i.bill_item_id::VARCHAR, i.bill_id, 'bill exists'
  FROM stg.bill_items i ANTI JOIN stg.bills b USING (bill_id)
UNION ALL
SELECT 'K03', p.promo_use_id::VARCHAR, p.bill_id, 'bill exists'
  FROM stg.promotions p ANTI JOIN stg.bills b USING (bill_id)
UNION ALL
SELECT 'K04', b.bill_id, b.customer_id, 'customer exists'
  FROM (SELECT * FROM stg.bills WHERE customer_id IS NOT NULL) b
  ANTI JOIN stg.customers c USING (customer_id)
UNION ALL
SELECT 'K05', customer_id, count(*)::VARCHAR, '1'
  FROM stg.customers GROUP BY customer_id HAVING count(*) > 1
UNION ALL
SELECT 'K06', b.staff_code, count(*)::VARCHAR || ' bills', 'staff exists'
  FROM stg.bills b ANTI JOIN stg.staff s USING (staff_code) GROUP BY b.staff_code
UNION ALL
SELECT 'K07', b.bill_id, '0 items', '>= 1'
  FROM stg.bills b ANTI JOIN item_tot i USING (bill_id)

-- R: reconciliation
UNION ALL
SELECT 'R01', b.bill_id, round(i.rev, 2)::VARCHAR, round(b.total_thb, 2)::VARCHAR
  FROM stg.bills b JOIN item_tot i USING (bill_id)
  WHERE abs(i.rev - b.total_thb) > 1
UNION ALL
SELECT 'R02', b.bill_id, b.item_count::VARCHAR, i.n_rows::VARCHAR || ' rows / ' || i.qty::VARCHAR || ' qty'
  FROM stg.bills b JOIN item_tot i USING (bill_id)
  WHERE b.item_count NOT IN (i.n_rows, i.qty)
UNION ALL
SELECT 'R03', coalesce(d.day_date, x.bill_date)::VARCHAR,
       round(coalesce(d.revenue_thb, 0), 2)::VARCHAR, round(coalesce(x.rev, 0), 2)::VARCHAR
  FROM stg.daily d FULL JOIN bill_day x ON d.day_date = x.bill_date
  WHERE abs(coalesce(d.revenue_thb, 0) - coalesce(x.rev, 0)) > 1
UNION ALL
SELECT 'R04', coalesce(d.day_date, x.bill_date)::VARCHAR,
       coalesce(d.bills, 0)::VARCHAR, coalesce(x.n, 0)::VARCHAR
  FROM stg.daily d FULL JOIN bill_day x ON d.day_date = x.bill_date
  WHERE coalesce(d.bills, 0) <> coalesce(x.n, 0)
UNION ALL
SELECT 'R05', coalesce(m.month, dm.month)::VARCHAR,
       round(coalesce(m.revenue_thb, 0))::VARCHAR, round(coalesce(dm.rev, 0))::VARCHAR
  FROM stg.monthly_summary m FULL JOIN daily_mon dm USING (month)
  WHERE abs(coalesce(m.revenue_thb, 0) - coalesce(dm.rev, 0)) > 1
UNION ALL
SELECT 'R06', month::VARCHAR,
       (booking_phone + booking_walk_in + booking_line + booking_ig_fb + booking_via_stylist)::VARCHAR,
       booking_total::VARCHAR
  FROM stg.channels
  WHERE booking_phone + booking_walk_in + booking_line + booking_ig_fb + booking_via_stylist <> booking_total
UNION ALL
SELECT 'R07', c.month::VARCHAR, round(c.total_money_thb)::VARCHAR, round(m.revenue_thb)::VARCHAR
  FROM stg.channels c JOIN stg.monthly_summary m USING (month)
  WHERE abs(c.total_money_thb - m.revenue_thb) / m.revenue_thb > 0.02
UNION ALL
SELECT 'R08', month::VARCHAR, (customers_requested + customers_non_requested)::VARCHAR, customers_total::VARCHAR
  FROM stg.channels
  WHERE customers_requested + customers_non_requested <> customers_total
UNION ALL
SELECT 'R09', b.bill_id, round(p.disc, 2)::VARCHAR, round(b.discount_thb, 2)::VARCHAR
  FROM stg.bills b JOIN promo_bill p USING (bill_id)
  WHERE abs(p.disc - b.discount_thb) > 1
UNION ALL
SELECT 'R10', i.bill_item_id::VARCHAR, i.item_date::VARCHAR, b.bill_date::VARCHAR
  FROM stg.bill_items i JOIN stg.bills b USING (bill_id)
  WHERE i.item_date <> b.bill_date
UNION ALL
SELECT 'R11', d.day_date::VARCHAR, d.new_customers::VARCHAR, coalesce(x.n_new, 0)::VARCHAR
  FROM stg.daily d LEFT JOIN bill_day x ON d.day_date = x.bill_date
  WHERE d.new_customers <> coalesce(x.n_new, 0)

-- V: value ranges
UNION ALL
SELECT 'V01', bill_id, hour::VARCHAR, '9-21' FROM stg.bills WHERE hour NOT BETWEEN 9 AND 21
UNION ALL
SELECT 'V02', bill_id, total_thb::VARCHAR, '>= 0' FROM stg.bills WHERE total_thb < 0
UNION ALL
SELECT 'V03', bill_id, discount_thb::VARCHAR, '>= 0' FROM stg.bills WHERE discount_thb < 0
UNION ALL
SELECT 'V04', bill_id, coalesce(duration_min::VARCHAR, 'NULL'), '(0, 480]'
  FROM stg.bills WHERE duration_min IS NULL OR duration_min <= 0 OR duration_min > 480
UNION ALL
SELECT 'V05', bill_id, weekday, dayname(bill_date) FROM stg.bills WHERE weekday <> dayname(bill_date)
UNION ALL
SELECT 'V06', 'monthly_summary ' || month || ' bills_N', bills_N::VARCHAR, 'whole number'
  FROM raw.monthly_summary WHERE bills_N <> floor(bills_N)
UNION ALL
SELECT 'V06', 'channels ' || ym || ' ' || col, v::VARCHAR, 'whole number'
  FROM (UNPIVOT raw.channels
        ON "Nรวม", "Rรวม", "รวมลูกค้า", "M", "โทร", "หน้าร้าน", "LINE", "IG/FB", "ช่าง", "รวมBooking"
        INTO NAME col VALUE v)
  WHERE v <> floor(v)
UNION ALL
SELECT 'V07', customer_id, first_visit_date || ' > ' || last_visit_date, 'first <= last'
  FROM stg.customers WHERE first_visit_date > last_visit_date
UNION ALL
SELECT 'V08', bill_id, request_tag, 'R / N / NULL'
  FROM stg.bills WHERE request_tag IS NOT NULL AND request_tag NOT IN ('R', 'N')
UNION ALL
SELECT 'V09', bill_item_id::VARCHAR, qty::VARCHAR, '> 0' FROM stg.bill_items WHERE qty <= 0
UNION ALL
SELECT 'V10', customer_id, pos_visit_days || ' days / ' || pos_bills || ' bills', 'days <= bills'
  FROM stg.customers WHERE pos_visit_days > pos_bills
UNION ALL
SELECT 'V11', bill_id, '0', '> 0' FROM stg.bills WHERE total_thb = 0

-- C: completeness
UNION ALL
SELECT 'C01', d::VARCHAR, 'no bills', '>= 1 bill'
  FROM all_days WHERE d NOT IN (SELECT bill_date FROM stg.bills)
UNION ALL
SELECT 'C02', m::VARCHAR, 'missing', 'row exists'
  FROM ch_months WHERE m NOT IN (SELECT month FROM stg.channels)
UNION ALL
SELECT 'C03', month::VARCHAR, days_recorded::VARCHAR, day(last_day(month))::VARCHAR
  FROM stg.channels WHERE days_recorded < day(last_day(month))
UNION ALL
SELECT 'C04', sponsorship_id::VARCHAR, 'NULL', 'month' FROM stg.sponsorships WHERE month IS NULL
UNION ALL
SELECT 'C05', bill_id, 'NULL', 'customer_id' FROM stg.bills WHERE customer_id IS NULL

-- KI: known issues
UNION ALL
SELECT 'KI01', bill_id, bill_date::VARCHAR, 'outside window'
  FROM stg.bills WHERE bill_date BETWEEN DATE '2025-10-13' AND DATE '2025-11-02'
UNION ALL
SELECT 'KI02', bill_id, bill_date::VARCHAR, '>= 2023-08-20'
  FROM stg.bills WHERE bill_date < DATE '2023-08-20'
UNION ALL
SELECT 'KI03', bill_id, bill_date::VARCHAR, '>= 2023-02-01'
  FROM stg.bills WHERE is_first_visit AND bill_date < DATE '2023-02-01'
UNION ALL
SELECT 'KI04', month::VARCHAR, 'est', 'actual' FROM stg.marketing_ads WHERE is_estimated
UNION ALL
SELECT 'KI05', 'bills.has_foreigner_tag', 'not recorded', 'from 2026-10-12'   -- column-level, one row

-- M: mapping
UNION ALL
SELECT 'M01', p.campaign, count(*)::VARCHAR || ' uses', 'in campaign_map'
  FROM stg.promotions p ANTI JOIN stg.campaign_map m USING (campaign)
  WHERE p.campaign IS NOT NULL GROUP BY p.campaign
UNION ALL
SELECT 'M02', campaign, campaign_family || ' / ' || campaign_goal, 'valid family / goal'
  FROM stg.campaign_map
  WHERE campaign_family IS NULL OR campaign_family = 'unmapped'
     OR campaign_goal NOT IN ('acquisition','upsell','retention','traffic','manual','other')
UNION ALL
SELECT 'M03', 'promotions.kind ' || kind_th, count(*)::VARCHAR, 'mapped'
  FROM stg.promotions WHERE kind = 'unmapped' GROUP BY kind_th
UNION ALL
SELECT 'M03', 'promotions.action', count(*)::VARCHAR, 'mapped'
  FROM stg.promotions WHERE action = 'unmapped'
UNION ALL
SELECT 'M03', 'staff.role ' || role_th, count(*)::VARCHAR, 'mapped'
  FROM stg.staff WHERE role = 'unmapped' GROUP BY role_th
UNION ALL
SELECT 'M03', 'bills.staff_type ' || staff_code, count(*)::VARCHAR, 'mapped'
  FROM stg.bills WHERE staff_type = 'unmapped' GROUP BY staff_code
UNION ALL
SELECT 'M03', 'sponsorships.' || col || ' ' || coalesce(v, 'NULL'), count(*)::VARCHAR, 'mapped'
  FROM (SELECT 'organisation_type' AS col, organisation_type_th AS v FROM stg.sponsorships WHERE organisation_type = 'unmapped'
        UNION ALL SELECT 'status', NULL FROM stg.sponsorships WHERE status = 'unmapped'
        UNION ALL SELECT 'stage',  NULL FROM stg.sponsorships WHERE stage  = 'unmapped')
  GROUP BY ALL
UNION ALL
SELECT 'M04', campaign, count(*)::VARCHAR, '1'
  FROM stg.campaign_map GROUP BY campaign HAVING count(*) > 1;

-- ── 4.3 Summary ───────────────────────────────────────────────────────
CREATE OR REPLACE TABLE stg.dq_summary AS
SELECT r.rule_id, r.table_name, r.description, r.severity, r.default_action,
       count(i.rule_id) AS n_issues,
       list(i.record_key ORDER BY i.record_key) FILTER (WHERE i.rule_id IS NOT NULL)[1:5] AS examples
FROM stg.dq_rules r
LEFT JOIN stg.dq_issues i USING (rule_id)
GROUP BY ALL
ORDER BY r.rule_id;

-- Guard: an issue whose rule_id isn't in the catalogue means a typo -> fail the run
SELECT CASE WHEN count(*) > 0 THEN error('dq_issues has rule_id not in dq_rules') END
FROM stg.dq_issues ANTI JOIN stg.dq_rules USING (rule_id);

COMMIT;