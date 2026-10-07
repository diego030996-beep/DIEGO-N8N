"""Corre una operación de la auditoría contra el Postgres de prueba (base 'auditoria'), igual que n8n."""
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from sqlops import todas, leer  # noqa: E402

PSQL = ['psql', '-h', '/var/tmp/pgc', '-p', '5544', '-U', 'postgres', '-d', os.environ.get('DB', 'auditoria'), '-At', '-v', 'ON_ERROR_STOP=1']
DEF = json.load(open(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'n8n', 'defaults.json')))
SQL = todas()


def lit(v):
    return "'" + str(v).replace("'", "''") + "'"


def psql(q):
    r = subprocess.run(PSQL + ['-c', q], text=True, capture_output=True)
    if r.returncode:
        raise SystemExit('ERROR: ' + r.stderr)
    return r.stdout.strip()


def correr(op, p=None, ahora='2026-10-07 21:00', por='Auditora', rol='auditora'):
    p = dict(p or {}, _rol=rol)
    vals = ['', json.dumps(DEF), por, json.dumps(p), ahora]
    q = re.sub(r'\$(\d+)', lambda m: lit(vals[int(m.group(1)) - 1]), leer('esquema') + '\n' + SQL[op])
    r = subprocess.run(PSQL + ['-c', q], text=True, capture_output=True)
    if r.returncode:
        raise SystemExit(f'ERROR en {op}: {r.stderr}')
    i = r.stdout.rfind('{"ok"')
    return json.JSONDecoder().raw_decode(r.stdout[i:])[0] if i >= 0 else None


if __name__ == '__main__':
    print(json.dumps(correr(sys.argv[1], json.loads(sys.argv[2]) if len(sys.argv) > 2 else {}), ensure_ascii=False, indent=1))
