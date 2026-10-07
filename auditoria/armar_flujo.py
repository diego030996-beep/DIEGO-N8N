"""Genera el flujo de n8n "Auditoría de movimientos (Microsip)" listo para importar.

Uso:  python3 auditoria/armar_flujo.py
Lee pagina.html, n8n/*.js, n8n/defaults.json y sql/*.sql y escribe n8n/Auditoría de movimientos (Microsip).json
"""
import json
import os
import uuid

from sqlops import todas, leer as leer_sql

AQUI = os.path.dirname(os.path.abspath(__file__))
SALIDA = os.path.join(AQUI, 'n8n', 'Auditoría de movimientos (Microsip).json')
CRED = {'postgres': {'id': 'nkJBZ7x5YYLa9MRx', 'name': 'Postgres account'}}
URL_N8N = 'https://ai.adhesipro.com.mx'
NO_CACHE = {'name': 'Cache-Control', 'value': 'no-store'}
# En el repositorio van marcadores; la copia que se entrega puede llevar los datos reales con variables de entorno.
BOT = {'token': os.environ.get('AUD_TG_TOKEN', 'PEGA_AQUI_EL_TOKEN_DEL_BOT_DE_AUDITORIA'),
       'chat': os.environ.get('AUD_TG_CHAT', 'PEGA_AQUI_EL_CHAT_ID_DEL_GRUPO_DE_CHOFERES'),
       'secreto': os.environ.get('AUD_TG_SECRETO', 'CAMBIA_ESTA_CLAVE_SECRETA')}
SALIDA = os.environ.get('AUD_SALIDA', SALIDA)


def leer(*ruta):
    with open(os.path.join(AQUI, *ruta), encoding='utf-8') as f:
        return f.read()


def uid(nombre):
    return str(uuid.uuid5(uuid.NAMESPACE_URL, 'auditoria-mov/' + nombre))


def nodo(nombre, tipo, version, pos, params, **extra):
    n = {'parameters': params, 'id': uid(nombre), 'name': nombre, 'type': tipo, 'typeVersion': version, 'position': pos}
    n.update(extra)
    return n


def si(nombre, pos, expr, op='true'):
    return nodo(nombre, 'n8n-nodes-base.if', 2.2, pos, {
        'conditions': {'options': {'caseSensitive': True, 'leftValue': '', 'typeValidation': 'loose', 'version': 2},
                       'conditions': [{'id': uid(nombre + '/c'), 'leftValue': expr, 'rightValue': '',
                                       'operator': {'type': 'boolean', 'operation': op, 'singleValue': True}}],
                       'combinator': 'and'}, 'options': {}})


def pg(nombre, pos, query, params=None, **extra):
    opts = {'queryReplacement': params} if params else {}
    return nodo(nombre, 'n8n-nodes-base.postgres', 2.5, pos, {'operation': 'executeQuery', 'query': query, 'options': opts}, credentials=CRED, **extra)


