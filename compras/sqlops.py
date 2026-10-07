"""Arma el SQL final de cada operación del planeador de compras: expande los fragmentos /*CTX*/, /*OC*/, etc."""
import os
import re

DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'sql')
OPS = ['datos', 'planeador', 'guardar', 'razon', 'folio', 'registro', 'reconstruir', 'calcular', 'ocs', 'reporte', 'buscar',
       'articulo', 'config', 'limpieza', 'revision', 'gerencia', 'reactivar', 'seguimiento', 'oc_estado', 'politica', 'equivalencias', 'equivalencia', 'oc_articulo', 'proveedor_art', 'proveedor_estado', 'politica_varios', 'copia']


def leer(nombre):
    with open(os.path.join(DIR, nombre + '.sql'), encoding='utf-8') as f:
        return f.read().strip()


def sug(m):
    e, p, mn, mx, emp = [x.strip() for x in m.group(1).split(',')]
    q = f'coalesce(nullif({emp}, 0), 1)'
    return (f"CASE WHEN {mn} IS NULL THEN NULL "
            f"WHEN cfg.regla = 'hasta_maximo' OR greatest({e}, 0) + coalesce({p}, 0) <= {mn} "
            f"THEN ceil(greatest({mx} - greatest({e}, 0) - coalesce({p}, 0), 0) / {q}) * {q} ELSE 0 END")


def calculo_solo_si_falta():
    s = leer('calcular')
    s = s[s.index('/*ESQUEMA*/') + len('/*ESQUEMA*/'):s.index('-- @fin_calculo')]
    return s.strip()


def expandir(s, nivel=0):
    if nivel > 5:
        raise ValueError('macros anidadas de más')
    rep = {
        '/*ESQUEMA*/': lambda: leer('esquema'),
        '/*CTX*/': lambda: leer('_ctx'),
        '/*OC*/': lambda: leer('_oc'),
        '/*OCD*/': lambda: leer('_ocd'),
        '/*EXI*/': lambda: leer('_exi'),
        '/*EXCL*/': lambda: leer('_eqv') + ',\n' + leer('_excl'),
        '/*EXCLSOLO*/': lambda: leer('_excl'),
        '/*EQV*/': lambda: leer('_eqv'),
        '/*LT*/': lambda: leer('_lt'),
        '/*LIGAR*/': lambda: leer('_ligar'),
        '/*CALCULAR_SOLO_SI_FALTA*/': calculo_solo_si_falta,
    }
    for k, f in rep.items():
        if k in s:
            s = s.replace(k, f())
    s = re.sub(r'/\*SUG\(([^)]*)\)\*/', sug, s)
    if '/*' in s and re.search(r'/\*[A-Z_]+(\(|\*/)', s):
        return expandir(s, nivel + 1)
    return s


def todas():
    out = {}
    for op in OPS:
        s = expandir(leer(op))
        # sin comentarios de línea para que la consulta pese menos
        s = '\n'.join(l for l in (re.sub(r'\s+--.*$', '', x) if not x.lstrip().startswith('--') else '' for x in s.split('\n')) if l.strip())
        # sin compilación JIT: en un servidor chico tarda más compilar que ejecutar (solo para esta consulta)
        out[op] = 'SET LOCAL jit = off;\n' + s
    return out


if __name__ == '__main__':
    for k, v in todas().items():
        print(k, len(v))
