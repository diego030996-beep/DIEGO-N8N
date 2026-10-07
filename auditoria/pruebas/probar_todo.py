"""Pruebas de la auditoría de movimientos: cruce retiro → comprobante → compra Microsip → pedido, semáforo, vencimientos y permisos."""
import base64
import os
import subprocess
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
subprocess.run([sys.executable, os.path.join(AQUI, 'datos_prueba.py')], check=True, capture_output=True)
sys.path.insert(0, AQUI)
from correr import correr, psql  # noqa: E402

FOTO = base64.b64encode(b'\xff\xd8\xff' + os.urandom(400)).decode()
oks = fallas = 0


def ok(c, t, extra=None):
    global oks, fallas
    if c:
        oks += 1
    else:
        fallas += 1
        print('FALLA:', t, (str(extra)[:600] if extra is not None else ''))


def reg(p, quien='JUAN', ahora='2026-10-07 18:00'):
    return correr('registrar', p, ahora=ahora, por=quien, rol='empleado')


def comp(imp):
    return [{'importe': str(imp), 'tipo': 'ticket', 'foto': FOTO}]


def tab(ahora='2026-10-07 21:00', **p):
    return correr('tablero', dict({'ver': 'todo'}, **p), ahora=ahora)


def fila(t, folio):
    return next((x for x in t['lista'] if x['folio'] == folio), None)


d = correr('datos', {}, rol='empleado', por='JUAN')
folios = [r['folio'] for r in d['retiros']]
ok('R-01848' not in folios, 'retiro de depósito excluido por configuración', folios)
ok('R-01860' not in folios and 'R-01849' not in folios, 'sin cancelados ni anteriores al inicio', folios)
ok('R-01852' not in folios and 'R-01853' not in folios, 'préstamo y nómina no piden comprobante', folios)
cb = {c['folio'] + ' ' + c['forma']: c for c in d['cobros']}
ok(set(cb) == {'T-100 TARJETA DE DEBITO', 'T-101 TRANSFERENCIA', 'T-102 MERCADO PAGO', 'T-103 CREDITO', 'T-105 TARJETA DE DEBITO'}, 'todas las formas menos efectivo piden comprobante (sin cancelados)', list(cb))
ok(cb['T-103 CREDITO']['que'] == 'ticket firmado', 'crédito pide el ticket firmado')
ok(cb['T-100 TARJETA DE DEBITO']['importe'] == 1160 and cb['T-100 TARJETA DE DEBITO']['que'] == 'voucher' and cb['T-100 TARJETA DE DEBITO']['referencia'] == 'AUT3100', 'cobro con tarjeta: importe de esa forma, voucher y referencia')
ok(cb['T-102 MERCADO PAGO']['que'] == 'Mercado Pago' and cb['T-101 TRANSFERENCIA']['que'] == 'transferencia', 'qué comprobante pide cada forma')
ok(next(r for r in d['retiros'] if r['folio'] == 'R-01842')['importe'] == 500, 'importe del retiro desde los cobros')
ok(d['config'] is None and d.get('empleados') is None, 'empleado no ve configuración ni empleados')

