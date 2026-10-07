"""Auditoría de polímero y merma, de punta a punta. Uso: python3 produccion/pruebas/probar_auditoria.py
Caso: pesaje inicial 400 kg (01/10) → entran 500 kg (02/10) → 10 tinacos de 22 kg que pesaron 23 kg (06/10) → se pesan 640 kg (07/10).
Debía haber 400 + 500 − 220 = 680: faltan 40 kg → fuera de tolerancia, se vuelve a pesar: 645 → faltan 35 (10 por tinacos más pesados, 25 de merma)."""
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
a = correr('auditoria')
ok([p['clave'] for p in a['polimeros']] == ['POLN'], 'se audita el polímero que está en alguna receta')
c0 = correr('contar', {'articulo_id': 50, 'fecha': '2026-10-01', 'kg': '400'})
ok(c0['estado'] == 'inicial' and c0['teorico'] is None, 'primer pesaje: punto de partida')
correr('capturar', {'fecha': '2026-10-06', 'nota': '', 'lineas': [{'articulo_id': 16, 'cantidad': 10, 'peso_real': '23'}]})
c1 = correr('contar', {'articulo_id': 50, 'fecha': '2026-10-07', 'kg': '640'})
ok(c1['teorico'] == 680 and c1['dif'] == -40 and c1['estado'] == 'revisar' and c1['dinero'] == -1300,
   f"debía haber 400 + 500 − 220 = 680; se pesaron 640: faltan 40 kg ($1,300) → volver a pesar ({c1['estado']})")
ok(c1['exceso'] == 10, 'los tinacos pesaron 1 kg más que la receta: 10 kg se fueron de más')
d = correr('datos')
ok(d['alertas']['revisar'] == 1 and 'POLIMERO NEGRO' in d['alertas']['polimeros'], 'alerta: volver a pesar el polímero negro')
c2 = correr('contar', {'articulo_id': 50, 'fecha': '2026-10-07', 'kg': '645', 'reconteo_de': str(c1['id'])})
ok(c2['estado'] == 'confirmado' and c2['dif'] == -35 and c2['reemplazo'] == 1, 'se volvió a pesar: 645, confirmado (faltan 35)')
ok(correr('datos')['alertas']['revisar'] == 0, 'ya no hay alerta')
a = correr('auditoria')['polimeros'][0]
ult = a['conteos'][0]
ok(ult['merma'] == 25 and ult['exceso'] == 10 and a['perdida']['kg'] == 35 and a['perdida']['dinero'] == 1137.5,
   'de los 35 kg: 10 por tinacos más pesados y 25 de merma; $1,137.50 perdidos')
