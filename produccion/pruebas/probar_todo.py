"""Prueba de punta a punta del módulo de producción contra el Postgres de prueba. Uso: python3 produccion/pruebas/probar_todo.py"""
import os
import re
import subprocess
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
subprocess.run([sys.executable, os.path.join(AQUI, 'datos_prueba.py')], check=True, capture_output=True)
from correr import correr  # noqa: E402
sys.path.insert(0, os.path.dirname(AQUI))
from sqlops import todas  # noqa: E402


def ok(c, msg):
    print(('OK   ' if c else 'FALLA') + ' ' + msg)
    if not c:
        sys.exit(1)


for op, q in todas().items():
    ok(not re.search(r"\$(?![1-5](?![0-9]))", q), f'sin "$" peligrosos en {op}')

d = correr('datos')
T = {t['clave']: t for t in d['tinacos']}
ok(set(T) >= {'TINACO', 'T1100BE', 'T1100BL', 'T450N'} and 'POLN' not in T, 'tinacos: los de la línea de tinacos, sin la materia prima')
ok(any(a['clave'] == 'POLN' for a in correr('buscar', {'q': 'polimero neg'})['articulos']), 'buscar materia prima en el inventario')
# receta del tinaco negro 1100: 22 kg de polímero negro + tapa + kit
ok(correr('receta', {'articulo_id': 16, 'comps': [{'componente_id': 50, 'cantidad': 22}, {'componente_id': 53, 'cantidad': 1}, {'componente_id': 54, 'cantidad': 1}]})['ok'], 'guardar receta')
t = {t['clave']: t for t in correr('datos')['tinacos']}['TINACO']
ok(t['costo'] == round(22 * 32.5 + 85 + 120, 2), f"costo de materiales = 22×32.5 + 85 + 120 = {t['costo']}")
# copiar a beige y blanco cambiando el polímero
correr('copiar', {'de': 16, 'a': [40], 'cambiar_de': '50', 'cambiar_a': '51'})
correr('copiar', {'de': 16, 'a': [41], 'cambiar_de': '50', 'cambiar_a': '52'})
t = {t['clave']: t for t in correr('datos')['tinacos']}
ok({c['clave'] for c in t['T1100BE']['receta']} == {'POLBE', 'TAPA1100', 'KITTIN'}, 'copiar receta al beige cambiando el polímero')
ok(any(c['clave'] == 'POLBL' and c['costo'] == 30 and c['fuente'] == 'última compra' for c in t['T1100BL']['receta']), 'sin último costo en Microsip: usa el precio de la última compra')
# capturar producción
r = correr('capturar', {'fecha': '2026-10-06', 'nota': '', 'lineas': [{'articulo_id': 16, 'cantidad': 10}, {'articulo_id': 40, 'cantidad': 3}, {'articulo_id': 42, 'cantidad': 2}]})
ok(r['registros'] == 2 and r['tinacos'] == 13 and r['sin_receta'] == ['42'], 'capturar: 10 negros + 3 beige; el de 450 no tiene receta y no se captura')
ok(any(n['clave'] == 'POLBE' and n['queda'] == 60 - 66 for n in r['negativos']), 'avisa que el polímero beige no alcanza (60 kg, usa 66)')
d = correr('datos')
C = {c['clave']: c for c in d['componentes']}
ok(C['POLN']['por_importar'] == 220 and C['POLN']['disponible'] == 400 - 220 and C['TAPA1100']['por_importar'] == 13, 'consumo pendiente de importar se descuenta de lo disponible')
ok(d['sin_exportar']['tinacos'] == 13, 'pendiente de exportar')
rg = correr('registros', {'desde': '2026-10-01', 'hasta': '2026-10-07'})['registros']
ok(len(rg) == 2 and any(x['clave'] == 'TINACO' and x['costo_unit'] == 920 and x['costo'] == 9200 for x in rg), 'registro con costo por tinaco')
# exportar: primero ver sin marcar, luego marcar
e = correr('exportar', {'desde': '2026-10-01', 'hasta': '2026-10-07', 'marcar': ''})
S = {x['clave']: x for x in e['salida']}; E = {x['clave']: x for x in e['entrada']}
ok(S['POLN']['u'] == 220 and S['POLN']['costo'] == 32.5 and S['TAPA1100']['u'] == 13 and E['TINACO']['u'] == 10 and E['TINACO']['costo'] == 920,
   'archivo de salida (materia prima) y de entrada (tinacos) con costo')
ok(e['marcados'] == 0 and correr('datos')['sin_exportar']['tinacos'] == 13, 'ver sin marcar no exporta')
e = correr('exportar', {'desde': '2026-10-01', 'hasta': '2026-10-07', 'marcar': 'si'})
ok(e['marcados'] == 2 and e['exporte_id'], 'exportar y marcar')
ok(correr('exportar', {'desde': '2026-10-01', 'hasta': '2026-10-07', 'marcar': 'si'})['registros'] == 0, 'lo exportado no vuelve a salir')
ok(len(correr('exportar', {'exporte_id': e['exporte_id']})['salida']) == 4, 'volver a bajar un exporte anterior')
ok(correr('borrar', {'id': rg[0]['id']})['ok'] is False, 'no se borra lo ya exportado')
d = correr('datos')
ok({c['clave']: c for c in d['componentes']}['POLN']['por_importar'] == 220 and len(d['sin_confirmar']) == 1, 'exportado pero sin importar: sigue descontando')
correr('importado', {'exporte_id': e['exporte_id']})
ok({c['clave']: c for c in correr('datos')['componentes']}['POLN']['por_importar'] == 0, 'confirmado que se importó: ya lo trae la existencia de Microsip')
# materia prima: entró 500 kg de negro el 02/10, se consumieron 220
m = {x['clave']: x for x in correr('materia', {'desde': '2026-10-01', 'hasta': '2026-10-07'})['filas']}
ok(m['POLN']['entro'] == 500 and m['POLN']['consumo'] == 220 and m['POLBL']['entro'] == 200, 'materia prima: lo que entró (Microsip) y lo que se consumió')
rs = correr('resumen', {'desde': '2026-10-01', 'hasta': '2026-10-07'})
ok(sum(s['tinacos'] for s in rs['semanas']) == 13 and rs['por_tinaco'][0]['clave'] == 'TINACO', 'resumen por semana y por tinaco')
correr('precio', {'articulo_id': 16, 'precio': '2700'})
ok({t['clave']: t for t in correr('datos')['tinacos']}['TINACO']['precio'] == 2700, 'precio de venta propio para la simulación')
correr('extras', {'lista': [{'concepto': 'Mano de obra quemador', 'monto': 60}, {'concepto': 'Gas', 'monto': 45, 'articulo_id': '16'}]})
ok(len(correr('datos')['extras']) == 2, 'gastos extra de la simulación')
r2 = correr('capturar', {'fecha': '2026-10-07', 'nota': '', 'lineas': [{'articulo_id': 41, 'cantidad': 1}]})
rid = [x for x in correr('registros', {})['registros'] if x['clave'] == 'T1100BL'][0]['id']
ok(correr('borrar', {'id': rid})['ok'], 'borrar una captura no exportada')
correr('config', {'general': {'almacenes': 'GENERAL'}})
ok(correr('datos')['cfg']['almacenes'] == 'GENERAL', 'configuración')
print('Todo bien.')
