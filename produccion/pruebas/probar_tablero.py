"""Pantalla principal y gas. Uso: python3 produccion/pruebas/probar_tablero.py
Caso: carga de gas el 01/10 (tanque lleno: punto de partida), 10 tinacos el 02/10 y 6 el 05/10, carga de $800 el 06/10
→ esos $800 se gastaron en 16 tinacos = $50 por tinaco. El 07/10 se hacen 4 más (gas estimado con la misma tasa: $200)."""
import os
import subprocess
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
subprocess.run([sys.executable, os.path.join(AQUI, 'datos_prueba.py')], check=True, capture_output=True)
from correr import correr  # noqa: E402


def ok(c, msg):
    print(('OK   ' if c else 'FALLA') + ' ' + msg)
    if not c:
        sys.exit(1)


correr('datos')
correr('receta', {'articulo_id': 16, 'comps': [{'componente_id': 50, 'cantidad': 22}, {'componente_id': 53, 'cantidad': 1}, {'componente_id': 54, 'cantidad': 1}]})
correr('gas', {'fecha': '2026-10-01', 'litros': '300', 'costo': '3000', 'nota': 'tanque lleno', 'borrar': ''})
correr('capturar', {'fecha': '2026-10-02', 'nota': '', 'lineas': [{'articulo_id': 16, 'cantidad': 10}]})
correr('capturar', {'fecha': '2026-10-05', 'nota': '', 'lineas': [{'articulo_id': 16, 'cantidad': 6}]})
correr('gas', {'fecha': '2026-10-06', 'litros': '80', 'costo': '800', 'nota': '', 'borrar': ''})
correr('capturar', {'fecha': '2026-10-07', 'nota': '', 'lineas': [{'articulo_id': 16, 'cantidad': 4}]})
correr('config', {'general': {'meta_diaria': '8'}})
t = correr('tablero', {'periodo': 'dia', 'fecha': '2026-10-07'})
ok(t['per']['piezas'] == 4 and t['meta_diaria'] == 8, 'hoy: 4 tinacos, meta 8')
ok(t['polimero']['kg'] == 88 and t['per']['materiales'] == 4 * 920, 'hoy: 88 kg de polímero y $3,680 de materiales')
ok(t['gas_tasa']['por_tinaco'] == 50 and t['gas_tasa']['litros_tinaco'] == 5, 'gas real: $800 ÷ 16 tinacos = $50 y 5 L por tinaco')
ok(t['per']['gas'] == 200 and t['per']['gas_estimado'] is True, 'hoy: $200 de gas (estimado: todavía no hay carga después)')
s = correr('tablero', {'periodo': 'semana', 'fecha': '2026-10-07'})
ok(s['desde'] == '2026-10-05' and s['per']['piezas'] == 10 and s['per']['gas'] == 6 * 50 + 4 * 50 and s['per']['gas_pagado'] == 800, 'semana: 10 tinacos, $500 de gas consumido, $800 pagado')
m = correr('tablero', {'periodo': 'mes', 'fecha': '2026-10-07'})
ok(m['per']['piezas'] == 20 and m['per']['gas'] == 1000 and m['per']['gas_pagado'] == 3800 and len(m['serie']) == 12, 'mes: 20 tinacos, $1,000 de gas consumido; la carga inicial es el punto de partida')
c = [x for x in m['gas_cargas'] if x['fecha'] == '2026-10-06'][0]
ok(c['piezas'] == 16 and c['por_tinaco'] == 50, 'cada carga dice para cuántos tinacos alcanzó')
ok(any(x['clave'] == 'POLN' and x['dias'] is not None for x in m['materia']), 'materia prima con días disponibles')
correr('extras', {'lista': [{'concepto': 'Gas', 'monto': 50}]})
ok(correr('tablero', {})['gas_ref'] == 50, 'referencia de gas de la simulación para comparar')
correr('gas', {'fecha': '2026-10-06', 'litros': '20', 'costo': '200', 'nota': 'otra carga el mismo día', 'borrar': ''})
t2 = correr('tablero', {'periodo': 'mes', 'fecha': '2026-10-07'})
ok(t2['gas_tasa']['por_tinaco'] == 62.5, 'dos cargas el mismo día cuentan juntas: $1,000 ÷ 16 = $62.50')
g = correr('gas', {'borrar': str(c['id'])})
ok(g['borrados'] == 1, 'borrar una carga')
print('Todo bien.')
