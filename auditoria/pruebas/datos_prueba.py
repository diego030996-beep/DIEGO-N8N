"""Crea la base 'auditoria' de prueba con lo mínimo de la copia de Microsip: retiros de caja, compras, recepciones, proveedores y pedidos."""
import json
import subprocess

PSQL = ['psql', '-h', '/var/tmp/pgc', '-p', '5544', '-U', 'postgres', '-At', '-v', 'ON_ERROR_STOP=1']
subprocess.run(PSQL + ['-c', 'DROP DATABASE IF EXISTS auditoria'], check=True, capture_output=True)
subprocess.run(PSQL + ['-c', 'CREATE DATABASE auditoria'], check=True, capture_output=True)
q = lambda s: "'" + str(s).replace("'", "''") + "'"
S = ["""
CREATE TABLE ms_ventas (base TEXT, origen TEXT, docto_id BIGINT, tipo TEXT, estatus TEXT, folio TEXT, fecha DATE, hora TEXT, cliente TEXT, almacen TEXT,
  importe NUMERIC, impuestos NUMERIC, descripcion TEXT, usuario TEXT, usuario_cancelacion TEXT, fecha_cancelacion TIMESTAMP, caja_id BIGINT, cajero_id BIGINT,
  cliente_id BIGINT, sync_id TEXT, actualizado TIMESTAMPTZ DEFAULT now(), PRIMARY KEY (base, origen, docto_id));
CREATE VIEW ms_ventas_v AS SELECT v.*, v.importe + v.impuestos AS total, (v.estatus = 'C') AS cancelado FROM ms_ventas v;
CREATE TABLE ms_raw (base TEXT, tabla TEXT, pk TEXT, fecha DATE, datos JSONB, sync_id TEXT, actualizado TIMESTAMPTZ DEFAULT now(), PRIMARY KEY (base, tabla, pk));
CREATE TABLE mov_config (clave TEXT PRIMARY KEY, valor TEXT, por TEXT, actualizado TIMESTAMPTZ NOT NULL DEFAULT now());
INSERT INTO mov_config (clave, valor) VALUES ('desde', '2026-10-01'), ('retiros_excluir', 'DEPOSITO|PR[EÉ]STAMO|N[OÓ]MINA'), ('formas_comprobante', 'TARJETA|TRANSFER|SPEI|MERCADO ?PAGO'), ('compras_sin_comprobante', 'contado');
"""]
# retiros de caja (PV, tipo R). importe en ms_ventas = 0; lo real viene de DOCTOS_PV_COBROS
ret = [  # id, folio, fecha, hora, descripcion, importe
    (1842, 'R-01842', '2026-10-07', '10:00', 'COMPRA BLOCK LIGERO', 500),
    (1843, 'R-01843', '2026-10-07', '11:00', 'COMPRA ARENA', 500),
    (1844, 'R-01844', '2026-10-07', '12:00', 'COMPRA VARILLA', 300),
    (1845, 'R-01845', '2026-10-07', '12:30', 'GASTO FLETE', 200),
    (1846, 'R-01846', '2026-10-07', '13:00', 'PAGO X', 150),
    (1847, 'R-01847', '2026-10-07', '20:30', 'COMPRA TARDE', 90),
    (1848, 'R-01848', '2026-10-07', '14:00', 'DEPOSITO BANCO', 9000),
    (1849, 'R-01849', '2026-09-20', '10:00', 'RETIRO VIEJO', 400),
    (1850, 'R-01850', '2026-10-07', '15:00', 'COMPRA TABICON', 1000),
    (1851, 'R-01851', '2026-10-07', '16:00', 'COMPRA CEMENTO', 700),
    (1852, 'R-01852', '2026-10-07', '17:00', 'PRÉSTAMO A PEDRO', 1000),
    (1853, 'R-01853', '2026-10-07', '17:30', 'Nomina semana 40', 8000),
]
for i, f, d, h, desc, imp in ret:
    S.append(f"INSERT INTO ms_ventas (base, origen, docto_id, tipo, estatus, folio, fecha, hora, importe, impuestos, descripcion, usuario) VALUES ('B', 'PV', {i}, 'R', 'N', {q(f)}, {q(d)}, {q(h + ':00')}, 0, 0, {q(desc)}, 'CAJERA1');")
    S.append(f"INSERT INTO ms_raw VALUES ('B', 'DOCTOS_PV_COBROS', 'c{i}', {q(d)}, {q(json.dumps({'DOCTO_PV_ID': i, 'FORMA_COBRO_ID': 1, 'IMPORTE': -imp}))});")
# un retiro cancelado
S.append("INSERT INTO ms_ventas (base, origen, docto_id, tipo, estatus, folio, fecha, hora, importe, impuestos, descripcion) VALUES ('B', 'PV', 1860, 'R', 'C', 'R-01860', '2026-10-07', '09:00:00', 0, 0, 'CANCELADO');")
S.append("INSERT INTO ms_raw VALUES ('B', 'DOCTOS_PV_COBROS', 'c1860', '2026-10-07', '{\"DOCTO_PV_ID\": 1860, \"IMPORTE\": 50}');")
# formas de cobro y tickets cobrados con tarjeta / transferencia / Mercado Pago (piden comprobante); efectivo y crédito no
for pk, n in [(1, 'EFECTIVO'), (2, 'TARJETA DE DEBITO'), (3, 'TRANSFERENCIA'), (4, 'MERCADO PAGO'), (5, 'CREDITO')]:
    S.append(f"INSERT INTO ms_raw VALUES ('B', 'FORMAS_COBRO', '{pk}', NULL, {q(json.dumps({'NOMBRE': n}))});")
