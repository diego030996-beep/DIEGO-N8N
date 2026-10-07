"""Arma una base de prueba con los casos reales exportados de Microsip (casos_planeador.xlsx).
Uso: python3 compras/pruebas/casos_reales.py ruta/al/casos_planeador.xlsx   (crea la base "casos" en el Postgres de prueba)
El Excel NO se guarda en el repositorio: tiene datos del negocio."""
import calendar
import json
import subprocess
import sys
from datetime import date, timedelta

import openpyxl

PSQL = ['psql', '-h', '/var/tmp/pgc', '-p', '5544', '-U', 'postgres', '-q', '-v', 'ON_ERROR_STOP=1']
B = 'LOMAS AJUSCO'
q = lambda s: 'NULL' if s is None else "'" + str(s).replace("'", "''") + "'"

wb = openpyxl.load_workbook(sys.argv[1], data_only=True)
rows = list(wb.worksheets[0].iter_rows(values_only=True))
H = rows[0]
casos = [dict(zip(H, r)) for r in rows[1:]]

subprocess.run(PSQL + ['-d', 'postgres', '-c', 'DROP DATABASE IF EXISTS casos'], check=True)
subprocess.run(PSQL + ['-d', 'postgres', '-c', 'CREATE DATABASE casos'], check=True)
ddl = open(__file__.replace('casos_reales.py', 'datos_prueba.py')).read()
ddl = ddl[ddl.index('ddl = """') + 9:]
ddl = ddl[:ddl.index('"""')].replace('DROP SCHEMA public CASCADE; CREATE SCHEMA public;', '')
sql = [ddl, "INSERT INTO tablero_acceso VALUES ('k-admin', 'admin', true) ON CONFLICT DO NOTHING;"]

arts, provs, nid = {}, {}, [1000]
def art_id(clave, nombre=None, unidad=None, linea=None):
    if clave not in arts:
        nid[0] += 1
        arts[clave] = dict(id=nid[0], clave=clave, nombre=nombre or clave, unidad=unidad, linea=linea)
    a = arts[clave]
    for k, v in (('nombre', nombre), ('unidad', unidad), ('linea', linea)):
        if v and (a[k] in (None, clave) or k != 'nombre'):
            a[k] = v
    return a['id']
def prov_id(nombre):
    if nombre not in provs:
        provs[nombre] = str(100 + len(provs))
    return provs[nombre]

