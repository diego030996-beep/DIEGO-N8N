"""Datos de prueba de producción: los de compras (ms_*) + tinacos de colores, polímeros, tapas y kits, y una recepción de polímero."""
import json
import os
import subprocess
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
subprocess.run([sys.executable, os.path.join(AQUI, '..', '..', 'compras', 'pruebas', 'datos_prueba.py')], check=True, capture_output=True)
PSQL = ['psql', '-h', '/var/tmp/pgc', '-p', '5544', '-U', 'postgres', '-q', '-v', 'ON_ERROR_STOP=1']
B = 'LOMAS AJUSCO'
q = lambda s: "NULL" if s is None else "'" + str(s).replace("'", "''") + "'"
sql = [open(os.path.join(AQUI, '..', 'sql', 'esquema.sql')).read()]
arts = [  # id, clave, nombre, unidad, linea, precio, costo, existencia
    (40, 'T1100BE', 'TINACO 1100 LTS BEIGE', 'Pieza', 'TINACOS Y CISTERNAS', 2500, None, 3),
    (41, 'T1100BL', 'TINACO 1100 LTS BLANCO', 'Pieza', 'TINACOS Y CISTERNAS', 2500, None, 0),
    (42, 'T450N', 'TINACO 450 LTS NEGRO', 'Pieza', 'TINACOS Y CISTERNAS', 1300, None, 5),
    (50, 'POLN', 'POLIMERO NEGRO', 'Kilogramo', 'MATERIA PRIMA', 0, 32.5, 400),
    (51, 'POLBE', 'POLIMERO BEIGE', 'Kilogramo', 'MATERIA PRIMA', 0, 34.0, 60),
    (52, 'POLBL', 'POLIMERO BLANCO', 'Kilogramo', 'MATERIA PRIMA', 0, None, 100),
    (53, 'TAPA1100', 'TAPA TINACO 1100', 'Pieza', 'MATERIA PRIMA', 0, 85, 30),
    (54, 'KITTIN', 'KIT ACCESORIOS TINACO', 'Pieza', 'MATERIA PRIMA', 0, 120, 25),
]
for a in arts:
    sql.append(f"INSERT INTO ms_articulos (base, articulo_id, clave, nombre, estatus, unidad, linea, grupo, precio_lista, costo_ultimo) VALUES "
               f"({q(B)}, {a[0]}, {q(a[1])}, {q(a[2])}, 'A', {q(a[3])}, {q(a[4])}, '', {a[5]}, {'NULL' if a[6] is None else a[6]});")
    sql.append(f"INSERT INTO ms_existencias (base, articulo_id, almacen_id, almacen, clave, articulo, existencia, valor) VALUES ({q(B)}, {a[0]}, 1, 'GENERAL', {q(a[1])}, {q(a[2])}, {a[7]}, 0);")
# recepción de polímero negro (500 kg) y blanco (sin último costo en Microsip: el costo sale de esta compra)
for did, f, art, u, pu in [(8001, '2026-10-02', 50, 500, 32.5), (8002, '2026-10-03', 52, 200, 30.0)]:
    sql.append(f"INSERT INTO ms_raw (base, tabla, pk, fecha, datos) VALUES ({q(B)}, 'DOCTOS_CM', '{did}', '{f}', "
               f"{q(json.dumps({'DOCTO_CM_ID': did, 'TIPO_DOCTO': 'R', 'FOLIO': 'R%07d' % did, 'FECHA': f, 'PROVEEDOR_ID': 13, 'ESTATUS': 'N'}))});")
    sql.append(f"INSERT INTO ms_raw (base, tabla, pk, datos) VALUES ({q(B)}, 'DOCTOS_CM_DET', '{did}-0', "
               f"{q(json.dumps({'DOCTO_CM_ID': did, 'ARTICULO_ID': art, 'UNIDADES': u, 'PRECIO_UNITARIO': pu, 'PRECIO_TOTAL_NETO': u * pu}))});")
sql.append("UPDATE ms_articulos SET costo_ultimo = 1750 WHERE articulo_id = 16;")   # el tinaco negro de compras
subprocess.run(PSQL, input='\n'.join(sql), text=True, check=True)
print('ok')
