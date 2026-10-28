-- =====================================================================
-- E-commerce SQL case study · 15 business questions
-- Author: Dibyanshi Poddar · Dialect: SQLite 3.25+ (window functions)
-- Net revenue = quantity × unit_price − discount_amount, delivered orders only
-- =====================================================================

-- Q1. Business snapshot: how big is the business, and how healthy is fulfilment?
SELECT
  COUNT(*)                                                         AS total_orders,
  SUM(order_status = 'Delivered')                                  AS delivered_orders,
  ROUND(100.0 * SUM(order_status = 'Cancelled') / COUNT(*), 1)     AS cancel_rate_pct,
  ROUND(100.0 * SUM(order_status = 'Returned')  / COUNT(*), 1)     AS return_rate_pct,
  (SELECT ROUND(SUM(oi.quantity * oi.unit_price - oi.discount_amount))
     FROM order_items oi JOIN orders o2 USING (order_id)
    WHERE o2.order_status = 'Delivered')                           AS net_revenue_inr,
  (SELECT ROUND(SUM(oi.quantity * oi.unit_price - oi.discount_amount) / COUNT(DISTINCT o2.order_id))
     FROM order_items oi JOIN orders o2 USING (order_id)
    WHERE o2.order_status = 'Delivered')                           AS avg_order_value_inr
FROM orders;

-- Q2. Monthly net revenue with month-on-month growth (LAG)
WITH monthly AS (
  SELECT strftime('%Y-%m', o.order_datetime) AS month,
         SUM(oi.quantity * oi.unit_price - oi.discount_amount) AS revenue
  FROM orders o JOIN order_items oi USING (order_id)
  WHERE o.order_status = 'Delivered'
  GROUP BY month
)
SELECT month,
       ROUND(revenue) AS net_revenue_inr,
       ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY month)) / LAG(revenue) OVER (ORDER BY month), 1) AS mom_growth_pct
FROM monthly
ORDER BY month;

-- Q3. Which categories make the most money, and at what margin?
SELECT p.category,
       ROUND(SUM(oi.quantity * oi.unit_price - oi.discount_amount))                       AS net_revenue_inr,
       ROUND(SUM(oi.quantity * oi.unit_price - oi.discount_amount - oi.quantity * p.unit_cost)) AS gross_profit_inr,
       ROUND(100.0 * SUM(oi.quantity * oi.unit_price - oi.discount_amount - oi.quantity * p.unit_cost)
                   / SUM(oi.quantity * oi.unit_price - oi.discount_amount), 1)            AS gross_margin_pct
FROM orders o
JOIN order_items oi USING (order_id)
JOIN products p USING (product_id)
WHERE o.order_status = 'Delivered'
GROUP BY p.category
ORDER BY net_revenue_inr DESC;

-- Q4. Top 3 products in each category by revenue (ROW_NUMBER)
WITH product_rev AS (
  SELECT p.category, p.product_name,
         SUM(oi.quantity * oi.unit_price - oi.discount_amount) AS revenue,
         ROW_NUMBER() OVER (PARTITION BY p.category
                            ORDER BY SUM(oi.quantity * oi.unit_price - oi.discount_amount) DESC) AS rnk
  FROM orders o JOIN order_items oi USING (order_id) JOIN products p USING (product_id)
  WHERE o.order_status = 'Delivered'
  GROUP BY p.category, p.product_id
)
SELECT category, rnk AS rank, product_name, ROUND(revenue) AS net_revenue_inr
FROM product_rev
WHERE rnk <= 3
ORDER BY category, rnk;

-- Q5. Running total of 2025 revenue, month by month (cumulative SUM)
WITH m AS (
  SELECT strftime('%m', o.order_datetime) AS month_no,
         SUM(oi.quantity * oi.unit_price - oi.discount_amount) AS revenue
  FROM orders o JOIN order_items oi USING (order_id)
  WHERE o.order_status = 'Delivered' AND strftime('%Y', o.order_datetime) = '2025'
  GROUP BY month_no
)
SELECT month_no,
       ROUND(revenue) AS net_revenue_inr,
       ROUND(SUM(revenue) OVER (ORDER BY month_no)) AS cumulative_revenue_inr,
       ROUND(100.0 * SUM(revenue) OVER (ORDER BY month_no) / SUM(revenue) OVER (), 1) AS pct_of_year
FROM m
ORDER BY month_no;

-- Q6. Year-on-year growth by region
WITH r AS (
  SELECT c.region,
         SUM(CASE WHEN strftime('%Y', o.order_datetime) = '2024' THEN oi.quantity * oi.unit_price - oi.discount_amount END) AS rev_2024,
         SUM(CASE WHEN strftime('%Y', o.order_datetime) = '2025' THEN oi.quantity * oi.unit_price - oi.discount_amount END) AS rev_2025
  FROM orders o JOIN order_items oi USING (order_id) JOIN customers c USING (customer_id)
  WHERE o.order_status = 'Delivered'
  GROUP BY c.region
)
SELECT region, ROUND(rev_2024) AS revenue_2024_inr, ROUND(rev_2025) AS revenue_2025_inr,
       ROUND(100.0 * (rev_2025 - rev_2024) / rev_2024, 1) AS yoy_growth_pct