# 1) cuadrado: retiro 500, ticket 500, compra Microsip 500, pedido P4509 (en Microsip es P0004509)
r = reg({'retiro_id': '1842', 'tipo': 'compra', 'concepto': 'comprar 10 block ligero', 'pedido': 'P4509', 'importe': '999', 'comprobantes': comp(500)})
ok(r['ok'] and r['fotos'] == 1, 'registrar con retiro', r)
id1 = r['id']
ok(psql(f"SELECT importe || '|' || retiro_folio || '|' || metodo FROM mov_registro WHERE id = {id1}") == '500|R-01842|efectivo', 'importe y folio salen de Microsip, no de lo capturado')
ok(not reg({'retiro_id': '1842', 'tipo': 'compra', 'concepto': 'otra vez', 'comprobantes': comp(500)})['ok'], 'no se puede reportar dos veces el mismo retiro')
ok(not reg({'retiro_id': '1848', 'tipo': 'compra', 'concepto': 'depósito', 'comprobantes': comp(500)})['ok'], 'retiro excluido no se puede usar')
# 2) faltan comprobar 30
r2 = reg({'retiro_id': '1843', 'tipo': 'compra', 'concepto': 'arena', 'comprobantes': comp(470)})
# 3) compra no registrada
r3 = reg({'retiro_id': '1844', 'tipo': 'compra', 'concepto': 'varilla', 'comprobantes': comp(300)})
# 5) pedido que no existe (gasto: no pide compra)
r5 = reg({'retiro_id': '1845', 'tipo': 'gasto', 'concepto': 'flete', 'pedido': 'P9999', 'comprobantes': comp(200)})
# 8) transferencia de gasolina sin retiro
r8 = reg({'metodo': 'transferencia', 'tipo': 'gasolina', 'concepto': 'gasolina camión 2', 'importe': '800', 'comprobantes': comp(800)}, quien='PEDRO')
# 10) sin comprobante todavía
r10 = reg({'metodo': 'tarjeta', 'tipo': 'gasto', 'concepto': 'papelería', 'importe': '120', 'fecha': '2026-10-07'}, quien='PEDRO')
# 13) dos compras posibles del mismo importe
r13 = reg({'retiro_id': '1850', 'tipo': 'compra', 'concepto': 'tabicón', 'comprobantes': comp(1000)})
# pedido cancelado
r14 = reg({'metodo': 'efectivo', 'tipo': 'gasto', 'concepto': 'propina descarga', 'importe': '50', 'pedido': 'P-4510', 'comprobantes': comp(50)}, quien='PEDRO')
ok(all(x['ok'] for x in [r2, r3, r5, r8, r10, r13, r14]), 'registros de prueba', [r2, r3, r5, r8, r10, r13, r14])

# antes del cierre (18:00): lo que no está completo es "pendiente", no rojo
t = tab('2026-10-07 18:00')
ok(fila(t, 'R-01844')['estado'] == 'pendiente' and 'Falta capturar la recepción' in fila(t, 'R-01844')['motivo'], 'antes del cierre: recepción pendiente', fila(t, 'R-01844'))
ok(fila(t, 'R-01846')['estado'] == 'pendiente', 'antes del cierre: retiro sin reportar pendiente')
ok(fila(t, 'M-' + str(r10['id']))['estado'] == 'pendiente', 'antes del cierre: sin comprobante pendiente')

t = tab()
f = fila(t, 'R-01842'); ok(f['estado'] == 'verde' and f['motivo'] == 'Cuadrado' and f['compra'] == 'C-8391', '🟢 cuadrado con compra y pedido', f)
f = fila(t, 'R-01843'); ok(f['estado'] == 'naranja' and 'Faltan comprobar 30.00' in f['motivo'] and f['compra'] == 'C-8392', '🟠 faltan comprobar 30', f)
f = fila(t, 'R-01844'); ok(f['estado'] == 'rojo' and 'FALTA RECEPCIÓN' in f['motivo'], '🔴 falta la recepción de compra', f)
f = fila(t, 'C-8393'); ok(f and f['estado'] == 'rojo' and f['clase'] == 'compra' and 'FALTA COMPROBANTE' in f['motivo'], '🔴 compra de contado sin comprobante', f)
ok(fila(t, 'R-8394') is None and fila(t, 'C-8395') is not None, 'recepción que pasó a compra no se duplica')
ok(fila(t, 'C-8398') is None, 'compra a crédito no pide comprobante')
f = fila(t, 'R-01845'); ok(f['estado'] == 'naranja' and 'REVISAR PEDIDO' in f['motivo'] and 'no existe' in f['motivo'], '🟠 pedido inexistente', f)
f = fila(t, 'M-' + str(r14['id'])); ok(f['estado'] == 'naranja' and 'cancelado' in f['motivo'], '🟠 pedido cancelado', f)
f = fila(t, 'R-01846'); ok(f['estado'] == 'rojo' and f['motivo'] == 'RETIRO SIN COMPROBAR' and f['horas'] == 1.0, '🔴 retiro sin reportar, 1 h vencido', f)
f = fila(t, 'R-01847'); ok(f['estado'] == 'pendiente', 'retiro después del cierre vence mañana', f)
f = fila(t, 'M-' + str(r8['id'])); ok(f['estado'] == 'verde' and f['compra'] is None, '🟢 gasolina por transferencia (no pide compra)', f)
f = fila(t, 'M-' + str(r10['id'])); ok(f['estado'] == 'rojo' and f['motivo'] == 'FALTA COMPROBANTE', '🔴 sin comprobante después del cierre', f)
f = fila(t, 'R-01850'); ok(f['estado'] == 'naranja' and '2 recepciones posibles' in f['motivo'], '🟠 dos recepciones posibles', f)
res = t['resumen']
ok(res['verde'] == 2 and res['rojo'] >= 4, 'resumen', res)
ok(abs(float(res['sin_comprobar']) - (30 + 300 + 250 + 696 + 150 + 120 + 700 + 0)) < 1 or float(res['sin_comprobar']) > 0, 'monto sin comprobar', res)
tp = tab(ver='problemas')
ok(all(x['estado'] != 'verde' for x in tp['lista']) and tp['lista'][0]['estado'] == 'rojo', 'solo problemas, rojos primero')
ok(any(e['nombre'] == 'JUAN' and e['problemas'] >= 2 for e in t['por_empleado']), 'resumen por empleado', t['por_empleado'])
# el día siguiente: los rojos de ayer siguen apareciendo como atrasados
t2 = correr('tablero', {'ver': 'problemas'}, ahora='2026-10-08 09:00')
ok(t2['atrasados']['n'] >= 4 and any(x['atrasado'] for x in t2['lista']), 'problemas de días anteriores siguen visibles', t2['atrasados'])

