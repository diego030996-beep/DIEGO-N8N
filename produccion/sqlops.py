"""Arma el SQL final de cada operación del módulo de producción: expande /*CTX*/ e /*INV*/ (igual que el planeador de compras)."""
import os
import re

DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'sql')
OPS = ['datos', 'buscar', 'receta', 'copiar', 'capturar', 'registros', 'borrar', 'exportar', 'importado', 'materia', 'resumen', 'precio', 'extras', 'config', 'contar', 'auditoria', 'merma', 'folio_ms']


def leer(nombre):
    with open(os.path.join(DIR, nombre + '.sql'), encoding='utf-8') as f:
        return f.read().strip()


def expandir(s):
    for k, f in {'/*CTX*/': '_ctx', '/*INV*/': '_inv', '/*MOV*/': '_mov'}.items():
        s = s.replace(k, leer(f))
    return s


def todas():
    out = {}
    for op in OPS:
        s = expandir(leer(op))
        s = '\n'.join(l for l in (re.sub(r'\s+--.*$', '', x) if not x.lstrip().startswith('--') else '' for x in s.split('\n')) if l.strip())
        out[op] = 'SET LOCAL jit = off;\n' + s
    return out


if __name__ == '__main__':
    for k, v in todas().items():
        print(k, len(v))