FROM r
ORDER BY yoy_growth_pct DESC;

-- Q7. RFM segmentation: who are our best, at-risk and lost customers? (NTILE)
WITH base AS (
  SELECT o.customer_id,
         julianday('2026-01-01') - julianday(MAX(o.order_datetime)) AS recency_days,
         COUNT(DISTINCT o.order_id)                                  AS frequency,
         SUM(oi.quantity * oi.unit_price - oi.discount_amount)       AS monetary
  FROM orders o JOIN order_items oi USING (order_id)
  WHERE o.order_status = 'Delivered'
  GROUP BY o.customer_id
),
scored AS (
  SELECT *,
         NTILE(4) OVER (ORDER BY recency_days DESC) AS r,   -- 4 = most recent
         NTILE(4) OVER (ORDER BY frequency)         AS f,   -- 4 = most frequent
         NTILE(4) OVER (ORDER BY monetary)          AS m    -- 4 = highest spend
  FROM base
),
segmented AS (
  SELECT *,
         CASE WHEN r >= 3 AND f >= 3 AND m >= 3 THEN 'Champions'
              WHEN r >= 3 AND f >= 2             THEN 'Loyal'
              WHEN r >= 3                        THEN 'New or promising'
              WHEN r = 2                         THEN 'At risk'
              ELSE 'Lost' END AS segment
  FROM scored
)
SELECT segment,
       COUNT(*)                                    AS customers,
       ROUND(AVG(recency_days))                    AS avg_days_since_last_order,
       ROUND(AVG(frequency), 1)                    AS avg_orders,
       ROUND(SUM(monetary))                        AS revenue_inr,
       ROUND(100.0 * SUM(monetary) / SUM(SUM(monetary)) OVER (), 1) AS pct_of_revenue
FROM segmented
GROUP BY segment
ORDER BY revenue_inr DESC;

-- Q8. Cohort retention: of customers who first ordered in a quarter, what % ordered again 1, 2 and 3 months later?
WITH firsts AS (
  SELECT customer_id, MIN(date(order_datetime, 'start of month')) AS cohort_month
  FROM orders GROUP BY customer_id
),
activity AS (
  SELECT DISTINCT o.customer_id, f.cohort_month,
         (CAST(strftime('%Y', o.order_datetime) AS INT) - CAST(strftime('%Y', f.cohort_month) AS INT)) * 12
       + (CAST(strftime('%m', o.order_datetime) AS INT) - CAST(strftime('%m', f.cohort_month) AS INT)) AS month_n
  FROM orders o JOIN firsts f USING (customer_id)
)
SELECT strftime('%Y', cohort_month) || '-Q' || ((CAST(strftime('%m', cohort_month) AS INT) + 2) / 3) AS cohort_quarter,
       COUNT(DISTINCT CASE WHEN month_n = 0 THEN customer_id END) AS new_customers,
       ROUND(100.0 * COUNT(DISTINCT CASE WHEN month_n = 1 THEN customer_id END) / COUNT(DISTINCT CASE WHEN month_n = 0 THEN customer_id END), 1) AS m1_retention_pct,
       ROUND(100.0 * COUNT(DISTINCT CASE WHEN month_n = 2 THEN customer_id END) / COUNT(DISTINCT CASE WHEN month_n = 0 THEN customer_id END), 1) AS m2_retention_pct,
       ROUND(100.0 * COUNT(DISTINCT CASE WHEN month_n = 3 THEN customer_id END) / COUNT(DISTINCT CASE WHEN month_n = 0 THEN customer_id END), 1) AS m3_retention_pct
FROM activity
WHERE cohort_month < '2025-10-01'          -- only cohorts with 3 full months of follow-up
GROUP BY cohort_quarter
ORDER BY cohort_quarter;

-- Q9. How often do customers come back? Repeat rate and average gap between orders (LAG)
WITH seq AS (
  SELECT customer_id, order_datetime,
         LAG(order_datetime) OVER (PARTITION BY customer_id ORDER BY order_datetime) AS prev_order
  FROM orders
  WHERE order_status <> 'Cancelled'
),
per_customer AS (
  SELECT customer_id, COUNT(*) AS orders, AVG(julianday(order_datetime) - julianday(prev_order)) AS avg_gap_days
  FROM seq GROUP BY customer_id
)
SELECT COUNT(*)                                              AS buying_customers,
       ROUND(100.0 * SUM(orders > 1) / COUNT(*), 1)          AS repeat_customer_pct,
       ROUND(AVG(orders), 1)                                 AS avg_orders_per_customer,
       ROUND(AVG(avg_gap_days))                              AS avg_days_between_orders
FROM per_customer;