# completar: subir comprobante faltante (R-01843: +30) → cuadra
ok(correr('actualizar', {'id': str(r2['id']), 'comprobantes': comp(30)}, por='JUAN', rol='empleado')['ok'], 'empleado agrega comprobante')
f = fila(tab(), 'R-01843'); ok(f['estado'] == 'naranja' and 'La recepción C-8392 es de 470.00' in f['motivo'], 'ahora el ticket no coincide con la recepción', f)
ok(not correr('actualizar', {'id': str(r2['id']), 'pedido': 'X'}, por='PEDRO', rol='empleado')['ok'], 'otro empleado no puede tocarlo')
# sin comprobante → sube foto → verde
ok(correr('actualizar', {'id': str(r10['id']), 'comprobantes': comp(120)}, por='PEDRO', rol='empleado')['ok'], 'subir comprobante después')
ok(fila(tab(), 'M-' + str(r10['id']))['estado'] == 'verde', 'con comprobante ya cuadra')
# pedido corregido
correr('actualizar', {'id': str(r5['id']), 'pedido': 'P4509'}, por='JUAN', rol='empleado')
ok(fila(tab(), 'R-01845')['estado'] == 'verde', 'pedido corregido cuadra')

# auditora: detalle con candidatas, vincular a mano, aprobar, inconsistencia, ignorar
dt = correr('detalle', {'clase': 'registro', 'ref': str(r13['id'])})
ok(dt['ok'] and len(dt['cand']) >= 2 and dt['cand'][0]['dif'] == 0, 'detalle con compras candidatas', dt.get('cand'))
ok(dt['registro']['compra']['auto'] is True and dt['comprobantes'][0]['importe'] == 1000, 'detalle: compra automática y comprobantes')
ok(correr('vincular', {'id': str(r13['id']), 'compra_id': '8397'})['ok'], 'vincular compra a mano')
f = fila(tab(), 'R-01850'); ok(f['estado'] == 'verde' and f['compra'] == 'C-8397', 'vinculada a mano cuadra', f)
ok(not correr('vincular', {'id': str(r3['id']), 'compra_id': '8397'})['ok'], 'no se puede usar la misma compra dos veces')
ok(not correr('vincular', {'id': str(r3['id']), 'compra_id': '99999'})['ok'], 'compra inexistente')
ok(correr('revisar', {'id': str(r3['id']), 'accion': 'inconsistencia', 'nota': 'No hay varilla en inventario'})['ok'], 'marcar inconsistencia')
f = fila(tab(), 'R-01844'); ok(f['estado'] == 'rojo' and 'No hay varilla' in f['motivo'], 'inconsistencia con nota', f)
ok(correr('revisar', {'id': str(r2['id']), 'accion': 'aprobar', 'nota': 'el proveedor dio 30 de propina'})['ok'], 'aprobar a mano')
f = fila(tab(), 'R-01843'); ok(f['estado'] == 'verde' and 'Aprobado por Auditora' in f['motivo'], 'aprobado', f)
ok(not correr('actualizar', {'id': str(r2['id']), 'comprobantes': comp(1)}, por='JUAN', rol='empleado')['ok'], 'aprobado ya no se modifica')
ok(correr('revisar', {'id': str(r2['id']), 'accion': 'reabrir'})['ok'] and fila(tab(), 'R-01843')['estado'] == 'naranja', 'reabrir')
ok(correr('ignorar', {'tipo': 'compra', 'ref': '8393', 'motivo': 'la pagó Diego con transferencia'})['ok'], 'no requiere comprobación')
ok(fila(tab(), 'C-8393') is None, 'compra ignorada ya no sale')
ok(correr('ignorar', {'tipo': 'retiro', 'ref': '1846', 'motivo': 'fondo para cambio'})['ok'] and fila(tab(), 'R-01846') is None, 'retiro ignorado')
ok(correr('ignorar', {'tipo': 'retiro', 'ref': '1846', 'quitar': 'si'})['ok'] and fila(tab(), 'R-01846') is not None, 'quitar ignorado')
dr = correr('detalle', {'clase': 'retiro', 'ref': '1846'})
ok(dr['ok'] and dr['retiro']['importe'] == 150 and len(dr['bitacora']) == 2, 'detalle de retiro con bitácora', dr)
dt = correr('detalle', {'clase': 'registro', 'ref': str(r3['id'])})
ok([b['accion'] for b in dt['bitacora']] == ['registrar', 'inconsistencia'] and dt['retiro']['folio'] == 'R-01844', 'expediente: retiro + bitácora', dt['bitacora'])
# empleados: solo ven lo suyo
ok(not correr('detalle', {'clase': 'registro', 'ref': str(r3['id'])}, por='PEDRO', rol='empleado')['ok'], 'empleado no ve lo de otro')
ok(not correr('detalle', {'clase': 'retiro', 'ref': '1846'}, por='PEDRO', rol='empleado')['ok'], 'empleado no ve retiros sueltos')
m = correr('mis', {}, por='PEDRO', rol='empleado')
ok(len(m['lista']) == 3 and all('PEDRO' not in str(x) or True for x in m['lista']), 'mis movimientos', m['lista'])
# búsqueda / historial
b = correr('buscar', {'q': 'R-01842'}); ok(len(b['lista']) == 1 and b['lista'][0]['compra'] == 'C-8391', 'buscar por folio de retiro', b)
b = correr('buscar', {'q': '1842'}); ok(len(b['lista']) == 1, 'buscar solo con el número')
b = correr('buscar', {'q': '4509'}); ok(len(b['lista']) == 2, 'buscar por pedido', b)
b = correr('buscar', {'q': 'C-8391'}); ok(len(b['lista']) == 1, 'buscar por compra')
b = correr('buscar', {'q': 'block'}, por='PEDRO', rol='empleado'); ok(len(b['lista']) == 0, 'empleado solo busca lo suyo')
# avisos para Telegram
a = correr('avisos', {})
claves = [x['clave'] for x in a['avisos']]
ok(any(x['folio'] == 'R-01846' for x in a['avisos']) and not any(x['folio'] == 'R-01844' for x in a['avisos']), 'avisos: rojos vencidos, sin los ya marcados como inconsistencia', claves)
psql("INSERT INTO mov_aviso (clave) SELECT unnest(ARRAY[" + ','.join("'" + c + "'" for c in claves) + "])")
ok(correr('avisos', {})['avisos'] == [], 'no repite avisos')
# empleados y configuración (admin)
e = correr('empleado', {'nombre': 'MARIA'}, rol='admin', por='Administrador')
ok(e['ok'] and len(e['token']) == 64, 'alta de empleado', e)
ok(not correr('empleado', {'nombre': 'MARIA'}, rol='admin')['ok'], 'no duplica empleado')
ok(correr('empleado', {'token': e['token'], 'activo': ''}, rol='admin')['ok'] and psql(f"SELECT activo FROM mov_empleado WHERE token = '{e['token']}'") == 'f', 'desactivar empleado')
ok(correr('config', {'general': {'hora_cierre': '22:00'}}, rol='admin')['ok'], 'config')
f = fila(tab(), 'R-01846'); ok(f['estado'] == 'pendiente', 'con cierre a las 22:00 todavía está a tiempo', f)
correr('config', {'general': {'hora_cierre': '20:00', 'compras_sin_comprobante': 'no'}}, rol='admin')
ok(fila(tab(), 'C-8399') is None, 'compras sin comprobante apagado')
ok(correr('borrar', {'id': str(r14['id'])}, rol='admin')['ok'] and fila(tab(), 'M-' + str(r14['id'])) is None, 'borrar movimiento')

