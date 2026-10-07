"""Crea en un Postgres de prueba las tablas espejo de Microsip (ms_*) con datos inventados + las OCs del diario de compras."""
import json
import random
import subprocess
import sys
from datetime import date, timedelta

PSQL = sys.argv[1:] or ['psql', '-h', '/var/tmp/pgc', '-p', '5544', '-U', 'postgres', '-q', '-v', 'ON_ERROR_STOP=1']
B = 'LOMAS AJUSCO'
random.seed(7)

ddl = """
DROP SCHEMA public CASCADE; CREATE SCHEMA public;
CREATE TABLE ms_existencias (base TEXT, articulo_id BIGINT, almacen_id BIGINT, almacen TEXT, clave TEXT, articulo TEXT,
  existencia NUMERIC, valor NUMERIC, sync_id TEXT, actualizado TIMESTAMPTZ DEFAULT now(), PRIMARY KEY (base, articulo_id, almacen_id));
CREATE TABLE ms_articulos (base TEXT, articulo_id BIGINT, clave TEXT, nombre TEXT, estatus TEXT, unidad TEXT, linea TEXT, grupo TEXT,
  precio_lista NUMERIC, costo_ultimo NUMERIC, precio_minimo NUMERIC, sync_id TEXT, actualizado TIMESTAMPTZ DEFAULT now(), PRIMARY KEY (base, articulo_id));
CREATE TABLE ms_ventas (base TEXT, origen TEXT, docto_id BIGINT, tipo TEXT, estatus TEXT, folio TEXT, fecha DATE, hora TEXT,
  cliente TEXT, almacen TEXT, importe NUMERIC, impuestos NUMERIC, cliente_id BIGINT, sync_id TEXT, actualizado TIMESTAMPTZ DEFAULT now(), PRIMARY KEY (base, origen, docto_id));
CREATE TABLE ms_ventas_det (base TEXT, origen TEXT, det_id BIGINT, docto_id BIGINT, clave TEXT, articulo_id BIGINT, articulo TEXT,
  unidades NUMERIC, precio_unitario NUMERIC, importe NUMERIC, sync_id TEXT, actualizado TIMESTAMPTZ DEFAULT now(), PRIMARY KEY (base, origen, det_id));
CREATE INDEX ms_ventas_fecha ON ms_ventas (fecha);
CREATE INDEX ms_ventas_det_docto ON ms_ventas_det (base, origen, docto_id);
CREATE TABLE ms_raw (base TEXT, tabla TEXT, pk TEXT, fecha DATE, datos JSONB, sync_id TEXT, actualizado TIMESTAMPTZ DEFAULT now(), PRIMARY KEY (base, tabla, pk));
CREATE INDEX ms_raw_tabla_fecha ON ms_raw (tabla, fecha);
CREATE TABLE tablero_acceso (token TEXT PRIMARY KEY, rol TEXT NOT NULL, activo BOOLEAN NOT NULL DEFAULT true, creado TIMESTAMPTZ NOT NULL DEFAULT now());
INSERT INTO tablero_acceso VALUES ('k-compras', 'compras', true), ('k-auditor', 'auditor', true);
"""

prov = {'10': 'FERRECORRECAMINOS', '11': 'CIMAEP DE CONTADO', '12': 'CASA BLANCA', '13': 'DISTRIBUIDORA FERREMAX',
        '14': 'CEMEX S.A.B DE CV', '15': 'DISTRIBUIDORA LUMAR', '16': 'TRUPER', '17': 'FABRICA TINACOS'}
