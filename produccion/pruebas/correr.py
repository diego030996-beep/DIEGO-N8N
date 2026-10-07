"""Corre una operación de producción contra el Postgres de prueba, igual que n8n (una sola petición)."""
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from sqlops import todas  # noqa: E402

PSQL = ['psql', '-h', '/var/tmp/pgc', '-p', '5544', '-U', 'postgres', '-d', os.environ.get('DB', 'postgres'), '-At', '-v', 'ON_ERROR_STOP=1']
DEF = json.load(open(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'n8n', 'defaults.json')))
SQL = todas()


def lit(v):
    return "'" + str(v).replace("'", "''") + "'"


def correr(op, p=None, hoy='2026-10-07', base='', por='prueba'):
    vals = [base, json.dumps(DEF), por, json.dumps(p or {}), hoy]
    q = re.sub(r'\$(\d+)', lambda m: lit(vals[int(m.group(1)) - 1]), SQL[op])
    r = subprocess.run(PSQL + ['-c', q], text=True, capture_output=True)
    if r.returncode:
        raise SystemExit(f'ERROR en {op}: {r.stderr}')
    i = r.stdout.rfind('{"ok"')
    return json.JSONDecoder().raw_decode(r.stdout[i:])[0] if i >= 0 else None


if __name__ == '__main__':
    print(json.dumps(correr(sys.argv[1], json.loads(sys.argv[2]) if len(sys.argv) > 2 else {}), ensure_ascii=False, indent=1))