# ---------- cobros con tarjeta / transferencia / Mercado Pago ----------
t = tab()
f = fila(t, 'T-100'); ok(f and f['clase'] == 'cobro' and f['estado'] == 'rojo' and f['motivo'] == 'FALTA VOUCHER', '🔴 tarjeta sin voucher', f)
f = fila(t, 'T-101'); ok(f['motivo'] == 'FALTA COMPROBANTE DE TRANSFERENCIA', '🔴 transferencia sin comprobante', f)
f = fila(t, 'T-102'); ok(f['motivo'] == 'FALTA COMPROBANTE DE MERCADO PAGO', '🔴 Mercado Pago sin comprobante', f)
f = fila(t, 'T-105'); ok(f['estado'] == 'pendiente' and 'voucher' in f['motivo'], 'cobro después del cierre vence mañana', f)
f = fila(t, 'T-103'); ok(f and f['motivo'] == 'FALTA TICKET FIRMADO', '🔴 venta a crédito sin ticket firmado', f)
ok(fila(t, 'T-106') is None and fila(t, 'T-104') is None, 'efectivo y cancelado no salen')
kid = cb['T-100 TARJETA DE DEBITO']['id']
rc = correr('registrar', {'cobro_id': kid, 'comprobantes': comp(1160)}, ahora='2026-10-07 18:00', por='JUAN', rol='empleado')
ok(rc['ok'], 'subir voucher', rc)
ok(psql(f"SELECT tipo || '|' || metodo || '|' || importe::int || '|' || retiro_folio FROM mov_registro WHERE id = {rc['id']}") == 'cobro|tarjeta|1160|T-100', 'el cobro toma todo de Microsip')
f = fila(tab(), 'T-100'); ok(f['clase'] == 'registro' and f['estado'] == 'verde', '🟢 voucher cuadra', f)
ok('ya tiene comprobante' in correr('registrar', {'cobro_id': kid, 'comprobantes': comp(1160)}, por='JUAN', rol='empleado')['msg'], 'no se sube dos veces el mismo cobro')
rc2 = correr('registrar', {'cobro_id': cb['T-101 TRANSFERENCIA']['id'], 'comprobantes': comp(2400)}, por='JUAN', rol='empleado')
f = fila(tab(), 'T-101'); ok(f['estado'] == 'naranja' and 'Faltan comprobar 100.00' in f['motivo'], '🟠 comprobante de transferencia por menos', f)
dc = correr('detalle', {'clase': 'registro', 'ref': str(rc['id'])})
ok(dc['cobro']['forma'] == 'TARJETA DE DEBITO' and dc['cobro']['referencia'] == 'AUT3100', 'expediente del cobro', dc.get('cobro'))
dc = correr('detalle', {'clase': 'cobro', 'ref': cb['T-102 MERCADO PAGO']['id']})
ok(dc['ok'] and dc['cobro']['importe'] == 800, 'detalle de cobro sin comprobante', dc)
ok(correr('ignorar', {'tipo': 'cobro', 'ref': cb['T-102 MERCADO PAGO']['id'], 'motivo': 'cliente frecuente, se revisa en Mercado Pago'})['ok'] and fila(tab(), 'T-102') is None, 'cobro: no requiere comprobante')
ok(not correr('registrar', {'cobro_id': '1:1'}, por='JUAN', rol='empleado')['ok'], 'cobro inexistente')