arts = [  # id, clave, nombre, unidad, precio, ventas por día aprox, proveedor
    (1, 'CEM25', 'CEMENTO GRIS TOLTECA 25KG', 'Saco', 135, 12, '14'),
    (2, 'CEM50', 'CEMENTO GRIS TOLTECA 50KG', 'SACO', 240, 9, '14'),
    (3, 'MOR25', 'MORTERO DE 25 KG', 'SACO', 110, 5, '14'),
    (4, 'ARENA', 'ARENA X MT', 'Metro cúbico', 420, 1.2, '11'),
    (5, 'TPVC75', 'TUBO PVC 75 REFORZADO (3")', 'Pieza', 320, 0.4, '12'),
    (6, 'TPLUS25', 'TUBO PLUS 25 MM (3/4")', 'Pieza', 175, 0.6, '12'),
    (7, 'CPLUS25', 'CODO PLUS 25 X 90 ROTOPLAS (3/4")', 'Pieza', 12, 1.5, '12'),
    (8, 'CPLUS20', 'CODO PLUS 20 X 90 ROTOPLAS (1/2")', 'Pieza', 9, 1.8, '12'),
    (9, 'SIL300', 'SILICON SISTA TRANSPARENTE 300ML', 'Pieza', 110, 0.3, '10'),
    (10, 'PEGPVC85', 'PEGAMENTO P/PVC 85 ML SILER', 'Pieza', 75, 0.25, '10'),
    (11, 'CLAVO25', 'CLAVO ESTANDAR 2 1/2 KG', 'Kilogramo', 40, 1.1, '15'),
    (12, 'CINTA', 'CINTA AISLAR GRANDE NITTO', 'Pieza', 50, 0.4, '15'),
    (13, 'FLEX5', 'FLEXOMETRO PRETUL 5MT COLORES', 'Pieza', 55, 0.2, '13'),
    (14, 'DISCO', 'DISCO SABLE CORTE DE METAL 4 1/2', 'Pieza', 18, 0.9, '13'),
    (15, 'MARTILLO', 'MARTILLO TRUPER 16OZ', 'Pieza', 180, 0.05, '16'),
    (16, 'TINACO', 'TINACO 1100 LTS', 'Pieza', 2500, 0.1, None),
    (17, 'BROCHA4', 'BROCHA 4 PULGADAS', 'Pieza', 60, 0.3, '16'),      # C: solo vendió en enero-febrero
    (18, 'TALADRO', 'TALADRO TRUPER 1/2', 'Pieza', 900, 0.4, '16'),    # nuevo: solo vendió en octubre
    (19, 'CINTAP', 'CINTA AISLAR NEGRA PRETUL', 'Pieza', 30, 0.5, '15'),  # duplicado de marca de...
    (20, 'CINTAN', 'CINTA AISLAR NEGRA NITTO', 'Pieza', 45, 0.6, '15'),   # ...esta
    (21, 'LLAVE38', 'LLAVE ESPAÑOLA 3/8 TRUPER', 'Pieza', 60, 0.3, '16'), # misma marca, otra medida: NO es duplicado
    (22, 'LLAVE516', 'LLAVE ESPAÑOLA 5/16 TRUPER', 'Pieza', 60, 0.3, '16'),
    (23, 'BISAGRA', 'BISAGRA LATON 3 PULGADAS', 'Pieza', 80, 0.0, '16'),  # una sola venta
]
VENTANA = {17: (date(2026, 1, 5), date(2026, 2, 28)), 18: (date(2026, 10, 1), date(2026, 10, 31))}
sql = [ddl]
q = lambda s: "NULL" if s is None else "'" + str(s).replace("'", "''") + "'"
for a in arts:
    sql.append(f"INSERT INTO ms_articulos (base, articulo_id, clave, nombre, estatus, unidad, linea, grupo, precio_lista, costo_ultimo) VALUES "
               f"({q(B)}, {a[0]}, {q(a[1])}, {q(a[2])}, 'A', {q(a[3])}, {q('TINACOS Y CISTERNAS' if a[0] == 16 else 'MATERIALES')}, '', {a[4]}, "
               f"{'NULL' if a[0] in (5, 15) else round(a[4] * 0.7, 4)});")
    sql.append(f"INSERT INTO ms_existencias (base, articulo_id, almacen_id, almacen, clave, articulo, existencia, valor) VALUES "
               f"({q(B)}, {a[0]}, 1, 'GENERAL', {q(a[1])}, {q(a[2])}, {round(a[5] * random.uniform(2, 20))}, 1);")
for k, v in prov.items():
    sql.append(f"INSERT INTO ms_raw (base, tabla, pk, datos) VALUES ({q(B)}, 'PROVEEDORES', {q(k)}, {q(json.dumps({'PROVEEDOR_ID': int(k), 'NOMBRE': v}))});")