tk = [  # docto, folio, hora, estatus, [(forma, importe)]
    (3100, 'T-100', '10:30', 'N', [(2, 1160), (1, 200)]),
    (3101, 'T-101', '12:00', 'N', [(3, 2500)]),
    (3102, 'T-102', '13:00', 'N', [(4, 800)]),
    (3103, 'T-103', '13:30', 'N', [(5, 5000)]),
    (3104, 'T-104', '14:00', 'C', [(2, 999)]),
    (3105, 'T-105', '20:40', 'N', [(2, 450)]),
    (3106, 'T-106', '15:00', 'N', [(1, 300)]),
]
for i, f, h, est, cobros in tk:
    S.append(f"INSERT INTO ms_ventas (base, origen, docto_id, tipo, estatus, folio, fecha, hora, cliente, importe, impuestos, usuario) VALUES ('B', 'PV', {i}, 'V', {q(est)}, {q(f)}, '2026-10-07', {q(h + ':00')}, 'PUBLICO', {sum(x[1] for x in cobros) / 1.16:.2f}, {sum(x[1] for x in cobros) - sum(x[1] for x in cobros) / 1.16:.2f}, 'CAJERA1');")
    for j, (fid, imp) in enumerate(cobros):
        S.append(f"INSERT INTO ms_raw VALUES ('B', 'DOCTOS_PV_COBROS', 'k{i}{j}', '2026-10-07', {q(json.dumps({'DOCTO_PV_ID': i, 'FORMA_COBRO_ID': fid, 'TIPO': 'C', 'IMPORTE': imp, 'REFERENCIA': 'AUT' + str(i) if fid == 2 else ''}))});")
# ventas normales (no deben salir)
S.append("INSERT INTO ms_ventas (base, origen, docto_id, tipo, estatus, folio, fecha, hora, importe, impuestos) VALUES ('B', 'PV', 2000, 'V', 'N', 'T-1', '2026-10-07', '10:00:00', 100, 16);")
# pedidos de Ventas
S.append("INSERT INTO ms_ventas (base, origen, docto_id, tipo, estatus, folio, fecha, cliente, importe, impuestos) VALUES ('B', 'VE', 4509, 'P', 'N', 'P0004509', '2026-10-05', 'OBRA LOMAS', 5000, 800);")
S.append("INSERT INTO ms_ventas (base, origen, docto_id, tipo, estatus, folio, fecha, cliente, importe, impuestos) VALUES ('B', 'VE', 4510, 'P', 'C', 'P0004510', '2026-10-05', 'CANCELADO SA', 1000, 160);")
# proveedores y condiciones de pago
for pk, n in [(1, 'BLOCKERA AJUSCO'), (2, 'ARENERA SUR'), (3, 'CEMEX'), (4, 'TABIQUERA A'), (5, 'TABIQUERA B')]:
    S.append(f"INSERT INTO ms_raw VALUES ('B', 'PROVEEDORES', '{pk}', NULL, {q(json.dumps({'PROVEEDOR_ID': pk, 'NOMBRE': n}))});")
S.append("INSERT INTO ms_raw VALUES ('B', 'CONDICIONES_PAGO', '1', NULL, '{\"NOMBRE\": \"CONTADO\"}'), ('B', 'CONDICIONES_PAGO', '2', NULL, '{\"NOMBRE\": \"CREDITO 30 DIAS\"}');")
cm = [  # id, tipo, folio, fecha, prov, cond, neto, iva
    (8391, 'C', 'C-8391', '2026-10-07', 1, 1, 431.03, 68.97),   # = 500 → R-01842
    (8392, 'C', 'C-8392', '2026-10-07', 2, 1, 405.17, 64.83),   # = 470 → R-01843 (comprobó 470)
    (8393, 'C', 'C-8393', '2026-10-06', 3, 1, 215.52, 34.48),   # = 250 contado sin comprobante → rojo
    (8394, 'R', 'R-8394', '2026-10-06', 3, 1, 600, 96),         # recepción que pasó a compra C-8395: no se duplica
    (8395, 'C', 'C-8395', '2026-10-06', 3, 1, 600, 96),
    (8396, 'C', 'C-8396', '2026-10-07', 4, 1, 862.07, 137.93),  # 1000 (dos candidatas para R-01850)
    (8397, 'C', 'C-8397', '2026-10-07', 5, 1, 862.07, 137.93),  # 1000
    (8398, 'C', 'C-8398', '2026-10-07', 3, 2, 5000, 800),       # a crédito: no pide comprobante
    (8399, 'C', 'C-8399', '2026-10-07', 3, 1, 603.45, 96.55),   # 700 contado → R-01851 (pero vinculada a mano a otra)
]
for i, t, f, d, pv, cp, n, iva in cm:
    S.append(f"INSERT INTO ms_raw VALUES ('B', 'DOCTOS_CM', '{i}', {q(d)}, {q(json.dumps({'DOCTO_CM_ID': i, 'TIPO_DOCTO': t, 'FOLIO': f, 'FECHA': d, 'PROVEEDOR_ID': pv, 'COND_PAGO_ID': cp, 'ESTATUS': 'N', 'IMPORTE_NETO': n, 'TOTAL_IMPUESTOS': iva}))});")
S.append("INSERT INTO ms_raw VALUES ('B', 'DOCTOS_CM_LIGAS', 'l1', NULL, '{\"DOCTO_CM_FTE_ID\": 8394, \"DOCTO_CM_DEST_ID\": 8395}');")
r = subprocess.run(PSQL + ['-d', 'auditoria', '-c', '\n'.join(S)], text=True, capture_output=True)
if r.returncode:
    raise SystemExit(r.stderr)
print('base auditoria lista')
