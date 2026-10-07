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
ok(d['ok'] and d['mes'] is None and d['oc_total'] == 16, 'datos sin cálculo previo')
ok(sorted(x['linea'] for x in d['excluidos']) == ['Servicios (no son mercancía)', 'TINACOS Y CISTERNAS', 'Varios (artículo genérico)'],
   'avisa que tinacos, servicios y VARIOS no se toman en cuenta')
c = correr('calcular', {'mes': '2026-10-01'})
ok(c['productos'] == 21 and c['a'] + c['b'] + c['c'] == 21 and c['c'] >= 2, f"A/B/C: {c['a']} A, {c['b']} B, {c['c']} C (tinaco excluido)")
mm = {f['clave']: f for f in correr('reporte', {})['filas']}
f = mm['CEM25']
import math
z = {95: 1.65, 90: 1.28, 85: 1.04}[int(f['ns'])]
ok(f['minimo'] == math.ceil(z * f['sd'] * math.sqrt(f['entrega'] + f['revision']) - 1e-6) or abs(f['minimo'] - z * f['sd'] * math.sqrt(f['entrega'] + f['revision'])) < 1.01, 'stock de seguridad = Z × variación × √(entrega + revisión)')
ok(f['punto_reorden'] == math.ceil(f['vd'] * (f['entrega'] + f['revision']) - 1e-9) + f['minimo'], 'punto de reorden = venta diaria × (entrega + revisión) + mínimo')
ok(f['maximo'] == f['punto_reorden'] + math.ceil(f['vd'] * f['inventario'] - 1e-9), 'máximo = punto de reorden + venta diaria × días de inventario')
ok(all(x['minimo'] >= 1 and x['maximo'] >= x['minimo'] and x['maximo'] > x['punto_reorden'] and (x['rotacion'] == 'baja' or x['punto_reorden'] >= x['minimo']) for x in mm.values()), 'ningún mínimo en 0, máx ≥ mín y máx > punto de reorden')
ok(mm['BISAGRA']['rotacion'] == 'baja' and (mm['BISAGRA']['minimo'], mm['BISAGRA']['punto_reorden'], mm['BISAGRA']['maximo']) == (1, 0, 1), 'rota poco: tener 1 y pedir solo cuando se acabe (mín 1, reorden 0, máx 1)')
ok(mm['CEM25']['rotacion'] == 'alta', 'cemento rota mucho')
_ab = [x for x in mm.values() if x['pct'] is not None]
_t = sum(x['venta'] for x in _ab)
ok(all((x['clase'] == 'A') == ((x['pct_acum'] * _t - x['venta']) < 0.80 * _t + 0.01) for x in _ab), 'A = primer 80% de la venta')
ok(all(x['clase'] == 'C' for x in _ab if (x['pct_acum'] * _t - x['venta']) >= 0.95 * _t + 0.01), 'C = último 5% de la venta')
_p = {x['clave']: x for x in correr('planeador', {'proveedor_id': '14'})['filas']}
ok(_p['CEM25']['ult_venta'] is not None and _p['CEM25']['rec_fecha'] == '2026-09-22' and _p['CEM25']['rec_unidades'] == 360, 'renglón con última venta y última recepción')
ok(mm['MARTILLO']['alerta'] == 'sin proveedor', 'alerta sin proveedor')
ok('TINACO' not in mm, 'tinacos fuera del cálculo')
ok(mm['BROCHA4']['clase'] == 'C' and mm['BROCHA4']['minimo'] >= 1 and mm['BROCHA4']['maximo'] > mm['BROCHA4']['minimo'], 'C: vendido fuera de los 6 meses, mínimo 1 pieza')
n = {x['clave']: x for x in correr('planeador', {'proveedor_id': ''})['filas']}
ok(n['TALADRO']['clase'] == 'C' and n['TALADRO']['alerta'].startswith('nuevo'), 'artículo nuevo de este mes entra como C provisional')
p = correr('planeador', {'proveedor_id': '14'})
cem = {x['clave']: x for x in p['filas']}
ok(cem['CEM25']['pendiente'] == 100 and 'O0000077' in cem['CEM25']['folios'], 'pendiente por recibir de la OC abierta')
s = cem['CEM50']
ok(s['sugerido'] == (s['maximo'] - max(s['existencia'], 0) - s['pendiente'] if max(s['existencia'], 0) + s['pendiente'] <= s['punto_reorden'] else 0), 'sugerido = máx − existencia − por recibir al llegar al punto de reorden')
t = correr('planeador', {'todos': 'si'})['filas']
ok(len({x['proveedor_id'] for x in t}) > 2 and all(x['sugerido'] > 0 or max(x['existencia'], 0) + x['pendiente'] <= x['punto_reorden'] for x in t), 'vista de todos los productos: solo lo que hay que pedir, de todos los proveedores')
g = correr('guardar', {'proveedor_id': '14', 'proveedor': 'CEMEX', 'clase': 'A', 'folio': '', 'lineas': [
    {**{k: s[k] for k in ('articulo_id', 'clave', 'articulo', 'unidad', 'clase', 'existencia', 'pendiente', 'minimo', 'punto_reorden', 'maximo', 'sugerido')}, 'comprado': s['sugerido'] + 20, 'razon': 'promocion', 'nota': ''}]})
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
ok(L['CEM50']['costo'] == 168.0 and L['CEM50']['costo_fuente'] == 'último costo' and L['CEM50']['clave'] == 'CEM50', 'archivo para Microsip: clave y último costo de Microsip')
ok(d['falta_razon'] == 1, 'pide razón del renglón no planeado')
for m in ('2026-08-01', '2026-09-01'):
    x = correr('reconstruir', {'mes': m, 'solo_si_falta': 'si'}, hoy='2026-10-07')
    ok(x['ocs'] == (5 if m < '2026-09' else 8), 'reconstruir ' + m + f" ({x['renglones']} renglones, sin la OC de tinacos)")
