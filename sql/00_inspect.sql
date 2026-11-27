-- What would DuckDB guess for each CSV?
SELECT 'bills' AS f, * FROM (DESCRIBE SELECT * FROM 'Bright-Case-Study-Dataset-CSV/bills.csv');
SELECT 'bill_items' AS f, * FROM (DESCRIBE SELECT * FROM 'Bright-Case-Study-Dataset-CSV/bill_items.csv');
SELECT 'promotions' AS f, * FROM (DESCRIBE SELECT * FROM 'Bright-Case-Study-Dataset-CSV/promotions.csv');
SELECT 'customers' AS f, * FROM (DESCRIBE SELECT * FROM 'Bright-Case-Study-Dataset-CSV/customers.csv');
SELECT 'monthly_summary' AS f, * FROM (DESCRIBE SELECT * FROM 'Bright-Case-Study-Dataset-CSV/monthly_summary.csv');
SELECT 'channels' AS f, * FROM (DESCRIBE SELECT * FROM 'Bright-Case-Study-Dataset-CSV/channels.csv');