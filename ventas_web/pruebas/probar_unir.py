"""Prueba «Sugerir qué chats unir» (V8.65) contra un Postgres de prueba.

Uso: python3 ventas_web/pruebas/probar_unir.py
Crea la base vw_prueba, corre «Crear tablas y funciones» del flujo (fallan solo las partes que piden tablas de Microsip,
que aquí no hay) y revisa las sugerencias, unir, «No es el mismo», permisos y el cron.
"""
import json
import os
import subprocess

AQUI = os.path.dirname(os.path.abspath(__file__))
FLUJO = os.path.join(os.path.dirname(AQUI), 'n8n', 'Ventas web.json')
PG = ['psql', '-h', '/var/tmp/pgc', '-p', '5544', '-U', 'postgres']
DB = 'vw_prueba'


def sql(q, db=DB):
    r = subprocess.run(PG + ['-d', db, '-At', '-v', 'ON_ERROR_STOP=1', '-c', q], text=True, capture_output=True)
    if r.returncode:
        raise SystemExit(r.stderr)
    return r.stdout.strip()


def api(acc, tok='tokA', **p):
    j = json.dumps(dict(p, accion=acc, s=tok), ensure_ascii=False).replace("'", "''")
    return json.loads(sql(f"SELECT vw_api_wch('{j}'::jsonb, 'x')"))


def main():
    sql(f'DROP DATABASE IF EXISTS {DB}', 'postgres')
    sql(f'CREATE DATABASE {DB}', 'postgres')
    q = next(n for n in json.load(open(FLUJO, encoding='utf-8'))['nodes'] if n['name'] == 'Crear tablas y funciones')['parameters']['query']
    subprocess.run(PG + ['-d', DB, '-q'], input=q, text=True, capture_output=True)
    sql("""
INSERT INTO vw_usuarios (usuario, nombre, activo, es_admin, permisos) VALUES ('admin','Admin',true,true,'{}'), ('vend','Vendedor',true,false,'{"chat_supertank":true}');
INSERT INTO vw_sesiones (token_hash, usuario_id, expira) SELECT vw_hash('tokA'), id, now()+interval '1 day' FROM vw_usuarios WHERE usuario='admin';
INSERT INTO vw_sesiones (token_hash, usuario_id, expira) SELECT vw_hash('tokV'), id, now()+interval '1 day' FROM vw_usuarios WHERE usuario='vend';
UPDATE wch_canales SET phone_number_id='pn1' WHERE nombre='Super Tank';
INSERT INTO wch_canales (tipo, marca, nombre, phone_number_id) VALUES ('whatsapp','supertank','Super Tank 2','pn2'), ('messenger','supertank','Facebook ST',NULL),
  ('telegram','supertank','Telegram ST',NULL), ('whatsapp','construrama','Construrama WA','pn3');
INSERT INTO wch_conversaciones (id, canal_id, marca, telefono, nombre, ultimo_en) VALUES
 (1,(SELECT id FROM wch_canales WHERE nombre='Super Tank'),'supertank','5512345678','Juan Pérez López', now()-interval '1 day'),
 (2,(SELECT id FROM wch_canales WHERE nombre='Super Tank 2'),'supertank','5215512345678',NULL, now()-interval '2 day'),
 (3,(SELECT id FROM wch_canales WHERE nombre='Facebook ST'),'supertank','24681357913579','Maria Gonzalez', now()),
 (4,(SELECT id FROM wch_canales WHERE nombre='Super Tank'),'supertank','5587654321','Mari', now()-interval '3 day'),
 (5,(SELECT id FROM wch_canales WHERE nombre='Facebook ST'),'supertank','99999999999999','Juan Perez Lopez', now()-interval '5 day'),
 (6,(SELECT id FROM wch_canales WHERE nombre='Telegram ST'),'supertank','1234567890','Pedro', now()),
 (7,(SELECT id FROM wch_canales WHERE nombre='Super Tank 2'),'supertank','5500001111','Ana', now()),
 (8,(SELECT id FROM wch_canales WHERE nombre='Construrama WA'),'construrama','5512345678','Juan', now());
SELECT setval('wch_conversaciones_id_seq', 20);
INSERT INTO wch_mensajes (conv_id, dir, origen, texto) SELECT 1,'in','cliente','hola' FROM generate_series(1,3);
INSERT INTO wch_mensajes (conv_id, dir, origen, texto) SELECT 2,'in','cliente','precio' FROM generate_series(1,10);
INSERT INTO wch_mensajes (conv_id, dir, origen, texto) SELECT 3,'in','cliente','quiero tinaco' FROM generate_series(1,7);
INSERT INTO wch_mensajes (conv_id, dir, origen, texto) VALUES (3,'in','cliente','mi cel es (55) 8765-4321'), (4,'in','cliente','ok'), (4,'out','sistema','aviso'),
  (7,'in','cliente','mi número 1234567890');
INSERT INTO wch_usuario_canales SELECT id, (SELECT id FROM wch_canales WHERE nombre='Super Tank 2') FROM vw_usuarios WHERE usuario='vend';
""")
    l = api('wch_unir_sug', refrescar='si')['lista']
    par = {(s['principal']['id'], s['otro']['id']): s for s in l}
    assert set(par) == {(2, 1), (4, 3), (1, 5)}, par.keys()                  # teléfono, teléfono escrito en Facebook, nombre
    assert par[(2, 1)]['razon'] == 'mismo teléfono' and '10 contra 3' in par[(2, 1)]['por_que']   # queda en el de más plática
    assert par[(4, 3)]['razon'] == 'dio su teléfono en el chat' and 'solo por WhatsApp' in par[(4, 3)]['por_que']
    assert [s['razon'] for s in l] == ['mismo teléfono', 'dio su teléfono en el chat', 'mismo nombre']
    assert api('wch_unir_sug', tok='tokV')['lista'] == []                    # no ve los dos chats de ninguna pareja
    assert not api('wch_unir_descartar', tok='tokV', a=3, b=4)['ok']
    c = api('wch_unir_cand', conv_id=4)
    assert c['lista'][0]['id'] == 3 and c['lista'][0]['sugerido'] and c['yo_msgs'] == 1
    assert api('wch_unir', principal=2, otro=1)['ok']
    assert api('wch_unir_descartar', a=4, b=3)['ok']
    l = api('wch_unir_sug', refrescar='si')['lista']
    assert [(s['principal']['id'], s['otro']['id'], s['razon']) for s in l] == [(2, 5, 'mismo nombre')], l   # el nombre pasó al principal
    sql("INSERT INTO wch_conversaciones (id, canal_id, marca, telefono, nombre, ultimo_en) VALUES (21,(SELECT id FROM wch_canales WHERE nombre='Super Tank'),'supertank','525500001111','Ana R', now())")
    l = api('wch_unir_sug', conv_id=21)['lista']                             # chat nuevo: se ve sin esperar el cálculo de cada 15 min
    assert [(s['principal']['id'], s['otro']['id']) for s in l] == [(7, 21)], l
    assert int(sql('SELECT wch_unir_sug_cron()')) >= 1
    print('OK: sugerencias, principal por plática, permisos, unir, descartar, en vivo y cron')


if __name__ == '__main__':
    main()