# ventas diarias de marzo a hoy
d, docto, det = date(2026, 1, 1), 1000, 1
fin = date(2026, 10, 6)
while d <= fin:
    if d.weekday() < 6:
        for a in arts:
            if a[0] in VENTANA and not (VENTANA[a[0]][0] <= d <= VENTANA[a[0]][1]):
                continue
            if a[0] not in VENTANA and d < date(2026, 3, 1):
                continue
            if a[0] == 23:
                if d != date(2026, 6, 15):
                    continue
            u = sum(1 for _ in range(int(a[5] * 3)) if random.random() < 1 / 3)
            if a[5] < 1 and random.random() < a[5]:
                u += 1
            if a[0] == 23:
                u = 2
            if u <= 0:
                continue
            docto += 1
            tipo = 'V'
            sql.append(f"INSERT INTO ms_ventas VALUES ({q(B)}, 'PV', {docto}, '{tipo}', 'N', 'T{docto}', '{d}', '10:00', 'PUBLICO', 'GENERAL', {u * a[4]}, {u * a[4] * 0.16}, NULL);")
            sql.append(f"INSERT INTO ms_ventas_det VALUES ({q(B)}, 'PV', {det}, {docto}, {q(a[1])}, {a[0]}, {q(a[2])}, {u}, {a[4]}, {u * a[4]});")
            det += 1
    d += timedelta(days=1)

# OCs del diario de compras (agosto–septiembre) + una de octubre abierta
ocs = [
    (62, '2026-08-13', '10', [(9, 5), (10, 4)]),
    (64, '2026-08-26', '11', [(5, 2), (6, 5), (7, 13), (8, 5)]),
    (65, '2026-08-26', '12', [(8, 25), (7, 20), (5, 10), (6, 10)]),
    (66, '2026-08-31', '11', [(4, 17)]),
    (67, '2026-08-31', '13', [(13, 4), (14, 20)]),
    (72, '2026-09-19', '14', [(1, 280), (3, 120)]),
    (73, '2026-09-21', '15', [(11, 25), (12, 10)]),
    (74, '2026-09-22', '14', [(1, 360), (2, 20)]),
    (76, '2026-09-29', '14', [(2, 200)]),
    (77, '2026-10-05', '14', [(1, 100)]),
    (63, '2026-08-20', '17', [(16, 10)]),   # OC de tinacos: no debe entrar
    (68, '2026-09-10', '16', [(17, 3)]),
]
precio = {a[0]: a[4] * 0.75 for a in arts}
for folio, f, p, lineas in ocs:
    did = 5000 + folio
    imp = sum(precio[a] * u for a, u in lineas)
    sql.append(f"INSERT INTO ms_raw (base, tabla, pk, fecha, datos) VALUES ({q(B)}, 'DOCTOS_CM', '{did}', '{f}', "
               f"{q(json.dumps({'DOCTO_CM_ID': did, 'TIPO_DOCTO': 'O', 'FOLIO': 'O%07d' % folio, 'FECHA': f, 'PROVEEDOR_ID': int(p), 'ESTATUS': 'P', 'IMPORTE_NETO': round(imp, 2), 'TOTAL_IMPUESTOS': round(imp * .16, 2)}))});")
    for i, (a, u) in enumerate(lineas):
        sql.append(f"INSERT INTO ms_raw (base, tabla, pk, datos) VALUES ({q(B)}, 'DOCTOS_CM_DET', '{did}-{i}', "
                   f"{q(json.dumps({'DOCTO_CM_DET_ID': did * 10 + i, 'DOCTO_CM_ID': did, 'ARTICULO_ID': a, 'UNIDADES': u, 'PRECIO_UNITARIO': precio[a], 'PRECIO_TOTAL_NETO': round(precio[a] * u, 2)}))});")
    if folio != 77:  # recibidas: recepción R ligada a la OC
        rid = 7000 + folio
        sql.append(f"INSERT INTO ms_raw (base, tabla, pk, fecha, datos) VALUES ({q(B)}, 'DOCTOS_CM', '{rid}', '{f}', "
                   f"{q(json.dumps({'DOCTO_CM_ID': rid, 'TIPO_DOCTO': 'R', 'FOLIO': 'R%07d' % folio, 'FECHA': f, 'PROVEEDOR_ID': int(p), 'ESTATUS': 'N'}))});")
        for i, (a, u) in enumerate(lineas):
            sql.append(f"INSERT INTO ms_raw (base, tabla, pk, datos) VALUES ({q(B)}, 'DOCTOS_CM_DET', '{rid}-{i}', "
                       f"{q(json.dumps({'DOCTO_CM_ID': rid, 'ARTICULO_ID': a, 'UNIDADES': u}))});")
        sql.append(f"INSERT INTO ms_raw (base, tabla, pk, datos) VALUES ({q(B)}, 'DOCTOS_CM_LIGAS', '{did}-{rid}', "
                   f"{q(json.dumps({'DOCTO_CM_FTE_ID': did, 'DOCTO_CM_DEST_ID': rid}))});")

