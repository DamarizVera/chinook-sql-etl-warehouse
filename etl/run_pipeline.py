#!/usr/bin/env python3
"""Orquestador del pipeline ETL (solo librería estándar + psql).

Uso:
    python3 etl/run_pipeline.py --db chinook_dw [--host localhost --user dama]

Pasos: staging -> esquema DW -> carga -> calidad de datos -> marts -> export CSV.
Cada paso se registra en dw.etl_run_log. Si algún control de calidad falla,
el pipeline termina con código 1 (no se exportan reportes).
"""
import argparse
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STEPS = [
    ("staging", "sql/01_staging.sql"),
    ("dw_schema", "sql/02_dw_schema.sql"),
    ("load_dw", "sql/03_load_dw.sql"),
    ("data_quality", "sql/04_data_quality.sql"),
    ("marts", "sql/05_marts.sql"),
]
EXPORTS = [
    "v_monthly_revenue", "v_customer_rfm", "v_genre_revenue", "v_artist_pareto",
    "v_cohort_retention", "v_rep_performance", "v_country_revenue",
]


def psql(args, cmd, capture=False):
    base = ["psql", "-X", "-q", "-v", "ON_ERROR_STOP=1", "-d", args.db]
    if args.host:
        base += ["-h", args.host]
    if args.user:
        base += ["-U", args.user]
    return subprocess.run(base + cmd, check=False, text=True, capture_output=capture)


def log(args, step, status, secs, msg=""):
    psql(args, ["-c",
        f"INSERT INTO dw.etl_run_log(step,started_at,seconds,status) "
        f"VALUES ('{step}', now() - interval '{secs:.3f} seconds', {secs:.3f}, '{status}')"])


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--db", default="chinook_dw")
    p.add_argument("--host", default=None)
    p.add_argument("--user", default=None)
    args = p.parse_args()

    for name, rel in STEPS:
        t0 = time.time()
        r = psql(args, ["-f", str(ROOT / rel)], capture=True)
        secs = time.time() - t0
        if r.returncode != 0:
            print(f"[FAIL] {name}: {r.stderr.strip()}")
            if name != "staging":
                log(args, name, "FAIL", secs, r.stderr)
            sys.exit(1)
        print(f"[ OK ] {name:<13} {secs:6.2f}s")
        if name == "data_quality":
            print(r.stdout.strip())
            if "FAIL" in r.stdout:
                log(args, name, "FAIL", secs, "controles de calidad fallidos")
                print("Controles de calidad fallidos: pipeline detenido.")
                sys.exit(1)
        if name != "staging":
            log(args, name, "OK", secs)

    out = ROOT / "reports"
    out.mkdir(exist_ok=True)
    for v in EXPORTS:
        r = psql(args, ["-c", f"\\copy (SELECT * FROM mart.{v}) TO '{out / (v + '.csv')}' CSV HEADER"],
                 capture=True)
        if r.returncode != 0:
            print(f"[FAIL] export {v}: {r.stderr.strip()}")
            sys.exit(1)
    print(f"[ OK ] {len(EXPORTS)} reportes exportados a reports/")


if __name__ == "__main__":
    main()