-- Q10. Pareto check: how much revenue comes from the top 20% of customers?
WITH spend AS (
  SELECT o.customer_id, SUM(oi.quantity * oi.unit_price - oi.discount_amount) AS revenue
  FROM orders o JOIN order_items oi USING (order_id)
  WHERE o.order_status = 'Delivered'
  GROUP BY o.customer_id
),
ranked AS (SELECT revenue, NTILE(5) OVER (ORDER BY revenue DESC) AS quintile FROM spend)
SELECT 'Top ' || (quintile * 20) || '% band' AS customer_band,
       COUNT(*) AS customers,
       ROUND(SUM(revenue)) AS revenue_inr,
       ROUND(100.0 * SUM(revenue) / SUM(SUM(revenue)) OVER (), 1) AS pct_of_revenue
FROM ranked
GROUP BY quintile
ORDER BY quintile;

-- Q11. Which acquisition channel brings the most valuable customers?
WITH cust_value AS (
  SELECT c.customer_id, c.acquisition_channel,
         COUNT(DISTINCT CASE WHEN o.order_status = 'Delivered' THEN o.order_id END) AS orders,
         COALESCE(SUM(CASE WHEN o.order_status = 'Delivered' THEN oi.quantity * oi.unit_price - oi.discount_amount END), 0) AS revenue
  FROM customers c
  LEFT JOIN orders o USING (customer_id)
  LEFT JOIN order_items oi USING (order_id)
  GROUP BY c.customer_id
)
SELECT acquisition_channel,
       COUNT(*)                                     AS customers,
       ROUND(100.0 * SUM(orders > 0) / COUNT(*), 1) AS activated_pct,
       ROUND(100.0 * SUM(orders > 1) / COUNT(*), 1) AS repeat_pct,
       ROUND(AVG(revenue))                          AS revenue_per_customer_inr
FROM cust_value
GROUP BY acquisition_channel
ORDER BY revenue_per_customer_inr DESC;

-- Q12. Do coupons pay off? Order value, discount cost and return rate by coupon
WITH ord AS (
  SELECT o.order_id, COALESCE(o.coupon_code, 'No coupon') AS coupon, o.order_status,
         SUM(oi.quantity * oi.unit_price) AS gross_value, SUM(oi.discount_amount) AS discount
  FROM orders o JOIN order_items oi USING (order_id)
  GROUP BY o.order_id
)
SELECT coupon,
       COUNT(*)                                                       AS orders,
       ROUND(AVG(gross_value))                                        AS avg_basket_before_discount_inr,
       ROUND(SUM(discount))                                           AS total_discount_inr,
       ROUND(100.0 * SUM(order_status = 'Returned') / COUNT(*), 1)    AS return_rate_pct
FROM ord
GROUP BY coupon
ORDER BY orders DESC;

-- Q13. Which categories get returned most? (share of units in returned orders)
SELECT p.category,
       SUM(oi.quantity)                                                                   AS units_sold,
       SUM(CASE WHEN o.order_status = 'Returned' THEN oi.quantity ELSE 0 END)             AS units_returned,
       ROUND(100.0 * SUM(CASE WHEN o.order_status = 'Returned' THEN oi.quantity ELSE 0 END)
                   / SUM(oi.quantity), 1)                                                 AS return_rate_pct
FROM orders o JOIN order_items oi USING (order_id) JOIN products p USING (product_id)
WHERE o.order_status <> 'Cancelled'
GROUP BY p.category
ORDER BY return_rate_pct DESC;

-- Q14. Delivery performance: on-time % by courier, in sale weeks vs normal weeks
WITH s AS (
  SELECT sh.courier,
         CASE WHEN date(o.order_datetime) BETWEEN '2024-10-01' AND '2024-10-08'
                OR date(o.order_datetime) BETWEEN '2025-09-22' AND '2025-09-29'
                OR date(o.order_datetime) BETWEEN '2024-07-12' AND '2024-07-14'
                OR date(o.order_datetime) BETWEEN '2025-07-11' AND '2025-07-13'
              THEN 'Sale' ELSE 'Normal' END AS period,
         julianday(sh.delivered_date) - julianday(date(o.order_datetime)) AS days_to_deliver,
         sh.delivered_date <= sh.promised_date AS on_time
  FROM shipments sh JOIN orders o USING (order_id)
)
SELECT courier,
       COUNT(*)                                                                             AS shipments,
       ROUND(AVG(days_to_deliver), 1)                                                       AS avg_days,
       ROUND(100.0 * AVG(on_time), 1)                                                       AS on_time_pct,
       ROUND(100.0 * AVG(CASE WHEN period = 'Normal' THEN on_time END), 1)                  AS on_time_normal_pct,
       ROUND(100.0 * AVG(CASE WHEN period = 'Sale'   THEN on_time END), 1)                  AS on_time_sale_pct
FROM s
GROUP BY courier
ORDER BY on_time_pct DESC;

-- Q15. Market basket: which product types are most often bought together? (self-join)
SELECT a.sub_category AS item_a, b.sub_category AS item_b, COUNT(*) AS orders_together
FROM (SELECT oi.order_id, p.sub_category FROM order_items oi JOIN products p USING (product_id)) a
JOIN (SELECT oi.order_id, p.sub_category FROM order_items oi JOIN products p USING (product_id)) b
  ON a.order_id = b.order_id AND a.sub_category < b.sub_category
GROUP BY item_a, item_b
ORDER BY orders_together DESC
LIMIT 10;