# Casos nuevos: servicio y VARIOS (se vendieron pero no son mercancía), tonelada sin venta (presentación del saco),
# existencia negativa en otro almacén, OC parcial (llegó una parte) y OC atrasada (sin recepción).
extra = [(30, 'FLETE', 'SERVICIO DE FLETE A DOMICILIO', 'Servicio', 150), (31, 'VARIOS', 'VARIOS', 'Pieza', 10),
         (32, 'CEM50TON', 'TONELADA CEMENTO GRIS TOLTECA 50KG', 'Tonelada', 4800)]
for a in extra:
    sql.append(f"INSERT INTO ms_articulos (base, articulo_id, clave, nombre, estatus, unidad, linea, grupo, precio_lista, costo_ultimo) VALUES "
               f"({q(B)}, {a[0]}, {q(a[1])}, {q(a[2])}, 'A', {q(a[3])}, 'MATERIALES', '', {a[4]}, {a[4] * 0.7});")
for i, (a, u) in enumerate([(30, 1), (31, 3)] * 40):
    docto += 1
    f = date(2026, 4, 1) + timedelta(days=i * 4)
    sql.append(f"INSERT INTO ms_ventas VALUES ({q(B)}, 'PV', {docto}, 'V', 'N', 'T{docto}', '{f}', '10:00', 'PUBLICO', 'GENERAL', {u * 5000}, 0, NULL);")
    sql.append(f"INSERT INTO ms_ventas_det VALUES ({q(B)}, 'PV', {det}, {docto}, 'X', {a}, 'X', {u}, 5000, {u * 5000});")
    det += 1
sql.append(f"INSERT INTO ms_existencias (base, articulo_id, almacen_id, almacen, clave, articulo, existencia, valor) VALUES ({q(B)}, 6, 2, 'BODEGA', 'TPLUS25', 'TUBO', -3, 0);")
for folio, f, p, a, u, rec in [(90, '2026-10-02', '15', 11, 50, 20), (91, '2026-09-01', '16', 21, 5, 0)]:
    did, rid = 5000 + folio, 7000 + folio
    sql.append(f"INSERT INTO ms_raw (base, tabla, pk, fecha, datos) VALUES ({q(B)}, 'DOCTOS_CM', '{did}', '{f}', "
               f"{q(json.dumps({'DOCTO_CM_ID': did, 'TIPO_DOCTO': 'O', 'FOLIO': 'O%07d' % folio, 'FECHA': f, 'PROVEEDOR_ID': int(p), 'ESTATUS': 'P', 'IMPORTE_NETO': u * 10}))});")
    sql.append(f"INSERT INTO ms_raw (base, tabla, pk, datos) VALUES ({q(B)}, 'DOCTOS_CM_DET', '{did}-0', "
               f"{q(json.dumps({'DOCTO_CM_ID': did, 'ARTICULO_ID': a, 'UNIDADES': u, 'PRECIO_UNITARIO': 10, 'PRECIO_TOTAL_NETO': u * 10}))});")
    if rec:
        sql.append(f"INSERT INTO ms_raw (base, tabla, pk, fecha, datos) VALUES ({q(B)}, 'DOCTOS_CM', '{rid}', '{f}', "
                   f"{q(json.dumps({'DOCTO_CM_ID': rid, 'TIPO_DOCTO': 'R', 'FOLIO': 'R%07d' % folio, 'FECHA': f, 'PROVEEDOR_ID': int(p), 'ESTATUS': 'N'}))});")
        sql.append(f"INSERT INTO ms_raw (base, tabla, pk, datos) VALUES ({q(B)}, 'DOCTOS_CM_DET', '{rid}-0', {q(json.dumps({'DOCTO_CM_ID': rid, 'ARTICULO_ID': a, 'UNIDADES': rec}))});")
        sql.append(f"INSERT INTO ms_raw (base, tabla, pk, datos) VALUES ({q(B)}, 'DOCTOS_CM_LIGAS', '{did}-{rid}', "
                   f"{q(json.dumps({'DOCTO_CM_FTE_ID': did, 'DOCTO_CM_DEST_ID': rid}))});")

