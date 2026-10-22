-- =============================================================================
-- 04_data_quality.sql  |  Controles de calidad y conciliación fuente vs. DW
-- Cada control inserta una fila PASS/FAIL en dw.dq_check_result.
-- El orquestador (etl/run_pipeline.py) falla si existe algún FAIL en esta corrida.
-- =============================================================================
CREATE TEMP TABLE _run AS SELECT now() AS run_ts;

-- 1) Conciliación de filas: líneas de factura en la fuente vs. hechos en el DW
INSERT INTO dw.dq_check_result (run_ts, check_name, status, detail)
SELECT r.run_ts, 'reconciliacion_filas_fact_vs_fuente',
       CASE WHEN s.n = f.n THEN 'PASS' ELSE 'FAIL' END,
       'fuente=' || s.n || ' | dw=' || f.n
FROM _run r,
     (SELECT COUNT(*) n FROM src.invoice_line) s,
     (SELECT COUNT(*) n FROM dw.fact_sales)    f;

-- 2) Conciliación de ingresos: total de facturas (fuente) vs. suma de líneas (DW)
INSERT INTO dw.dq_check_result (run_ts, check_name, status, detail)
SELECT r.run_ts, 'reconciliacion_ingresos_total',
       CASE WHEN ABS(s.total - f.total) < 0.01 THEN 'PASS' ELSE 'FAIL' END,
       'fuente=' || s.total || ' | dw=' || f.total
FROM _run r,
     (SELECT SUM(total) total FROM src.invoice)        s,
     (SELECT SUM(line_amount) total FROM dw.fact_sales) f;

-- 3) Integridad referencial: hechos sin dimensión asociada
INSERT INTO dw.dq_check_result (run_ts, check_name, status, detail)
SELECT r.run_ts, 'hechos_sin_dimension',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       'filas huérfanas=' || COUNT(*)
FROM _run r, dw.fact_sales f
LEFT JOIN dw.dim_customer c ON c.customer_key = f.customer_key
LEFT JOIN dw.dim_track    t ON t.track_key    = f.track_key
LEFT JOIN dw.dim_date     d ON d.date_key     = f.date_key
WHERE c.customer_key IS NULL OR t.track_key IS NULL OR d.date_key IS NULL
GROUP BY r.run_ts
UNION ALL
SELECT r.run_ts, 'hechos_sin_dimension', 'PASS', 'filas huérfanas=0'
FROM _run r
WHERE NOT EXISTS (SELECT 1 FROM dw.fact_sales f
                  LEFT JOIN dw.dim_customer c ON c.customer_key = f.customer_key
                  LEFT JOIN dw.dim_track t ON t.track_key = f.track_key
                  LEFT JOIN dw.dim_date d ON d.date_key = f.date_key
                  WHERE c.customer_key IS NULL OR t.track_key IS NULL OR d.date_key IS NULL);

-- 4) Importes coherentes: line_amount = quantity * unit_price y sin valores negativos
INSERT INTO dw.dq_check_result (run_ts, check_name, status, detail)
SELECT r.run_ts, 'importes_consistentes',
       CASE WHEN COUNT(*) FILTER (WHERE f.line_amount <> f.quantity * f.unit_price
                                     OR f.line_amount < 0) = 0 THEN 'PASS' ELSE 'FAIL' END,
       'filas con error=' || COUNT(*) FILTER (WHERE f.line_amount <> f.quantity * f.unit_price
                                                 OR f.line_amount < 0)
FROM _run r, dw.fact_sales f
GROUP BY r.run_ts;

-- 5) Unicidad de claves naturales en las dimensiones
INSERT INTO dw.dq_check_result (run_ts, check_name, status, detail)
SELECT r.run_ts, 'claves_naturales_unicas',
       CASE WHEN d.dups = 0 THEN 'PASS' ELSE 'FAIL' END,
       'duplicados=' || d.dups
FROM _run r,
     (SELECT (SELECT COUNT(*) - COUNT(DISTINCT customer_id) FROM dw.dim_customer)
           + (SELECT COUNT(*) - COUNT(DISTINCT track_id)    FROM dw.dim_track)
           + (SELECT COUNT(*) - COUNT(DISTINCT employee_id) FROM dw.dim_employee) AS dups) d;

-- 6) Campos obligatorios sin nulos en las dimensiones
INSERT INTO dw.dq_check_result (run_ts, check_name, status, detail)
SELECT r.run_ts, 'campos_obligatorios_sin_nulos',
       CASE WHEN n.nulls = 0 THEN 'PASS' ELSE 'FAIL' END,
       'nulos=' || n.nulls
FROM _run r,
     (SELECT (SELECT COUNT(*) FROM dw.dim_customer WHERE full_name IS NULL OR country IS NULL)
           + (SELECT COUNT(*) FROM dw.dim_track    WHERE track_name IS NULL OR genre_name IS NULL)
           + (SELECT COUNT(*) FROM dw.dim_employee WHERE full_name IS NULL) AS nulls) n;

-- 7) Cobertura temporal: todas las fechas de venta existen en dim_date
INSERT INTO dw.dq_check_result (run_ts, check_name, status, detail)
SELECT r.run_ts, 'fechas_dentro_de_dim_date',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       'facturas fuera de rango=' || COUNT(*)
FROM _run r, src.invoice i
WHERE i.invoice_date::date NOT IN (SELECT full_date FROM dw.dim_date)
GROUP BY r.run_ts
UNION ALL
SELECT r.run_ts, 'fechas_dentro_de_dim_date', 'PASS', 'facturas fuera de rango=0'
FROM _run r
WHERE NOT EXISTS (SELECT 1 FROM src.invoice i
                  WHERE i.invoice_date::date NOT IN (SELECT full_date FROM dw.dim_date));

SELECT check_name, status, detail
FROM dw.dq_check_result
WHERE run_ts = (SELECT run_ts FROM _run)
ORDER BY check_id;
