"""Mete los cambios de este repo en el flujo «Sistema de Control DISACAM - Ventas web» de n8n.

Uso:
  python3 ventas_web/armar_flujo.py                      # actualiza ventas_web/n8n/Ventas web.json (sin llaves)
  python3 ventas_web/armar_flujo.py ENTRADA.json SALIDA.json   # toma otro archivo (ej. el que bajaste de n8n) y escribe el listo para importar

Se puede correr las veces que sea: cada cambio va entre marcas y se reemplaza, no se duplica.
Cambios:
  V8.65 · Sugerir qué chats unir (sql/unir_sugerencias.sql + js/unir_sugerencias.js)
Al guardar dentro del repo, los tokens de bots de Telegram se cambian por __TOKEN_TELEGRAM_n__ (no se suben llaves a GitHub).
"""
import json
import os
import re
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(AQUI)
DEF = os.path.join(AQUI, 'n8n', 'Ventas web.json')
VERSION = 'V8.65'

SQL_INI, SQL_FIN = '-- >>> V8.65 unir sugerencias (ventas_web/sql/unir_sugerencias.sql)', '-- <<< V8.65 unir sugerencias'
JS_INI, JS_FIN = '// >>> V8.65 unir sugerencias (ventas_web/js/unir_sugerencias.js)', '// <<< V8.65 unir sugerencias'
DESPACHO_VIEJO = "ELSIF acc IN ('wch_unir', 'wch_desunir', 'wch_unir_cand') THEN\n    RETURN wch_unir_fn(acc, u, p);"
DESPACHO_NUEVO = "ELSIF acc IN ('wch_unir', 'wch_desunir', 'wch_unir_cand', 'wch_unir_sug', 'wch_unir_descartar') THEN\n    RETURN wch_unir_fn2(acc, u, p);"
TOKEN = re.compile(r'(?<![0-9])\d{8,10}:AA[A-Za-z0-9_-]{30,}')


def leer(*ruta):
    with open(os.path.join(AQUI, *ruta), encoding='utf-8') as f:
        return f.read().strip()


def bloque(texto, ini, fin, nuevo, antes_de=None):
    """Quita el bloque viejo (si existe) y pone el nuevo al final o antes de la última aparición de `antes_de`."""
    texto = re.sub(re.escape(ini) + r'.*?' + re.escape(fin) + r'\n?', '', texto, flags=re.S)
    b = ini + '\n' + nuevo + '\n' + fin + '\n'
    if antes_de is None:
        return texto.rstrip('\n') + '\n\n' + b
    i = texto.rfind(antes_de)
    if i < 0:
        raise SystemExit(f'No encontré «{antes_de}» para insertar el bloque')
    return texto[:i] + b + texto[i:]


def nodo(flujo, nombre):
    for n in flujo['nodes']:
        if n['name'] == nombre:
            return n
    raise SystemExit(f'No encontré el nodo «{nombre}»')


def armar(flujo):
    # 1) base de datos: funciones nuevas al final de «Crear tablas y funciones» y las dos acciones nuevas en vw_api_wch
    p = nodo(flujo, 'Crear tablas y funciones')['parameters']
    q = p['query']
    if DESPACHO_NUEVO not in q:
        if q.count(DESPACHO_VIEJO) != 1:
            raise SystemExit('No encontré (una sola vez) dónde vw_api_wch manda a wch_unir_fn')
        q = q.replace(DESPACHO_VIEJO, DESPACHO_NUEVO)
    p['query'] = bloque(q, SQL_INI, SQL_FIN, leer('sql', 'unir_sugerencias.sql'))
    # 2) cada 15 min se recalculan las sugerencias (si falla no detiene los avisos)
    p = nodo(flujo, 'Revisar cola y avisos de venta')['parameters']
    if 'wch_unir_sug_cron()' not in p['query']:
        q = p['query'].rstrip().rstrip(';')
        p['query'] = q + ', wch_unir_sug_cron() AS unir_sug;'
    # 3) página: el código va al final del script principal
    p = nodo(flujo, 'Mostrar página')['parameters']
    p['responseBody'] = bloque(p['responseBody'], JS_INI, JS_FIN, leer('js', 'unir_sugerencias.js'), antes_de='</script>')
    flujo['name'] = re.sub(r'\s*V\d+\.\d+\s*$', '', flujo['name']) + ' ' + VERSION
    return flujo


def sin_llaves(flujo):
    vistos = {}

    def cambia(m):
        vistos.setdefault(m.group(), '__TOKEN_TELEGRAM_%d__' % (len(vistos) + 1))
        return vistos[m.group()]
    s = TOKEN.sub(cambia, json.dumps(flujo, ensure_ascii=False))
    return json.loads(s), len(vistos)


def main():
    entrada = sys.argv[1] if len(sys.argv) > 1 else DEF
    salida = sys.argv[2] if len(sys.argv) > 2 else DEF
    with open(entrada, encoding='utf-8') as f:
        flujo = armar(json.load(f))
    dentro = os.path.abspath(salida).startswith(REPO + os.sep)
    if dentro:
        flujo, n = sin_llaves(flujo)
        if n:
            print(f'{n} token(s) de Telegram cambiados por __TOKEN_TELEGRAM_n__ (ponlos en n8n al importar)')
    with open(salida, 'w', encoding='utf-8') as f:
        json.dump(flujo, f, ensure_ascii=False, indent=2)
        f.write('\n')
    print('Listo:', salida, '·', flujo['name'])


if __name__ == '__main__':
    main()