docto, det, vistos, compras_vistas, cm_id = [5000], [1], set(), set(), [9000]
for c in casos:
    if c['clave']:
        aid = art_id(c['clave'], c['producto'], c['unidad'], c['linea'])
        if c['clave'] in vistos:
            continue
        vistos.add(c['clave'])
        for x in json.loads(c['existencia_por_almacen'] or '[]'):
            sql.append(f"INSERT INTO ms_existencias (base, articulo_id, almacen_id, almacen, clave, articulo, existencia) VALUES "
                       f"({q(B)}, {aid}, {1 if x['almacen'] == B else 2}, {q(x['almacen'])}, {q(c['clave'])}, {q(c['producto'])}, {x['existencia']});")
        # ventas: cada renglón mensual se reparte en sus tickets dentro del mes
        for v in json.loads(c['ventas_por_mes'] or '[]'):
            org, tipo = v['documento'].split('-')
            y, m = map(int, v['mes'].split('-'))
            ult = min(calendar.monthrange(y, m)[1], 6 if (y, m) == (2026, 10) else 31)
            n = max(int(v['tickets']), 1)
            for i in range(n):
                docto[0] += 1
                d = date(y, m, 1 + (i * (ult - 1)) // max(n - 1, 1)) if n > 1 else date(y, m, min(15, ult))
                u = round(v['unidades'] / n, 4)
                sql.append(f"INSERT INTO ms_ventas (base, origen, docto_id, tipo, estatus, folio, fecha, importe, impuestos) VALUES "
                           f"({q(B)}, '{org}', {docto[0]}, '{tipo}', 'N', 'X{docto[0]}', '{d}', {round(v['importe'] / n, 2)}, 0);")
                sql.append(f"INSERT INTO ms_ventas_det (base, origen, det_id, docto_id, clave, articulo_id, articulo, unidades, importe) VALUES "
                           f"({q(B)}, '{org}', {det[0]}, {docto[0]}, {q(c['clave'])}, {aid}, {q(c['producto'])}, {u}, {round(v['importe'] / n, 2)});")
                det[0] += 1
        if c['ajuste_manual']:
            aj = json.loads(c['ajuste_manual'])
            sql.append(f"CREATE TABLE IF NOT EXISTS compras_articulos (base TEXT NOT NULL, articulo_id BIGINT NOT NULL, proveedor_id TEXT, clase TEXT, empaque NUMERIC,"
                       f" minimo NUMERIC, maximo NUMERIC, excluir BOOLEAN NOT NULL DEFAULT false, nota TEXT, por TEXT, actualizado TIMESTAMPTZ NOT NULL DEFAULT now(),"
                       f" PRIMARY KEY (base, articulo_id));")
            sql.append(f"INSERT INTO compras_articulos (base, articulo_id, excluir, nota, por) VALUES ({q(B)}, {aid}, {str(bool(aj['excluir'])).lower()}, {q(aj['nota'])}, 'exportado') ON CONFLICT DO NOTHING;")
        for x in json.loads(c['compras_180_dias'] or '[]'):
            key = (x['folio'], c['clave'])
            if key in compras_vistas:
                continue
            compras_vistas.add(key)
            tipo = {'orden de compra': 'O', 'recepción': 'R', 'compra': 'C'}[x['tipo']]
            did = abs(hash(x['folio'])) % 10**8
            pid = prov_id(x['proveedor'])
            sql.append(f"INSERT INTO ms_raw (base, tabla, pk, fecha, datos) VALUES ({q(B)}, 'DOCTOS_CM', '{did}', '{x['fecha']}', "
                       f"{q(json.dumps({'DOCTO_CM_ID': did, 'TIPO_DOCTO': tipo, 'FOLIO': x['folio'], 'FECHA': x['fecha'], 'PROVEEDOR_ID': int(pid), 'ESTATUS': 'N'}))}) ON CONFLICT DO NOTHING;")
            cm_id[0] += 1
            sql.append(f"INSERT INTO ms_raw (base, tabla, pk, datos) VALUES ({q(B)}, 'DOCTOS_CM_DET', '{cm_id[0]}', "
                       f"{q(json.dumps({'DOCTO_CM_ID': did, 'ARTICULO_ID': aid, 'UNIDADES': x['unidades'], 'PRECIO_UNITARIO': x['precio_unitario']}))});")
    elif c['folio']:   # OC sin recibir
        did = abs(hash(c['folio'])) % 10**8
        pid = prov_id(c['proveedor'])
        sql.append(f"INSERT INTO ms_raw (base, tabla, pk, fecha, datos) VALUES ({q(B)}, 'DOCTOS_CM', '{did}', '{c['fecha']}', "
                   f"{q(json.dumps({'DOCTO_CM_ID': did, 'TIPO_DOCTO': 'O', 'FOLIO': c['folio'], 'FECHA': str(c['fecha'])[:10], 'PROVEEDOR_ID': int(pid), 'ESTATUS': 'P'}))}) ON CONFLICT DO NOTHING;")
        for l in json.loads(c['detalle'] or '[]'):
            aid = art_id(l['clave'], l['articulo'])
            cm_id[0] += 1
            sql.append(f"INSERT INTO ms_raw (base, tabla, pk, datos) VALUES ({q(B)}, 'DOCTOS_CM_DET', '{cm_id[0]}', "
                       f"{q(json.dumps({'DOCTO_CM_ID': did, 'ARTICULO_ID': aid, 'UNIDADES': l['pedido']}))});")

for a in arts.values():
    sql.append(f"INSERT INTO ms_articulos (base, articulo_id, clave, nombre, estatus, unidad, linea, grupo) VALUES "
               f"({q(B)}, {a['id']}, {q(a['clave'])}, {q(a['nombre'])}, 'A', {q(a['unidad'])}, {q(a['linea'])}, '') ON CONFLICT DO NOTHING;")
for n, i in provs.items():
    sql.append(f"INSERT INTO ms_raw (base, tabla, pk, datos) VALUES ({q(B)}, 'PROVEEDORES', '{i}', {q(json.dumps({'PROVEEDOR_ID': int(i), 'NOMBRE': n}))});")
# ligas OC → recepción: la recepción del mismo proveedor y artículo hecha 0 a 5 días después de la OC (como haría Microsip)
sql.append(f"""INSERT INTO ms_raw (base, tabla, pk, datos)
SELECT DISTINCT '{B}', 'DOCTOS_CM_LIGAS', o.pk || '-' || r.pk, jsonb_build_object('DOCTO_CM_FTE_ID', o.pk::bigint, 'DOCTO_CM_DEST_ID', r.pk::bigint)
FROM ms_raw o JOIN ms_raw r ON r.tabla = 'DOCTOS_CM' AND r.datos->>'TIPO_DOCTO' = 'R' AND r.datos->>'PROVEEDOR_ID' = o.datos->>'PROVEEDOR_ID'
  AND r.fecha BETWEEN o.fecha AND o.fecha + 5
WHERE o.tabla = 'DOCTOS_CM' AND o.datos->>'TIPO_DOCTO' = 'O' AND o.datos->>'ESTATUS' = 'N'
  AND EXISTS (SELECT 1 FROM ms_raw od JOIN ms_raw rd ON rd.tabla = 'DOCTOS_CM_DET' AND rd.datos->>'DOCTO_CM_ID' = r.pk AND rd.datos->>'ARTICULO_ID' = od.datos->>'ARTICULO_ID'
              WHERE od.tabla = 'DOCTOS_CM_DET' AND od.datos->>'DOCTO_CM_ID' = o.pk)
;""")
sql.append('ANALYZE;')
subprocess.run(PSQL + ['-d', 'casos'], input='\n'.join(sql), text=True, check=True)
print('ok:', len(arts), 'artículos,', len(provs), 'proveedores,', docto[0] - 5000, 'tickets')