# OC O92: la recepción se capturó SIN ligarla a la OC (Microsip dice 0 por recibir). OC O93: Microsip trae UNIDADES_A_REC = 0.
sql.append(f"INSERT INTO ms_raw (base, tabla, pk, fecha, datos) VALUES ({q(B)}, 'DOCTOS_CM', '5092', '2026-09-01', "
           f"{q(json.dumps({'DOCTO_CM_ID': 5092, 'TIPO_DOCTO': 'O', 'FOLIO': 'O0000092', 'FECHA': '2026-09-01', 'PROVEEDOR_ID': 13, 'ESTATUS': 'P', 'IMPORTE_NETO': 50}))});")
sql.append(f"INSERT INTO ms_raw (base, tabla, pk, datos) VALUES ({q(B)}, 'DOCTOS_CM_DET', '5092-0', {q(json.dumps({'DOCTO_CM_ID': 5092, 'ARTICULO_ID': 13, 'UNIDADES': 5, 'PRECIO_UNITARIO': 10}))});")
sql.append(f"INSERT INTO ms_raw (base, tabla, pk, fecha, datos) VALUES ({q(B)}, 'DOCTOS_CM', '7092', '2026-09-04', "
           f"{q(json.dumps({'DOCTO_CM_ID': 7092, 'TIPO_DOCTO': 'R', 'FOLIO': 'R0000092', 'FECHA': '2026-09-04', 'PROVEEDOR_ID': 13, 'ESTATUS': 'N'}))});")
sql.append(f"INSERT INTO ms_raw (base, tabla, pk, datos) VALUES ({q(B)}, 'DOCTOS_CM_DET', '7092-0', {q(json.dumps({'DOCTO_CM_ID': 7092, 'ARTICULO_ID': 13, 'UNIDADES': 5}))});")
sql.append(f"INSERT INTO ms_raw (base, tabla, pk, fecha, datos) VALUES ({q(B)}, 'DOCTOS_CM', '5093', '2026-09-01', "
           f"{q(json.dumps({'DOCTO_CM_ID': 5093, 'TIPO_DOCTO': 'O', 'FOLIO': 'O0000093', 'FECHA': '2026-09-01', 'PROVEEDOR_ID': 10, 'ESTATUS': 'P', 'IMPORTE_NETO': 40}))});")
sql.append(f"INSERT INTO ms_raw (base, tabla, pk, datos) VALUES ({q(B)}, 'DOCTOS_CM_DET', '5093-0', "
           f"{q(json.dumps({'DOCTO_CM_ID': 5093, 'ARTICULO_ID': 9, 'UNIDADES': 4, 'UNIDADES_REC_DEV': 4, 'UNIDADES_A_REC': 0, 'PRECIO_UNITARIO': 10}))});")

# Recepción SIN ligar de CLAVO25 después de la OC parcial O90 (ya ligada): Microsip la sigue dando como pendiente, no debe descontarse.
sql.append(f"INSERT INTO ms_raw (base, tabla, pk, fecha, datos) VALUES ({q(B)}, 'DOCTOS_CM', '7094', '2026-10-03', "
           f"{q(json.dumps({'DOCTO_CM_ID': 7094, 'TIPO_DOCTO': 'R', 'FOLIO': 'R0000094', 'FECHA': '2026-10-03', 'PROVEEDOR_ID': 15, 'ESTATUS': 'N'}))});")
sql.append(f"INSERT INTO ms_raw (base, tabla, pk, datos) VALUES ({q(B)}, 'DOCTOS_CM_DET', '7094-0', {q(json.dumps({'DOCTO_CM_ID': 7094, 'ARTICULO_ID': 11, 'UNIDADES': 30}))});")
# OC O95 con UNIDADES_REC_DEV de Microsip (5 de 20 recibidos) y sin ligas: por recibir = 15.
sql.append(f"INSERT INTO ms_raw (base, tabla, pk, fecha, datos) VALUES ({q(B)}, 'DOCTOS_CM', '5095', '2026-10-04', "
           f"{q(json.dumps({'DOCTO_CM_ID': 5095, 'TIPO_DOCTO': 'O', 'FOLIO': 'O0000095', 'FECHA': '2026-10-04', 'PROVEEDOR_ID': 13, 'ESTATUS': 'P', 'IMPORTE_NETO': 200}))});")
