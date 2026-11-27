-- 03_seeds.sql : load hand-maintained mapping files into stg.
BEGIN TRANSACTION;

CREATE OR REPLACE TABLE stg.campaign_map AS
SELECT campaign, campaign_clean, campaign_family, campaign_goal, reviewed, notes
FROM read_csv('seeds/campaign_map.csv', header=true, delim=',', quote='"', escape='"', columns={
  'campaign':'VARCHAR', 'campaign_clean':'VARCHAR', 'campaign_family':'VARCHAR',
  'campaign_goal':'VARCHAR', 'reviewed':'BOOLEAN', 'notes':'VARCHAR',
  'n_uses':'INTEGER', 'first_used':'DATE', 'last_used':'DATE',
  'total_discount_thb':'DOUBLE', 'first_visit_rate':'DOUBLE'});

CREATE OR REPLACE TABLE stg.platform_map AS
SELECT * FROM read_csv('seeds/platform_map.csv', header=true, delim=',', quote='"', escape='"', columns={
  'match_field':'VARCHAR', 'pattern':'VARCHAR', 'platform':'VARCHAR', 'notes':'VARCHAR'});

COMMIT;