-- =============================================================================
-- 05_marts.sql  |  Capa analítica (vistas) sobre el modelo en estrella
-- Window functions, CTEs, NTILE, LAG, medias móviles, cohortes y Pareto.
-- =============================================================================
CREATE SCHEMA IF NOT EXISTS mart;

-- 1) Ingresos mensuales con variación MoM, YoY y media móvil de 3 meses
CREATE OR REPLACE VIEW mart.v_monthly_revenue AS
WITH m AS (
    SELECT d.year_month, MIN(d.full_date) AS month_start,
           SUM(f.line_amount) AS revenue,
           COUNT(DISTINCT f.invoice_id) AS invoices
    FROM dw.fact_sales f JOIN dw.dim_date d USING (date_key)
    GROUP BY d.year_month
)
SELECT year_month, revenue, invoices,
       ROUND(100.0 * (revenue - LAG(revenue)     OVER w) / NULLIF(LAG(revenue)     OVER w, 0), 1) AS mom_pct,
       ROUND(100.0 * (revenue - LAG(revenue, 12) OVER w) / NULLIF(LAG(revenue, 12) OVER w, 0), 1) AS yoy_pct,
       ROUND(AVG(revenue) OVER (w ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2) AS moving_avg_3m,
       SUM(revenue) OVER (PARTITION BY LEFT(year_month, 4) ORDER BY year_month) AS ytd_revenue
FROM m
WINDOW w AS (ORDER BY year_month)
ORDER BY year_month;

-- 2) RFM por cliente (quintiles con NTILE) y segmento
CREATE OR REPLACE VIEW mart.v_customer_rfm AS
WITH base AS (
    SELECT c.customer_key, c.full_name, c.country,
           (SELECT MAX(full_date) FROM dw.dim_date d JOIN dw.fact_sales x USING (date_key)) - MAX(d.full_date) AS recency_days,
           COUNT(DISTINCT f.invoice_id) AS frequency,
           SUM(f.line_amount) AS monetary
    FROM dw.fact_sales f
    JOIN dw.dim_customer c USING (customer_key)
    JOIN dw.dim_date d USING (date_key)
    GROUP BY c.customer_key, c.full_name, c.country
), scored AS (
    SELECT *,
           NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,
           NTILE(5) OVER (ORDER BY frequency)         AS f_score,
           NTILE(5) OVER (ORDER BY monetary)          AS m_score
    FROM base
)
SELECT customer_key, full_name, country, recency_days, frequency, monetary,
       r_score, f_score, m_score,
       CASE WHEN r_score >= 4 AND m_score >= 4 THEN 'Campeones'
            WHEN r_score >= 3 AND m_score >= 3 THEN 'Leales'
            WHEN r_score <= 2 AND m_score >= 4 THEN 'En riesgo (alto valor)'
            WHEN r_score <= 2                  THEN 'Dormidos'
            ELSE 'Regulares' END AS segment
FROM scored
ORDER BY monetary DESC;

-- 3) Ingresos por género con participación
CREATE OR REPLACE VIEW mart.v_genre_revenue AS
SELECT t.genre_name,
       SUM(f.line_amount) AS revenue,
       SUM(f.quantity)    AS units,
       ROUND(100.0 * SUM(f.line_amount) / SUM(SUM(f.line_amount)) OVER (), 2) AS share_pct,
       RANK() OVER (ORDER BY SUM(f.line_amount) DESC) AS rank
FROM dw.fact_sales f JOIN dw.dim_track t USING (track_key)
GROUP BY t.genre_name
ORDER BY revenue DESC;

-- 4) Pareto de artistas: participación acumulada
CREATE OR REPLACE VIEW mart.v_artist_pareto AS
WITH a AS (
    SELECT t.artist_name, SUM(f.line_amount) AS revenue
    FROM dw.fact_sales f JOIN dw.dim_track t USING (track_key)
    GROUP BY t.artist_name
)
SELECT artist_name, revenue,
       ROW_NUMBER() OVER (ORDER BY revenue DESC, artist_name) AS rank,
       ROUND(100.0 * SUM(revenue) OVER (ORDER BY revenue DESC, artist_name) / SUM(revenue) OVER (), 2) AS cumulative_share_pct,
       CASE WHEN SUM(revenue) OVER (ORDER BY revenue DESC, artist_name)
                 / SUM(revenue) OVER () <= 0.80 THEN 'Top 80%' ELSE 'Cola' END AS pareto_class
FROM a
ORDER BY rank;

-- 5) Cohortes de retención por mes de primera compra
CREATE OR REPLACE VIEW mart.v_cohort_retention AS
WITH purchases AS (
    SELECT DISTINCT f.customer_key, d.year_month,
           (EXTRACT(YEAR FROM d.full_date) * 12 + EXTRACT(MONTH FROM d.full_date))::INT AS month_idx
    FROM dw.fact_sales f JOIN dw.dim_date d USING (date_key)
), first_p AS (
    SELECT customer_key, MIN(year_month) AS cohort, MIN(month_idx) AS first_idx
    FROM purchases GROUP BY customer_key
), act AS (
    SELECT fp.cohort, p.month_idx - fp.first_idx AS months_since, COUNT(DISTINCT p.customer_key) AS active_customers
    FROM purchases p JOIN first_p fp USING (customer_key)
    GROUP BY fp.cohort, p.month_idx - fp.first_idx
)
SELECT cohort, months_since, active_customers,
       ROUND(100.0 * active_customers / FIRST_VALUE(active_customers) OVER (PARTITION BY cohort ORDER BY months_since), 1) AS retention_pct
FROM act
ORDER BY cohort, months_since;

-- 6) Desempeño por ejecutivo de soporte
CREATE OR REPLACE VIEW mart.v_rep_performance AS
SELECT e.full_name AS rep, e.title, e.manager_name,
       COUNT(DISTINCT f.customer_key) AS customers,
       COUNT(DISTINCT f.invoice_id)   AS invoices,
       SUM(f.line_amount)             AS revenue,
       ROUND(SUM(f.line_amount) / NULLIF(COUNT(DISTINCT f.customer_key), 0), 2) AS revenue_per_customer,
       RANK() OVER (ORDER BY SUM(f.line_amount) DESC) AS rank
FROM dw.fact_sales f JOIN dw.dim_employee e USING (employee_key)
GROUP BY e.full_name, e.title, e.manager_name
ORDER BY revenue DESC;

-- 7) Ingresos por país
CREATE OR REPLACE VIEW mart.v_country_revenue AS
SELECT c.country,
       COUNT(DISTINCT c.customer_key) AS customers,
       SUM(f.line_amount) AS revenue,
       ROUND(SUM(f.line_amount) / COUNT(DISTINCT c.customer_key), 2) AS revenue_per_customer,
       ROUND(100.0 * SUM(f.line_amount) / SUM(SUM(f.line_amount)) OVER (), 2) AS share_pct
FROM dw.fact_sales f JOIN dw.dim_customer c USING (customer_key)
GROUP BY c.country
ORDER BY revenue DESC;