def armar():
    defaults = json.loads(leer('n8n', 'defaults.json'))
    sql = todas()
    preparar = (leer('n8n', 'preparar.js').replace('__SQL__', json.dumps({k: v for k, v in sql.items() if k != 'avisos'}, ensure_ascii=False))
                .replace('__DEF__', json.dumps(defaults, ensure_ascii=False)))
    esquema = leer_sql('esquema')
    acceso_sql = (esquema + "\n"
        "SELECT coalesce((SELECT rol FROM tablero_acceso WHERE token = $1 AND activo AND rol IN ('admin', 'auditora') LIMIT 1),\n"
        "                (SELECT 'empleado' FROM mov_empleado WHERE token = $1 AND activo LIMIT 1)) AS rol,\n"
        "       (SELECT nombre FROM mov_empleado WHERE token = $1 AND activo LIMIT 1) AS nombre;")
    foto_sql = (esquema + "\n"
        "SELECT c.foto FROM mov_comprobante c JOIN mov_registro g ON g.id = c.registro_id\n"
        "WHERE c.id = NULLIF(regexp_replace($2, '[^0-9]', '', 'g'), '')::bigint\n"
        "  AND (EXISTS (SELECT 1 FROM tablero_acceso WHERE token = $1 AND activo AND rol IN ('admin', 'auditora'))\n"
        "       OR EXISTS (SELECT 1 FROM mov_empleado e WHERE e.token = $1 AND e.activo AND e.nombre = g.empleado));")
    foto_js = ("// Devuelve el comprobante como imagen\n"
               "const f = String(($input.first().json || {}).foto || '');\n"
               "if (!f) return [{ json: { falta: true } }];\n"
               "return [{ json: { falta: false }, binary: { data: { data: f, mimeType: 'image/jpeg', fileName: 'comprobante.jpg', fileExtension: 'jpg' } } }];\n")
    avisos_sql = esquema + "\n" + sql['avisos']
    tablero_sql = esquema + "\n" + sql['tablero']
    def_txt = json.dumps(json.dumps(defaults, ensure_ascii=False), ensure_ascii=False)
    avisos_params = "={{ ['', " + def_txt + ", 'Telegram', '{\"_rol\":\"admin\"}', ''] }}"
    resumen_params = "={{ ['', " + def_txt + ", 'Telegram', '{\"_rol\":\"admin\",\"ver\":\"problemas\"}', ''] }}"
    tg_sql = {k: (esquema + "\n" + sql[k]) for k in ('tablero', 'buscar', 'tg_registrar', 'detalle')}
    tg_leer = leer('n8n', 'tg_leer.js').replace('__SQL__', json.dumps(tg_sql, ensure_ascii=False)).replace('__DEF__', json.dumps(defaults, ensure_ascii=False))
    marcar_sql = "INSERT INTO mov_aviso (clave) SELECT unnest($1::text[]) ON CONFLICT (clave) DO NOTHING;\nSELECT 1 AS ok;"
    tg_send = lambda nombre, pos, **extra: nodo(nombre, 'n8n-nodes-base.httpRequest', 4.2, pos, {
        'method': 'POST', 'url': "=https://api.telegram.org/bot{{ $('Configuración del bot').first().json.telegram_token }}/sendMessage",
        'sendBody': True, 'specifyBody': 'json',
        'jsonBody': '={{ JSON.stringify({ chat_id: $json.chat_id, text: $json.text, parse_mode: "HTML", disable_web_page_preview: true, reply_parameters: $json.reply_parameters }) }}',
        'options': {}}, **extra)
    ligas_sql = (esquema + "\n"
        "INSERT INTO tablero_acceso (token, rol) SELECT replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''), v.r FROM (VALUES ('auditora'), ('admin')) AS v(r)\n"
        "WHERE NOT EXISTS (SELECT 1 FROM tablero_acceso a WHERE a.rol = v.r AND a.activo);\n"
        "SELECT (SELECT token FROM tablero_acceso WHERE rol = 'auditora' AND activo ORDER BY creado LIMIT 1) AS t_aud,\n"
        "       (SELECT token FROM tablero_acceso WHERE rol = 'admin' AND activo ORDER BY creado LIMIT 1) AS t_admin,\n"
        "       (SELECT coalesce(json_agg(json_build_object('nombre', nombre, 'token', token) ORDER BY nombre), '[]') FROM mov_empleado WHERE activo) AS empleados;")
    ligas_js = (
        "// Ligas de la auditoría. Los empleados se dan de alta desde la página (Empleados) con la liga de administrador.\n"
        "const cfg = $('Configuración (ligas)').first().json, a = $('Ligas').first().json;\n"
        "const url = String(cfg.url_n8n || '').replace(/\\/+$/, '') + '/webhook/auditoria-mov?k=';\n"
        "let E = a.empleados; if (typeof E === 'string') E = JSON.parse(E);\n"
        "const out = { administrador: url + a.t_admin, auditora: url + a.t_aud };\n"
        "for (const e of E || []) out['empleado ' + e.nombre] = url + e.token;\n"
        "return [{ json: out }];")
    nodes = [
        nodo('Página', 'n8n-nodes-base.webhook', 2, [0, -300], {'path': 'auditoria-mov', 'responseMode': 'responseNode', 'options': {}}, webhookId=uid('webhook/auditoria-mov')),
        nodo('Mostrar página', 'n8n-nodes-base.respondToWebhook', 1.1, [224, -300], {
            'respondWith': 'text', 'responseBody': leer('pagina.html'),
            'options': {'responseHeaders': {'entries': [{'name': 'Content-Type', 'value': 'text/html; charset=utf-8'}, NO_CACHE,
                                                        {'name': 'X-Robots-Tag', 'value': 'noindex'}, {'name': 'Referrer-Policy', 'value': 'no-referrer'}]}}}),
        nodo('API', 'n8n-nodes-base.webhook', 2, [0, -60], {'httpMethod': 'POST', 'path': 'auditoria-mov-api', 'responseMode': 'responseNode', 'options': {}},
             webhookId=uid('webhook/auditoria-mov-api')),
        pg('Acceso', [224, -60], acceso_sql, "={{ [ String(($('API').first().json.body || {}).k || '').slice(0, 128) ] }}"),
        nodo('Preparar', 'n8n-nodes-base.code', 2, [448, -60], {'jsCode': preparar}),
        si('¿Válido?', [672, -60], '={{ $json.ok === true }}'),
        pg('Consultar', [896, -140], '={{ $json.sql }}', '={{ $json.params }}', alwaysOutputData=True, onError='continueRegularOutput'),
        nodo('Armar respuesta', 'n8n-nodes-base.code', 2, [1120, -140], {'jsCode': leer('n8n', 'armar.js')}),
        nodo('Responder', 'n8n-nodes-base.respondToWebhook', 1.1, [1344, -60], {
            'respondWith': 'text', 'responseBody': '={{ JSON.stringify($json.respuesta) }}',
            'options': {'responseHeaders': {'entries': [{'name': 'Content-Type', 'value': 'application/json; charset=utf-8'}, NO_CACHE]}}}),
        # fotos de comprobantes
        nodo('Foto', 'n8n-nodes-base.webhook', 2, [0, 180], {'path': 'auditoria-mov-foto', 'responseMode': 'responseNode', 'options': {}}, webhookId=uid('webhook/auditoria-mov-foto')),
        pg('Buscar foto', [224, 180], foto_sql, "={{ [ String($('Foto').first().json.query.k || '').slice(0, 128), String($('Foto').first().json.query.id || '').slice(0, 20) ] }}", alwaysOutputData=True),
        nodo('Foto a imagen', 'n8n-nodes-base.code', 2, [448, 180], {'jsCode': foto_js}),
        si('¿Hay foto?', [672, 180], '={{ $json.falta }}', op='false'),
        nodo('Mostrar foto', 'n8n-nodes-base.respondToWebhook', 1.1, [896, 120], {'respondWith': 'binary', 'options': {'responseHeaders': {'entries': [
            {'name': 'Content-Type', 'value': 'image/jpeg'}, {'name': 'Cache-Control', 'value': 'private, max-age=3600'}]}}}),
        nodo('Sin foto', 'n8n-nodes-base.respondToWebhook', 1.1, [896, 260], {'respondWith': 'text', 'responseBody': 'No encontré ese comprobante o tu liga no tiene permiso.',
            'options': {'responseCode': 404, 'responseHeaders': {'entries': [{'name': 'Content-Type', 'value': 'text/plain; charset=utf-8'}, NO_CACHE]}}}),
        # bot de auditoría en el grupo de choferes: mensajes, avisos de cada hora, resumen del día
        nodo('Cómo conectar el bot', 'n8n-nodes-base.stickyNote', 1, [-420, 380], {'width': 380, 'height': 520, 'content':
            '## Bot de auditoría en el grupo de choferes\n'
            '1. En Telegram, con **@BotFather**: `/newbot` (ej. *Auditoría Construrama*). Copia el token.\n'
            '2. Con @BotFather: `/setprivacy` → escoge el bot → **Disable** (para que vea las fotos del grupo).\n'
            '3. Agrega el bot al **grupo de choferes**.\n'
            '4. Pega el token en **Configuración del bot** (el chat del grupo ya viene puesto).\n'
            '5. Guarda y **activa** el flujo; luego corre a mano **Conectar bot** (una sola vez).\n\n'
            '⚠️ **NO uses el token del bot de choferes**: ese bot ya recibe sus mensajes en otro flujo y "Conectar bot" se los quitaría.\n\n'
            'En el grupo: foto + `R-01842 500 P4509 block`, o responder con la foto a un aviso. `/pendientes`, `/folio R-01842`, `/ayuda`.'}),
        nodo('Telegram', 'n8n-nodes-base.webhook', 2, [0, 440], {'httpMethod': 'POST', 'path': 'auditoria-mov-tg', 'options': {}}, webhookId=uid('webhook/auditoria-mov-tg')),
        nodo('Cada hora', 'n8n-nodes-base.scheduleTrigger', 1.2, [0, 600], {'rule': {'interval': [{'field': 'cronExpression', 'expression': '5 8-22 * * *'}]}}),
        nodo('Resumen del día', 'n8n-nodes-base.scheduleTrigger', 1.2, [0, 760], {'rule': {'interval': [{'field': 'cronExpression', 'expression': '20 20 * * *'}]}}),
        nodo('Conectar bot', 'n8n-nodes-base.manualTrigger', 1, [0, 920], {}),
        nodo('Configuración del bot', 'n8n-nodes-base.set', 3.4, [224, 680], {'assignments': {'assignments': [
            {'id': uid('tg'), 'name': 'telegram_token', 'value': BOT['token'], 'type': 'string'},
            {'id': uid('chat'), 'name': 'chat_id', 'value': BOT['chat'], 'type': 'string'},
            {'id': uid('secreto'), 'name': 'secreto', 'value': BOT['secreto'], 'type': 'string'},
            {'id': uid('url2'), 'name': 'url_n8n', 'value': URL_N8N, 'type': 'string'}]}, 'options': {}}),
        nodo('Origen', 'n8n-nodes-base.code', 2, [448, 680], {'jsCode': leer('n8n', 'tg_origen.js')}),
        si('¿Mensaje del grupo?', [672, 440], "={{ $json.origen === 'telegram' }}"),
        si('¿Avisos?', [672, 600], "={{ $json.origen === 'avisos' }}"),
        si('¿Resumen?', [672, 760], "={{ $json.origen === 'resumen' }}"),
        # mensajes del grupo
        nodo('Leer mensaje', 'n8n-nodes-base.code', 2, [896, 360], {'jsCode': tg_leer}),
        si('¿Foto?', [1120, 360], "={{ $json.ruta === 'foto' }}"),
        nodo('Pedir archivo', 'n8n-nodes-base.httpRequest', 4.2, [1344, 220], {
            'url': "=https://api.telegram.org/bot{{ $('Configuración del bot').first().json.telegram_token }}/getFile?file_id={{ encodeURIComponent($json.file_id) }}", 'options': {}}),
        nodo('Bajar foto', 'n8n-nodes-base.httpRequest', 4.2, [1568, 220], {
            'url': "=https://api.telegram.org/file/bot{{ $('Configuración del bot').first().json.telegram_token }}/{{ $json.result.file_path }}",
            'options': {'response': {'response': {'responseFormat': 'file', 'outputPropertyName': 'data'}}}}),
        nodo('Foto a texto', 'n8n-nodes-base.code', 2, [1792, 220], {'jsCode': leer('n8n', 'tg_foto.js')}),
        pg('Guardar desde Telegram', [2016, 220], '={{ $json.sql }}', '={{ $json.params }}', alwaysOutputData=True, onError='continueRegularOutput'),
        nodo('Pedir estado', 'n8n-nodes-base.code', 2, [2240, 220], {'jsCode': leer('n8n', 'tg_estado.js')}),
        pg('Estado', [2464, 220], '={{ $json.sql }}', '={{ $json.params }}', alwaysOutputData=True, onError='continueRegularOutput'),
        nodo('Contestar foto', 'n8n-nodes-base.code', 2, [2688, 220], {'jsCode': leer('n8n', 'tg_responder.js')}),
        si('¿Comando?', [1344, 440], "={{ $json.ruta === 'comando' }}"),
        pg('Consultar comando', [1568, 380], '={{ $json.sql }}', '={{ $json.params }}', alwaysOutputData=True, onError='continueRegularOutput'),
        nodo('Contestar comando', 'n8n-nodes-base.code', 2, [1792, 380], {'jsCode': leer('n8n', 'tg_comando.js')}),
        nodo('Texto fijo', 'n8n-nodes-base.code', 2, [1568, 520], {'jsCode': "return [{ json: $input.first().json.envio }];"}),
        tg_send('Mandar al grupo', [2912, 440], onError='continueRegularOutput'),
        # avisos de cada hora
        pg('Pendientes de avisar', [896, 600], avisos_sql, avisos_params),
        nodo('Armar avisos', 'n8n-nodes-base.code', 2, [1120, 600], {'jsCode': leer('n8n', 'tg_avisos.js')}),
        tg_send('Mandar aviso', [1344, 600]),
        pg('Marcar avisados', [1568, 600], marcar_sql, "={{ [ '{' + $('Armar avisos').all().flatMap(i => i.json.claves).map(c => '\"' + c + '\"').join(',') + '}' ] }}", executeOnce=True),
        # resumen del día
        pg('Leer resumen', [896, 760], tablero_sql, resumen_params),
        nodo('Armar resumen', 'n8n-nodes-base.code', 2, [1120, 760], {'jsCode': leer('n8n', 'tg_resumen.js')}),
        tg_send('Mandar resumen', [1344, 760]),
        # conectar el bot (una vez)
        nodo('Datos del bot', 'n8n-nodes-base.code', 2, [896, 920], {'jsCode': leer('n8n', 'tg_conectar.js')}),
        nodo('Conectar webhook', 'n8n-nodes-base.httpRequest', 4.2, [1120, 920], {
            'method': 'POST', 'url': "=https://api.telegram.org/bot{{ $('Configuración del bot').first().json.telegram_token }}/setWebhook",
            'sendBody': True, 'specifyBody': 'json', 'jsonBody': '={{ JSON.stringify($json) }}', 'options': {}}),
        # ligas
        nodo('Ver ligas', 'n8n-nodes-base.manualTrigger', 1, [0, 680], {}),
        nodo('Configuración (ligas)', 'n8n-nodes-base.set', 3.4, [224, 680], {'assignments': {'assignments': [
            {'id': uid('url'), 'name': 'url_n8n', 'value': URL_N8N, 'type': 'string'}]}, 'options': {}}),
        pg('Ligas', [448, 680], ligas_sql),
        nodo('Ligas para abrir', 'n8n-nodes-base.code', 2, [672, 680], {'jsCode': ligas_js}),
    ]
    c = lambda *dest: {'main': [[{'node': d, 'type': 'main', 'index': 0} for d in rama] for rama in dest]}
    connections = {
        'Página': c(['Mostrar página']), 'API': c(['Acceso']), 'Acceso': c(['Preparar']), 'Preparar': c(['¿Válido?']),
        '¿Válido?': c(['Consultar'], ['Responder']), 'Consultar': c(['Armar respuesta']), 'Armar respuesta': c(['Responder']),
        'Foto': c(['Buscar foto']), 'Buscar foto': c(['Foto a imagen']), 'Foto a imagen': c(['¿Hay foto?']), '¿Hay foto?': c(['Mostrar foto'], ['Sin foto']),
        'Telegram': c(['Configuración del bot']), 'Cada hora': c(['Configuración del bot']), 'Resumen del día': c(['Configuración del bot']),
        'Conectar bot': c(['Configuración del bot']), 'Configuración del bot': c(['Origen']),
        'Origen': c(['¿Mensaje del grupo?']), '¿Mensaje del grupo?': c(['Leer mensaje'], ['¿Avisos?']), '¿Avisos?': c(['Pendientes de avisar'], ['¿Resumen?']),
        '¿Resumen?': c(['Leer resumen'], ['Datos del bot']),
        'Leer mensaje': c(['¿Foto?']), '¿Foto?': c(['Pedir archivo'], ['¿Comando?']), 'Pedir archivo': c(['Bajar foto']), 'Bajar foto': c(['Foto a texto']),
        'Foto a texto': c(['Guardar desde Telegram']), 'Guardar desde Telegram': c(['Pedir estado']), 'Pedir estado': c(['Estado']), 'Estado': c(['Contestar foto']),
        'Contestar foto': c(['Mandar al grupo']), '¿Comando?': c(['Consultar comando'], ['Texto fijo']), 'Consultar comando': c(['Contestar comando']),
        'Contestar comando': c(['Mandar al grupo']), 'Texto fijo': c(['Mandar al grupo']),
        'Pendientes de avisar': c(['Armar avisos']), 'Armar avisos': c(['Mandar aviso']), 'Mandar aviso': c(['Marcar avisados']),
        'Leer resumen': c(['Armar resumen']), 'Armar resumen': c(['Mandar resumen']),
        'Datos del bot': c(['Conectar webhook']),
        'Ver ligas': c(['Configuración (ligas)']), 'Configuración (ligas)': c(['Ligas']), 'Ligas': c(['Ligas para abrir']),
    }
    flujo = {'name': 'Auditoría de movimientos (Microsip)', 'nodes': nodes, 'connections': connections, 'pinData': {}, 'active': False,
             'settings': {'executionOrder': 'v1', 'saveDataSuccessExecution': 'none', 'saveDataErrorExecution': 'all',
                          'saveManualExecutions': True, 'executionTimeout': 120, 'timezone': 'America/Mexico_City'}}
    with open(SALIDA, 'w', encoding='utf-8') as f:
        json.dump(flujo, f, ensure_ascii=False, indent=2)
    return flujo


if __name__ == '__main__':
    f = armar()
    print('Listo:', SALIDA, '·', len(f['nodes']), 'nodos ·', os.path.getsize(SALIDA) // 1024, 'KB')
