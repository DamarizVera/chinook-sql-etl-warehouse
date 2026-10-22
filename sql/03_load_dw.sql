-- =============================================================================
-- 03_load_dw.sql  |  Carga incremental del DW (UPSERT con ON CONFLICT)
-- Orden: dim_date -> dim_employee -> dim_customer -> dim_track -> fact_sales
-- Se puede re-ejecutar sin duplicar datos (idempotente).
-- =============================================================================

-- ---- dim_date: calendario completo 2021-2026 ---------------------------------
INSERT INTO dw.dim_date
SELECT
    TO_CHAR(d, 'YYYYMMDD')::INT,
    d::date,
    EXTRACT(YEAR    FROM d)::INT,
    EXTRACT(QUARTER FROM d)::INT,
    EXTRACT(MONTH   FROM d)::INT,
    TO_CHAR(d, 'TMMonth'),
    TO_CHAR(d, 'YYYY-MM'),
    EXTRACT(WEEK FROM d)::INT,
    EXTRACT(ISODOW FROM d)::INT,
    TO_CHAR(d, 'TMDay'),
    EXTRACT(ISODOW FROM d) IN (6, 7)
FROM GENERATE_SERIES('2021-01-01'::date, '2026-12-31'::date, '1 day') AS g(d)
ON CONFLICT (date_key) DO NOTHING;

-- ---- dim_employee (primero sin manager; el nombre se completa con self-join) --
INSERT INTO dw.dim_employee (employee_id, full_name, title, hire_date, manager_name)
SELECT e.employee_id, e.full_name, e.title, e.hire_date, m.full_name
FROM stg.employee e
LEFT JOIN stg.employee m ON m.employee_id = e.manager_id
ON CONFLICT (employee_id) DO UPDATE
SET full_name    = EXCLUDED.full_name,
    title        = EXCLUDED.title,
    hire_date    = EXCLUDED.hire_date,
    manager_name = EXCLUDED.manager_name,
    updated_at   = now();

-- ---- dim_customer ------------------------------------------------------------
INSERT INTO dw.dim_customer (customer_id, full_name, company, city, state, country, email, employee_key)
SELECT c.customer_id, c.full_name, c.company, c.city, c.state, c.country, c.email, de.employee_key
FROM stg.customer c
LEFT JOIN dw.dim_employee de ON de.employee_id = c.support_rep_id
ON CONFLICT (customer_id) DO UPDATE
SET full_name    = EXCLUDED.full_name,
    company      = EXCLUDED.company,
    city         = EXCLUDED.city,
    state        = EXCLUDED.state,
    country      = EXCLUDED.country,
    email        = EXCLUDED.email,
    employee_key = EXCLUDED.employee_key,
    updated_at   = now();

-- ---- dim_track ---------------------------------------------------------------
INSERT INTO dw.dim_track (track_id, track_name, album_title, artist_name, genre_name,
                          media_type, composer, duration_seconds, list_price)
SELECT t.track_id, t.track_name, t.album_title, t.artist_name, t.genre_name,
       t.media_type, t.composer, t.duration_seconds, t.unit_price
FROM stg.track t
ON CONFLICT (track_id) DO UPDATE
SET track_name       = EXCLUDED.track_name,
    album_title      = EXCLUDED.album_title,
    artist_name      = EXCLUDED.artist_name,
    genre_name       = EXCLUDED.genre_name,
    media_type       = EXCLUDED.media_type,
    composer         = EXCLUDED.composer,
    duration_seconds = EXCLUDED.duration_seconds,
    list_price       = EXCLUDED.list_price,
    updated_at       = now();

-- ---- fact_sales --------------------------------------------------------------
INSERT INTO dw.fact_sales (invoice_line_id, invoice_id, date_key, customer_key, track_key,
                           employee_key, quantity, unit_price, line_amount)
SELECT il.invoice_line_id,
       il.invoice_id,
       TO_CHAR(il.invoice_date, 'YYYYMMDD')::INT,
       dc.customer_key,
       dt.track_key,
       dc.employee_key,
       il.quantity,
       il.unit_price,
       il.line_amount
FROM stg.invoice_line il
JOIN dw.dim_customer dc ON dc.customer_id = il.customer_id
JOIN dw.dim_track    dt ON dt.track_id    = il.track_id
ON CONFLICT (invoice_line_id) DO UPDATE
SET invoice_id   = EXCLUDED.invoice_id,
    date_key     = EXCLUDED.date_key,
    customer_key = EXCLUDED.customer_key,
    track_key    = EXCLUDED.track_key,
    employee_key = EXCLUDED.employee_key,
    quantity     = EXCLUDED.quantity,
    unit_price   = EXCLUDED.unit_price,
    line_amount  = EXCLUDED.line_amount;

ANALYZE dw.fact_sales;
