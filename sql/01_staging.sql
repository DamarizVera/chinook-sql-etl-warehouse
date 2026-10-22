-- =============================================================================
-- 01_staging.sql  |  Capa STAGING: limpieza y estandarización de la fuente
-- Lee del esquema `src` (Chinook tal como viene) y deja tablas limpias en `stg`.
-- Idempotente: se puede ejecutar N veces (DROP + CREATE).
-- =============================================================================
CREATE SCHEMA IF NOT EXISTS stg;

DROP TABLE IF EXISTS stg.customer CASCADE;
CREATE TABLE stg.customer AS
SELECT
    c.customer_id,
    INITCAP(TRIM(c.first_name))                         AS first_name,
    INITCAP(TRIM(c.last_name))                          AS last_name,
    INITCAP(TRIM(c.first_name)) || ' ' || INITCAP(TRIM(c.last_name)) AS full_name,
    NULLIF(TRIM(c.company), '')                         AS company,
    INITCAP(TRIM(c.city))                               AS city,
    COALESCE(NULLIF(TRIM(c.state), ''), 'N/A')          AS state,
    TRIM(c.country)                                     AS country,
    LOWER(TRIM(c.email))                                AS email,
    c.support_rep_id
FROM src.customer c;

DROP TABLE IF EXISTS stg.employee CASCADE;
CREATE TABLE stg.employee AS
SELECT
    e.employee_id,
    INITCAP(TRIM(e.first_name)) || ' ' || INITCAP(TRIM(e.last_name)) AS full_name,
    TRIM(e.title)                                       AS title,
    e.hire_date::date                                   AS hire_date,
    e.reports_to                                        AS manager_id
FROM src.employee e;

DROP TABLE IF EXISTS stg.track CASCADE;
CREATE TABLE stg.track AS
SELECT
    t.track_id,
    TRIM(t.name)                                        AS track_name,
    COALESCE(al.title, 'Unknown album')                 AS album_title,
    COALESCE(ar.name,  'Unknown artist')                AS artist_name,
    COALESCE(g.name,   'Unknown genre')                 AS genre_name,
    COALESCE(mt.name,  'Unknown media type')            AS media_type,
    NULLIF(TRIM(t.composer), '')                        AS composer,
    ROUND(t.milliseconds / 1000.0, 1)                   AS duration_seconds,
    t.unit_price
FROM src.track t
LEFT JOIN src.album      al ON al.album_id      = t.album_id
LEFT JOIN src.artist     ar ON ar.artist_id     = al.artist_id
LEFT JOIN src.genre      g  ON g.genre_id       = t.genre_id
LEFT JOIN src.media_type mt ON mt.media_type_id = t.media_type_id;

DROP TABLE IF EXISTS stg.invoice_line CASCADE;
CREATE TABLE stg.invoice_line AS
SELECT
    il.invoice_line_id,
    il.invoice_id,
    i.customer_id,
    i.invoice_date::date                                AS invoice_date,
    il.track_id,
    il.unit_price,
    il.quantity,
    (il.unit_price * il.quantity)                       AS line_amount
FROM src.invoice_line il
JOIN src.invoice i ON i.invoice_id = il.invoice_id;

CREATE INDEX ON stg.invoice_line (invoice_date);