sql.append(f"INSERT INTO ms_raw (base, tabla, pk, datos) VALUES ({q(B)}, 'DOCTOS_CM_DET', '5095-0', "
           f"{q(json.dumps({'DOCTO_CM_ID': 5095, 'ARTICULO_ID': 14, 'UNIDADES': 20, 'UNIDADES_REC_DEV': 5, 'PRECIO_UNITARIO': 10}))});")

# OC O96 cancelada en Microsip (trae usuario de cancelación aunque el estatus no diga C): no debe contar.
sql.append(f"INSERT INTO ms_raw (base, tabla, pk, fecha, datos) VALUES ({q(B)}, 'DOCTOS_CM', '5096', '2026-08-20', "
           f"{q(json.dumps({'DOCTO_CM_ID': 5096, 'TIPO_DOCTO': 'O', 'FOLIO': 'O0000096', 'FECHA': '2026-08-20', 'PROVEEDOR_ID': 16, 'ESTATUS': 'P', 'USUARIO_CANCELACION': 'SYSDBA', 'IMPORTE_NETO': 2000}))});")
sql.append(f"INSERT INTO ms_raw (base, tabla, pk, datos) VALUES ({q(B)}, 'DOCTOS_CM_DET', '5096-0', {q(json.dumps({'DOCTO_CM_ID': 5096, 'ARTICULO_ID': 21, 'UNIDADES': 200, 'PRECIO_UNITARIO': 10}))});")

# OC O97 copiada de Microsip el 02/08 y nunca más (como la O51 que se canceló después): no se sabe si sigue viva, no cuenta.
sql.append(f"INSERT INTO ms_raw (base, tabla, pk, fecha, datos, actualizado) VALUES ({q(B)}, 'DOCTOS_CM', '5097', '2026-08-01', "
           f"{q(json.dumps({'DOCTO_CM_ID': 5097, 'TIPO_DOCTO': 'O', 'FOLIO': 'O0000097', 'FECHA': '2026-08-01', 'PROVEEDOR_ID': 10, 'ESTATUS': 'P', 'IMPORTE_NETO': 70}))}, '2026-08-02 10:00');")
sql.append(f"INSERT INTO ms_raw (base, tabla, pk, datos, actualizado) VALUES ({q(B)}, 'DOCTOS_CM_DET', '5097-0', {q(json.dumps({'DOCTO_CM_ID': 5097, 'ARTICULO_ID': 10, 'UNIDADES': 7, 'PRECIO_UNITARIO': 10}))}, '2026-08-02 10:00');")

# Pedidos de clientes (VE tipo P): uno pendiente de surtir (60 sacos de CEM50) y otro ya remisionado (ligado): solo cuenta el primero.
sql.append(f"INSERT INTO ms_ventas VALUES ({q(B)}, 'VE', 990001, 'P', 'P', 'P0009001', '2026-10-05', '10:00', 'OBRA', 'GENERAL', 14400, 0, NULL);")
sql.append(f"INSERT INTO ms_ventas_det VALUES ({q(B)}, 'VE', 990001, 990001, 'CEM50', 2, 'CEMENTO', 60, 240, 14400);")
sql.append(f"INSERT INTO ms_ventas VALUES ({q(B)}, 'VE', 990002, 'P', 'P', 'P0009002', '2026-10-04', '10:00', 'OBRA', 'GENERAL', 2400, 0, NULL);")
sql.append(f"INSERT INTO ms_ventas_det VALUES ({q(B)}, 'VE', 990002, 990002, 'CEM50', 2, 'CEMENTO', 10, 240, 2400);")
sql.append(f"INSERT INTO ms_raw (base, tabla, pk, datos) VALUES ({q(B)}, 'DOCTOS_VE_LIGAS', '990002-1', {q(json.dumps({'DOCTO_VE_FTE_ID': 990002, 'DOCTO_VE_DEST_ID': 990003}))});")

subprocess.run(PSQL, input='\n'.join(sql), text=True, check=True)
print('ok', len(sql), 'sentencias')
