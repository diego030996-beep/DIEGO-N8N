"""Corre una operación del planeador contra el Postgres de prueba, igual que n8n (una sola petición con todas las sentencias)."""
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from sqlops import todas  # noqa: E402

DB = os.environ.get('DB', 'postgres')
PSQL = ['psql', '-h', '/var/tmp/pgc', '-p', '5544', '-U', 'postgres', '-d', DB, '-At', '-v', 'ON_ERROR_STOP=1']
DEF = json.load(open(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'n8n', 'defaults.json')))
SQL = todas()


def lit(v):
    return "'" + str(v).replace("'", "''") + "'"


def correr(op, p=None, hoy='2026-10-06', base='', por='prueba'):
    vals = [base, json.dumps(DEF), por, json.dumps(p or {}), hoy]
    q = re.sub(r'\$(\d+)', lambda m: lit(vals[int(m.group(1)) - 1]), SQL[op])
    r = subprocess.run(PSQL + ['-c', q], text=True, capture_output=True)
    if r.returncode:
        raise SystemExit(f'ERROR en {op}: {r.stderr}')
    i = r.stdout.rfind('{"ok"')
    out = json.loads(r.stdout[i:].split('\nINSERT')[0].split('\nUPDATE')[0]) if i >= 0 else None
    if out and 'cols' in out:   # el reporte llega compacto: filas como listas
        per = out.get('periodos') or {}
        out['filas'] = [dict(zip(out['cols'], f)) for f in out['filas']]
        for f in out['filas']:
            pe = per.get('C' if f['clase'] == 'C' else 'AB') or {}
            f.update(ini=pe.get('ini'), fin=pe.get('fin'), dias=pe.get('dias'))
    return out


if __name__ == '__main__':
    op = sys.argv[1]
    p = json.loads(sys.argv[2]) if len(sys.argv) > 2 else {}
    print(json.dumps(correr(op, p, *(sys.argv[3:4] or ['2026-10-06'])), ensure_ascii=False, indent=1)[:6000])
