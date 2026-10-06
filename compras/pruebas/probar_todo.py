"""Prueba de punta a punta contra el Postgres de prueba (datos de pruebas/datos_prueba.py). Uso: python3 compras/pruebas/probar_todo.py"""
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from correr import correr, PSQL  # noqa: E402
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

def ok(c, msg):
    print(('OK   ' if c else 'FALLA') + ' ' + msg)
    if not c:
        sys.exit(1)

d = correr('datos')
ok(d['ok'] and d['mes'] is None and d['oc_total'] == 12, 'datos sin cálculo previo')
ok([x['linea'] for x in d['excluidos']] == ['TINACOS Y CISTERNAS'], 'avisa que la línea de tinacos no se toma en cuenta')
c = correr('calcular', {'mes': '2026-10-01'})
ok(c['productos'] == 16 and c['a'] == 3 and c['b'] == 12 and c['c'] == 1, 'A/B/C: 3 A, 12 B, 1 C (tinaco excluido)')
mm = {f['clave']: f for f in correr('reporte', {})['filas']}
f = mm['CEM25']
ok(f['minimo'] == -(-f['vd'] * (f['entrega'] + f['seguridad']) // 1) and f['maximo'] == f['minimo'] + -(-f['vd'] * f['inventario'] // 1), 'fórmula de mín/máx')
ok(all(x['minimo'] >= 1 and x['maximo'] > x['minimo'] for x in mm.values()), 'ningún mínimo en 0 y máximo > mínimo')
ok(mm['MARTILLO']['alerta'] == 'sin proveedor', 'alerta sin proveedor')
ok('TINACO' not in mm, 'tinacos fuera del cálculo')
ok(mm['BROCHA4']['clase'] == 'C' and mm['BROCHA4']['minimo'] >= 1 and mm['BROCHA4']['maximo'] > mm['BROCHA4']['minimo'], 'C: vendido fuera de los 6 meses, mínimo 1 pieza')
n = {x['clave']: x for x in correr('planeador', {'proveedor_id': ''})['filas']}
ok(n['TALADRO']['clase'] == 'C' and n['TALADRO']['alerta'].startswith('nuevo'), 'artículo nuevo de este mes entra como C provisional')
p = correr('planeador', {'proveedor_id': '14'})
cem = {x['clave']: x for x in p['filas']}
ok(cem['CEM25']['pendiente'] == 100 and 'O0000077' in cem['CEM25']['folios'], 'pendiente por recibir de la OC abierta')
s = cem['CEM50']
ok(s['sugerido'] == (s['maximo'] - max(s['existencia'], 0) - s['pendiente'] if max(s['existencia'], 0) + s['pendiente'] <= s['minimo'] else 0), 'sugerido')
g = correr('guardar', {'proveedor_id': '14', 'proveedor': 'CEMEX', 'clase': 'A', 'folio': '', 'lineas': [
    {**{k: s[k] for k in ('articulo_id', 'clave', 'articulo', 'unidad', 'clase', 'existencia', 'pendiente', 'minimo', 'maximo', 'sugerido')}, 'comprado': s['sugerido'] + 20, 'razon': 'promocion', 'nota': ''}]})
ok(g['lineas'] == 1, 'guardar plan')
dat = json.dumps({'DOCTO_CM_ID': 5099, 'TIPO_DOCTO': 'O', 'FOLIO': 'O0000078', 'FECHA': '2026-10-07', 'PROVEEDOR_ID': 14, 'ESTATUS': 'P'})
subprocess.run(PSQL + ['-c', f"INSERT INTO ms_raw (base,tabla,pk,fecha,datos) VALUES ('LOMAS AJUSCO','DOCTOS_CM','5099','2026-10-07','{dat}');"
               f"INSERT INTO ms_raw (base,tabla,pk,datos) VALUES ('LOMAS AJUSCO','DOCTOS_CM_DET','5099-0','{{\"DOCTO_CM_ID\":5099,\"ARTICULO_ID\":2,\"UNIDADES\":{s['sugerido'] + 20}}}'),"
               "('LOMAS AJUSCO','DOCTOS_CM_DET','5099-1','{\"DOCTO_CM_ID\":5099,\"ARTICULO_ID\":3,\"UNIDADES\":30}')"], check=True, capture_output=True)
d = correr('datos', hoy='2026-10-07')
r = correr('registro', {'mes': '2026-10-01'}, hoy='2026-10-07')
pl = [x for x in r['planes'] if x['origen'] == 'planeador'][0]
ok(pl['folio_oc'] == 'O0000078', 'la OC capturada en Microsip se liga sola al plan')
L = {x['clave']: x for x in pl['lineas']}
ok(L['CEM50']['oc_unidades'] == s['sugerido'] + 20 and L['MOR25']['fuente'].startswith('en la OC'), 'unidades de la OC y renglón no planeado')
ok(d['falta_razon'] == 1, 'pide razón del renglón no planeado')
for m in ('2026-08-01', '2026-09-01'):
    x = correr('reconstruir', {'mes': m, 'solo_si_falta': 'si'}, hoy='2026-10-07')
    ok(x['ocs'] == 5, 'reconstruir ' + m + f" ({x['renglones']} renglones, sin la OC de tinacos)")
x = correr('reconstruir', {'mes': '2026-08-01', 'solo_si_falta': 'si'}, hoy='2026-10-07')
ok(x['renglones'] == 13, 'reconstruir dos veces no duplica')
o = correr('ocs', {'desde': '2026-08-01', 'hasta': '2026-09-30'})
ok(len(o['ocs']) == 11 and all(bool(z['plan']) != z['excluida'] for z in o['ocs']), 'todas las OCs ligadas menos la de tinacos (marcada como excluida)')
ok(correr('registro', {'mes': '2026-08-01'})['oc_sin_plan'] == [], 'la OC de tinacos no sale como OC sin plan')
did = correr('registro', {'mes': '2026-08-01'})['planes'][0]['lineas'][0]['id']
ok(correr('razon', {'id': did, 'razon': 'no_documentado', 'nota': ''})['razon'] == 'no_documentado', 'guardar razón')
ok(correr('articulo', {'articulo_id': 2, 'proveedor_id': '14', 'clase': '', 'empaque': '10', 'minimo': '', 'maximo': '', 'excluir': 'false', 'nota': ''})['ok'], 'ajuste por artículo')
ok(correr('config', {'general': {'seg_a': '4'}, 'proveedores': [{'proveedor_id': '14', 'nombre': 'CEMEX', 'dias_entrega': 2, 'dia_a': 2, 'frec_b': 15, 'activo': True, 'nota': ''}]})['ok'], 'guardar configuración')
correr('calcular', {'mes': '2026-10-01'})
f = {x['clave']: x for x in correr('reporte', {})['filas']}['CEM50']
ok(f['entrega'] == 2 and f['seguridad'] == 4 and f['empaque'] == 10, 'el recálculo usa lo configurado en la página')
s = {x['clave']: x for x in correr('planeador', {'proveedor_id': '14'})['filas']}['CEM50']
ok(s['sugerido'] % 10 == 0, 'sugerido redondeado al empaque')
print('Todo bien.')

# n8n (algunas versiones) mete la consulta con String.replace(): "$'", "$&", "$`" y "$$" cambian el texto. No debe haber ninguno.
import re as _re
from sqlops import todas as _todas
for _op, _q in _todas().items():
    ok(not _re.search(r"\$(?![1-5](?![0-9]))", _q), f'sin "$" peligrosos en la consulta {_op}')
