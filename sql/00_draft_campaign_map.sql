-- 00_draft_campaign_map.sql : run manually. Writes seeds/campaign_map_draft.csv for review.
COPY (
  WITH stats AS (
    SELECT p.campaign,
           count(*)                         AS n_uses,
           min(b.bill_date)                 AS first_used,
           max(b.bill_date)                 AS last_used,
           round(sum(p.discount_thb))       AS total_discount_thb,
           round(avg(b.is_first_visit::INT), 2) AS first_visit_rate
    FROM stg.promotions p
    LEFT JOIN stg.bills b USING (bill_id)
    WHERE p.campaign IS NOT NULL
    GROUP BY p.campaign
  ),
  guess AS (
    SELECT *,
      -- strip "1. " / "2." numbering and trailing dots
      trim(regexp_replace(regexp_replace(campaign, '^\d+\.\s*', ''), '\.+$', '')) AS campaign_clean,
      CASE                                                     -- order matters: first match wins
        WHEN campaign ILIKE '%ระบุเอง%'                                     THEN 'manual'
        WHEN regexp_matches(campaign, '(?i)cu ?nex|muvmi|gowabi')           THEN 'partner_platform'
        WHEN campaign ILIKE '%สมัครสมาชิก%'                                 THEN 'member_signup'
        WHEN regexp_matches(campaign, '(?i)(standard|silver|gold|platinum|vip) member') THEN 'member_tier'
        WHEN campaign ILIKE '%เดือนเกิด%'                                   THEN 'birthday'
        WHEN regexp_matches(campaign, '(?i)ชวนเพื่อน|เพื่อนใหม่')            THEN 'referral'
        WHEN regexp_matches(campaign, '(?i)ผู้ชนะ')                         THEN 'prize'
        WHEN regexp_matches(campaign, '(?i)สอบตก|booth')                    THEN 'campus_event'
        WHEN regexp_matches(campaign, '(?i)package|แพ็?คเกจ|\d+ ครั้ง')     THEN 'package'
        WHEN regexp_matches(campaign, '(?i)^ny |new year|\d+\.\d+ \d{4}|แคมเปญ') THEN 'seasonal'
        WHEN campaign ILIKE '%คูปองแทนเงินสด%'                              THEN 'cash_voucher'
        WHEN campaign ILIKE '%คูปองส่วนลด%'                                 THEN 'discount_coupon'
        WHEN regexp_matches(campaign, '(?i)free|ฟรี')                       THEN 'free_service'
        WHEN campaign ILIKE '%ทั้งร้าน%'                                    THEN 'storewide_pct'
        WHEN regexp_matches(campaign, '(?i)\d+ ?%|off|ลด')                  THEN 'service_pct'
        ELSE 'unmapped'
      END AS campaign_family
    FROM stats
  )
  SELECT campaign, campaign_clean, campaign_family,
         CASE campaign_family
           WHEN 'member_signup'    THEN 'acquisition'
           WHEN 'partner_platform' THEN 'acquisition'
           WHEN 'referral'         THEN 'acquisition'
           WHEN 'campus_event'     THEN 'acquisition'
           WHEN 'discount_coupon'  THEN 'acquisition'
           WHEN 'cash_voucher'     THEN 'acquisition'
           WHEN 'free_service'     THEN 'acquisition'
           WHEN 'storewide_pct'    THEN 'traffic'
           WHEN 'seasonal'         THEN 'traffic'
           WHEN 'service_pct'      THEN 'upsell'
           WHEN 'member_tier'      THEN 'retention'
           WHEN 'birthday'         THEN 'retention'
           WHEN 'package'          THEN 'retention'
           WHEN 'manual'           THEN 'manual'
           ELSE 'other'
         END                       AS campaign_goal,
         false                     AS reviewed,
         ''                        AS notes,
         n_uses, first_used, last_used, total_discount_thb, first_visit_rate
  FROM guess
  ORDER BY campaign_family, n_uses DESC
) TO 'seeds/campaign_map_draft.csv' (HEADER, DELIMITER ',');