x = correr('reconstruir', {'mes': '2026-08-01', 'solo_si_falta': 'si'}, hoy='2026-10-07')
ok(x['renglones'] == 13, 'reconstruir dos veces no duplica')
o = correr('ocs', {'desde': '2026-08-01', 'hasta': '2026-09-30'})
ok(len(o['ocs']) == 14 and all(bool(z['plan']) != z['excluida'] for z in o['ocs']), 'todas las OCs ligadas menos la de tinacos (marcada como excluida)')
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
l = correr('limpieza', {})
ok([x['clave'] for x in l['una_venta']] == ['BISAGRA'], 'detecta lo que se vendió una sola vez')
dup = [sorted(a['clave'] for a in g['articulos']) for g in l['duplicados']]
ok(['CINTAN', 'CINTAP'] in dup, 'cinta aislar negra Pretul / Nitto: posible duplicado de marca')
ok(not any('LLAVE38' in g for g in dup), 'llave 3/8 y 5/16 no son duplicado (cambia la medida)')
ok(correr('revision', {'articulo_id': 23, 'tipo': 'una_venta', 'decision': 'se_va', 'grupo': '', 'nota': ''})['ok'], 'marcar "ya no comprar"')
ok(correr('limpieza', {})['una_venta'] == [], 'ya no aparece por revisar')
ok(correr('calcular', {'mes': '2026-10-01'})['productos'] == 20, 'sale del cálculo')
correr('revision', {'articulo_id': 23, 'tipo': 'una_venta', 'decision': 'deshacer', 'grupo': '', 'nota': ''})
ok(correr('calcular', {'mes': '2026-10-01'})['productos'] == 21, 'deshacer lo regresa')
r = correr('registro', {'mes': '2026-08-01'})
ok(all(l['razon'] in ('igual', 'gerencia', 'no_documentado') for p in r['planes'] for l in p['lineas']), 'OCs anteriores: «Autorizó gerencia» por omisión')
ok(correr('revision', {'articulo_id': 3, 'tipo': 'lento', 'decision': 'se_va', 'grupo': '', 'nota': ''})['ok'], 'pausar un producto desde el planeador')
ok(not any(f['clave'] == 'MOR25' for f in correr('planeador', {'proveedor_id': '14'})['filas']), 'el pausado sale del planeador de inmediato')
ok([x['clave'] for x in correr('limpieza', {})['pausados']] == ['MOR25'], 'aparece en Pausados')
correr('reactivar', {'articulo_id': 3})
ok(any(f['clave'] == 'MOR25' for f in correr('planeador', {'proveedor_id': '14'})['filas']) and correr('limpieza', {})['pausados'] == [], 'Regresar lo trae de vuelta')
# ---- Conversiones, pedidos abiertos/parciales/atrasados, revisar datos, política, costos, duplicados ----
H = '2026-10-07'
correr('calcular', {'mes': '2026-10-01'})
P = lambda pid: {x['clave']: x for x in correr('planeador', {'proveedor_id': pid}, hoy=H)['filas']}
ok(not any(x['clave'] in ('FLETE', 'VARIOS') for x in correr('planeador', {'todos': 'si'}, hoy=H)['filas']), 'servicios y VARIOS no salen en el planeador')
c15 = P('15')['CLAVO25']
ok(c15['pendiente'] == 30, 'OC parcial: se cuenta lo que falta (50 pedidas − 20 recibidas)')
l16 = P('16')['LLAVE38']
ok(l16['atr_u'] == 5 and l16['pendiente'] == 0 and any('atrasada' in r for r in l16['revisar']), 'OC atrasada: no cuenta como por recibir y pide revisarla')
sg = correr('seguimiento', {}, hoy=H)
E = {o['folio']: o for o in sg['ocs']}
ok(E['O0000091']['estado'] == 'atrasada' and E['O0000090']['estado'] == 'parcial' and E['O0000090']['falta'] == 30, 'seguimiento: atrasada y parcial')
ok('O0000092' not in E and 'O0000093' not in E, 'recepción sin ligar y UNIDADES_A_REC de Microsip: no salen como atrasadas')
ok(not P('13')['FLEX5'].get('atr_u') and not P('10')['SIL300'].get('atr_u'), 'no salen como «atrasado» en el planeador')
ok(correr('oc_estado', {'docto_cm_id': '5091', 'estado': 'en_camino', 'nota': 'llega el lunes'})['ok'], 'confirmar que la OC atrasada sigue en camino')
ok(P('16')['LLAVE38']['pendiente'] == 5, 'confirmada en camino: ya cuenta como por recibir')
correr('oc_estado', {'docto_cm_id': '5091', 'estado': 'cancelada', 'nota': ''})
ok('O0000091' not in {o['folio'] for o in correr('seguimiento', {}, hoy=H)['ocs']} and P('16')['LLAVE38']['atr_u'] in (None, 0), 'OC cancelada: sale del seguimiento')
t = P('12')['TPLUS25']
ok(t['existencia'] == 2 and any('negativa' in r and 'BODEGA' in r for r in t['revisar']), 'existencia negativa: avisa en qué almacén')
ok(t['estado'] in ('critico', 'pedir') and t['costo'] == 122.5 and t['costo_fuente'] == 'último costo', 'estado y costo por renglón')
rs = correr('planeador', {'todos': 'si'}, hoy=H)['resumen']
ok(rs['iva'] == 16 and all('costo' in p and 'sin_costo' in p for p in rs['proveedores']) and any(p['costo'] > 0 for p in rs['proveedores']), 'resumen: costo estimado por proveedor e IVA')
eq = correr('equivalencias', {})
sug = {x['clave']: x for x in eq['sugeridas']}
ok(sug.get('CEM50TON', {}).get('base_clave') == 'CEM50' and sug['CEM50TON']['factor'] == 20, 'sugiere TONELADA = 20 sacos de 50 kg')
antes = P('14')['CEM50']['existencia']
correr('equivalencia', {'articulo_id': 32, 'base_id': 2, 'factor': 20, 'accion': 'confirmar', 'nota': ''})
ok(correr('equivalencias', {})['activas'][0]['clave'] == 'CEM50TON', 'confirmada: ya cuenta')
correr('equivalencia', {'articulo_id': 32, 'accion': 'quitar'})
ok(correr('equivalencias', {})['activas'] == [] and P('14')['CEM50']['existencia'] == antes, 'quitarla la regresa')
ok(correr('politica', {'articulo_id': 21, 'politica': 'bajo_pedido', 'minimo': '', 'nota': ''})['ok'], 'política: solo bajo pedido')
l = P('16')['LLAVE38']
ok(l['estado'] == 'bajo_pedido' and l['sugerido'] == 0, 'bajo pedido: no se sugiere compra')
correr('politica', {'articulo_id': 21, 'politica': 'pausar', 'minimo': '', 'nota': ''})
ok('LLAVE38' not in P('16') and [x['clave'] for x in correr('limpieza', {})['pausados']] == ['LLAVE38'], 'pausar resurtido: sale del planeador y aparece en Pausados')
correr('reactivar', {'articulo_id': 21})
ok('LLAVE38' in P('16'), 'Regresar quita la pausa')
correr('politica', {'articulo_id': 21, 'politica': 'minimo', 'minimo': '4', 'nota': ''})
correr('calcular', {'mes': '2026-10-01'})
ok(P('16')['LLAVE38']['minimo'] >= 4, 'mantener un mínimo de 4')
correr('politica', {'articulo_id': 21, 'politica': '', 'minimo': '', 'nota': ''})
correr('config', {'general': {'marcas': 'TRUPER PRETUL'}, 'proveedores': []})
ok(not any('CINTAN' in [a['clave'] for a in g['articulos']] for g in correr('limpieza', {})['duplicados']), 'duplicados: solo si lo que cambia está en la lista de marcas')
correr('config', {'general': {'marcas': 'TRUPER PRETUL NITTO'}, 'proveedores': []})
ok(any(sorted(a['clave'] for a in g['articulos']) == ['CINTAN', 'CINTAP'] for g in correr('limpieza', {})['duplicados']), 'duplicados: Pretul / Nitto con las dos marcas en la lista')
d = correr('datos', hoy=H)
ok(any('lt_medido' in p for p in d['proveedores']), 'días de entrega medidos por proveedor')

print('Todo bien.')

# n8n (algunas versiones) mete la consulta con String.replace(): "$'", "$&", "$`" y "$$" cambian el texto. No debe haber ninguno.
import re as _re
from sqlops import todas as _todas
for _op, _q in _todas().items():
    ok(not _re.search(r"\$(?![1-5](?![0-9]))", _q), f'sin "$" peligrosos en la consulta {_op}')