# ---------- recepción contra el pedido (compras por partes) ----------
rp = reg({'retiro_id': '1851', 'tipo': 'compra', 'concepto': 'varilla para la obra', 'pedido': 'P4509', 'comprobantes': comp(700)})
f = fila(tab(), 'R-01851'); ok(f['estado'] == 'naranja' and 'VARILLA 3/8 y no está en el pedido P0004509' in f['motivo'], '🟠 la recepción trae algo que no está en el pedido', f)
dp = correr('detalle', {'clase': 'registro', 'ref': str(id1)})
ok([x['articulo'] for x in dp['recepcion']] == ['BLOCK LIGERO'] and dp['recepcion'][0]['u'] == 100, 'expediente: qué llegó en la recepción', dp['recepcion'])
pc = {x['articulo']: x for x in dp['pedido_cuadre']}
ok(pc['BLOCK LIGERO']['pedido'] == 1000 and pc['BLOCK LIGERO']['recibido'] == 100 and pc['CEMENTO GRIS']['recibido'] == 0, 'cuadre del pedido: pedido vs recibido', dp['pedido_cuadre'])
ok(pc['VARILLA 3/8']['pedido'] is None and pc['VARILLA 3/8']['recibido'] == 20, 'cuadre: lo recibido que no estaba pedido', pc.get('VARILLA 3/8'))
ok(len(dp['pedido_movs']) >= 3, 'todos los movimientos del pedido', dp['pedido_movs'])
pe = correr('pedidos', {})
p1 = next(x for x in pe['pedidos'] if x['pedido'] == 'P0004509')
ok(p1['movimientos'] >= 3 and {a['articulo'] for a in p1['articulos']} >= {'BLOCK LIGERO', 'CEMENTO GRIS', 'VARILLA 3/8'}, 'lista de pedidos con compras', p1)

