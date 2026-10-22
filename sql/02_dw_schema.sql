-- =============================================================================
-- 02_dw_schema.sql  |  Modelo dimensional (esquema en estrella) en el esquema `dw`
-- Grano de la tabla de hechos: 1 fila por línea de factura (invoice_line).
-- Las tablas se crean solo si no existen: la carga es incremental (UPSERT).
-- =============================================================================
CREATE SCHEMA IF NOT EXISTS dw;

CREATE TABLE IF NOT EXISTS dw.dim_date (
    date_key     INT PRIMARY KEY,            -- yyyymmdd
    full_date    DATE NOT NULL UNIQUE,
    year         INT  NOT NULL,
    quarter      INT  NOT NULL,
    month        INT  NOT NULL,
    month_name   TEXT NOT NULL,
    year_month   TEXT NOT NULL,              -- 'YYYY-MM'
    week_of_year INT  NOT NULL,
    day_of_week  INT  NOT NULL,              -- 1 = lunes
    day_name     TEXT NOT NULL,
    is_weekend   BOOLEAN NOT NULL
);

CREATE TABLE IF NOT EXISTS dw.dim_employee (
    employee_key SERIAL PRIMARY KEY,
    employee_id  INT  NOT NULL UNIQUE,       -- clave natural
    full_name    TEXT NOT NULL,
    title        TEXT,
    hire_date    DATE,
    manager_name TEXT,
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS dw.dim_customer (
    customer_key SERIAL PRIMARY KEY,
    customer_id  INT  NOT NULL UNIQUE,
    full_name    TEXT NOT NULL,
    company      TEXT,
    city         TEXT,
    state        TEXT,
    country      TEXT NOT NULL,
    email        TEXT,
    employee_key INT REFERENCES dw.dim_employee (employee_key),  -- ejecutivo de soporte
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS dw.dim_track (
    track_key        SERIAL PRIMARY KEY,
    track_id         INT  NOT NULL UNIQUE,
    track_name       TEXT NOT NULL,
    album_title      TEXT NOT NULL,
    artist_name      TEXT NOT NULL,
    genre_name       TEXT NOT NULL,
    media_type       TEXT NOT NULL,
    composer         TEXT,
    duration_seconds NUMERIC(10,1),
    list_price       NUMERIC(10,2),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS dw.fact_sales (
    sales_key       BIGSERIAL PRIMARY KEY,
    invoice_line_id INT NOT NULL UNIQUE,      -- clave natural (permite UPSERT)
    invoice_id      INT NOT NULL,
    date_key        INT NOT NULL REFERENCES dw.dim_date (date_key),
    customer_key    INT NOT NULL REFERENCES dw.dim_customer (customer_key),
    track_key       INT NOT NULL REFERENCES dw.dim_track (track_key),
    employee_key    INT REFERENCES dw.dim_employee (employee_key),
    quantity        INT NOT NULL CHECK (quantity > 0),
    unit_price      NUMERIC(10,2) NOT NULL CHECK (unit_price >= 0),
    line_amount     NUMERIC(12,2) NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_fact_sales_date     ON dw.fact_sales (date_key);
CREATE INDEX IF NOT EXISTS ix_fact_sales_customer ON dw.fact_sales (customer_key);
CREATE INDEX IF NOT EXISTS ix_fact_sales_track    ON dw.fact_sales (track_key);

-- Bitácora de ejecuciones y resultados de calidad de datos
CREATE TABLE IF NOT EXISTS dw.etl_run_log (
    run_id      BIGSERIAL PRIMARY KEY,
    step        TEXT NOT NULL,
    started_at  TIMESTAMPTZ NOT NULL,
    seconds     NUMERIC(10,3) NOT NULL,
    status      TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS dw.dq_check_result (
    check_id    BIGSERIAL PRIMARY KEY,
    run_ts      TIMESTAMPTZ NOT NULL DEFAULT now(),
    check_name  TEXT NOT NULL,
    status      TEXT NOT NULL CHECK (status IN ('PASS','FAIL')),
    detail      TEXT
);