ok(a['teorico_hoy'] == 645 and a['ult_kg'] == 645, 'lo que debe haber hoy parte del último pesaje')
ok(any(m['tipo'] == 'entrada' and m['kg'] == 500 for m in a['movs']) and any(m['tipo'] == 'consumo' and m['kg'] == -220 for m in a['movs']), 'trazabilidad: entradas y consumo día por día')
ok(any(c['estado'] == 'reemplazado' for c in a['conteos']), 'el pesaje reemplazado se ve (trazabilidad) pero no suma a la pérdida')
C = {c['clave']: c for c in correr('datos')['componentes']}
ok(C['POLN']['por_importar'] == 220 + 35, 'disponible = Microsip − consumo sin importar − merma sin ajustar')
m = correr('merma', {'marcar': ''})
ok(m['salida'] == [{'clave': 'POLN', 'nombre': 'POLIMERO NEGRO', 'unidad': 'Kilogramo', 'u': 35, 'costo': 32.5}] and m['marcados'] == 0, 'ajuste por merma: salida de 35 kg de polímero negro')
m = correr('merma', {'marcar': 'si'})
ok(m['marcados'] == 1 and correr('auditoria')['pendiente_merma']['conteos'] == 0, 'ajuste marcado: ya no está pendiente')
ok(len(correr('merma', {'exporte_id': str(m['exporte_id'])})['salida']) == 1, 'volver a bajar el ajuste')
correr('importado', {'exporte_id': m['exporte_id']})
C = {c['clave']: c for c in correr('datos')['componentes']}
ok(C['POLN']['por_importar'] == 220, 'ajuste importado en Microsip: ya no se descuenta aparte')
c3 = correr('contar', {'articulo_id': 50, 'fecha': '2026-10-07', 'kg': '643'})
ok(c3['estado'] == 'ok' and c3['dif'] == -2, 'diferencia chica (dentro de tolerancia): queda bien sin volver a pesar')
# el mismo día: se produce DESPUÉS del último pesaje y se vuelve a pesar → cuenta esa producción
correr('capturar', {'fecha': '2026-10-07', 'nota': '', 'lineas': [{'articulo_id': 16, 'cantidad': 5}]})
c4 = correr('contar', {'articulo_id': 50, 'fecha': '2026-10-07', 'kg': '533'})
ok(c4['teorico'] == 643 - 110 and c4['estado'] == 'ok', f"mismo día: lo producido después del pesaje anterior sí cuenta (debía haber {c4['teorico']})")
a = correr('auditoria')['polimeros'][0]
ok(a['teorico_hoy'] == 533 and a['consumo'] == 0, 'después del último pesaje no hay más consumo')
# predicción: varios pesajes con distinta producción; faltan 0.5 kg por tinaco + 3 kg fijos
correr('merma', {'marcar': 'si'})   # se ajusta lo de antes: la estadística empieza de cero
correr('config', {'general': {'tolerancia_kg': '20'}})
base = 533
for i, pz in enumerate([2, 5, 3, 6]):
    f = '2026-10-%02d' % (8 + i)
    correr('capturar', {'fecha': f, 'nota': '', 'lineas': [{'articulo_id': 16, 'cantidad': pz}]})
    base = base - 22 * pz - (0.5 * pz + 3)
    correr('contar', {'articulo_id': 50, 'fecha': f, 'kg': str(round(base, 2))}, hoy='2026-10-12')
a = correr('auditoria', hoy='2026-10-12')['polimeros'][0]
pr = a['prediccion']
ok(pr['kg_tinaco'] == 0.5 and pr['fijo'] == 3 and pr['r2'] >= 0.99,
   f"predicción: {pr['kg_tinaco']} kg de más por tinaco + {pr['fijo']} kg fijos por pesaje (r² {pr['r2']})")
ok(pr['desde_ajuste'] is True and pr['n'] == 4, 'la predicción usa los pesajes desde el último ajuste')
ok(a['actual']['pesajes'] == 4 and a['actual']['desde'] == '2026-10-08', 'desde el último ajuste: solo lo que no se ha ajustado')
ok(len(a['ajustes']) == 2 and a['ajustes'][1]['kg'] == -35 and a['ajustes'][0]['kg'] == -2, 'historial de ajustes por merma')
e = correr('merma', {'marcar': 'si'}, hoy='2026-10-12')
ok(correr('auditoria', hoy='2026-10-12')['polimeros'][0]['actual']['pesajes'] == 0, 'al ajustar, la cuenta empieza de cero (el historial se queda)')
# Microsip ya trae el movimiento de inventario con el polímero: se sugiere su folio
subprocess.run(['psql', '-h', '/var/tmp/pgc', '-p', '5544', '-U', 'postgres', '-q', '-c',
  "INSERT INTO ms_raw (base, tabla, pk, fecha, datos) VALUES ('LOMAS AJUSCO', 'RESUMEN_MOVTOS_IN', 'm1', current_date, "
  "'{\"articulo_id\": 50, \"tipo\": \"S\", \"origen\": \"IN\", \"concepto\": \"SALIDA POR MERMA\", \"folio\": \"SM0000123\", \"costo\": 100}')"], check=True)
f = correr('folio_ms', {'exporte_id': str(e['exporte_id'])})
ok(f['hay_copia'] and f['candidatos'] and f['candidatos'][0]['folio'] == 'SM0000123', 'encuentra en Microsip el documento donde se importó')
r = correr('importado', {'exporte_id': e['exporte_id'], 'folio': 'SM0000123'})
ok(any(x['folio_ms'] == 'SM0000123' for x in correr('merma', {}, hoy='2026-10-12')['anteriores']), 'ligar el folio de Microsip al importar')
print('Todo bien.')