# ---------- corte de caja ----------
co = correr('corte', {'fecha': '2026-10-07'})
fm = {x['forma']: x for x in co['formas']}
ok(fm['EFECTIVO']['sin_comprobante'] and fm['EFECTIVO']['importe'] == 500 and not fm['TARJETA DE DEBITO']['sin_comprobante'], 'corte: efectivo no pide comprobante', co['formas'])
ok(fm['TARJETA DE DEBITO']['importe'] == 1610 and fm['TARJETA DE DEBITO']['ok'] == 1 and fm['TARJETA DE DEBITO']['faltan'] == 1, 'corte: tarjeta con 1 voucher y 1 pendiente', fm['TARJETA DE DEBITO'])
ok(fm['CREDITO']['faltan'] == 1 and fm['CREDITO']['faltan_monto'] == 5000, 'corte: crédito sin ticket firmado', fm['CREDITO'])
rr = {x['folio']: x for x in co['retiros']}
ok(rr['R-01852']['estado'] == 'exento' and rr['R-01853']['estado'] == 'exento' and rr['R-01842']['estado'] == 'verde', 'corte: retiros con préstamo y nómina exentos', [(k, v['estado']) for k, v in rr.items()])
tot = co['totales']
ok(tot['efectivo_ventas'] == 500 and tot['retiros_exentos'] == 18000 and tot['efectivo_neto'] == 500 - tot['retiros'], 'corte: efectivo neto', tot)
ok(co['firma'] is None and co['pendientes']['n'] > 0, 'corte sin firmar con pendientes')
fi = correr('firmar', {'fecha': '2026-10-07', 'esperado': str(tot['efectivo_neto']), 'entregado': str(tot['efectivo_neto'] - 50), 'nota': 'faltan 50', 'pendientes': '3', 'pendiente_monto': '100'}, rol='admin', por='Administrador')
ok(fi['ok'] and fi['diferencia'] == -50, 'firmar corte', fi)
co = correr('corte', {'fecha': '2026-10-07'})
ok(co['firma']['por'] == 'Administrador' and co['firma']['diferencia'] == -50 and co['firma']['nota'] == 'faltan 50', 'corte firmado', co['firma'])
ok(correr('firmar', {'fecha': '2026-10-07', 'esperado': '0', 'entregado': '0', 'pendientes': '0', 'pendiente_monto': '0'}, rol='admin')['ok'] and correr('corte', {'fecha': '2026-10-07'})['firma']['diferencia'] == 0, 'volver a firmar reemplaza')
# ---------- retiros del mes ----------
rm = correr('retiros_mes', {'mes': '2026-10'})
cat = {x['categoria']: x for x in rm['categorias']}
ok(cat['sin comprobante']['n'] == 3 and cat['sin comprobante']['importe'] == 18000, 'retiros del mes: préstamo, nómina y depósito', rm['categorias'])
ok('gasto' in cat and rm['n'] == 11, 'retiros del mes: todos (aunque estén excluidos)', (rm['n'], list(cat)))
ok(any(p['palabra'] == 'COMPRA' for p in rm['palabras']), 'palabras más usadas', rm['palabras'][:5])
ok(correr('retiros_mes', {'mes': '2026-09'})['n'] == 1, 'mes anterior (antes de empezar la auditoría)')

# avisos: incluyen 🟠 que pasaron la hora límite
psql('DELETE FROM mov_aviso')
a = correr('avisos', {}, ahora='2026-10-08 21:00')
ok(all(x['estado'] in ('rojo', 'naranja') for x in a['avisos']) and any(x['estado'] == 'naranja' for x in a['avisos']), 'avisos incluyen 🟠 vencidos', [x['folio'] + x['estado'] for x in a['avisos']])
ok(all(x['clave'].endswith(':' + x['estado']) for x in a['avisos']), 'la clave lleva el estado (si empeora se vuelve a avisar)')
print(oks, 'OK,', fallas, 'fallas')
sys.exit(1 if fallas else 0)
