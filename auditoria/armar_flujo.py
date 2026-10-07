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
    avisos_params = "={{ ['', " + json.dumps(json.dumps(defaults, ensure_ascii=False), ensure_ascii=False) + ", 'Telegram', '{\"_rol\":\"admin\"}', ''] }}"
    avisos_js = (
        "// Arma UN mensaje con lo que venció sin comprobar (máximo 15 renglones) y la lista de claves para marcarlas como avisadas.\n"
        "const cfg = $('Configuración (avisos)').first().json;\n"
        "let r = $input.first().json.r || {}; if (typeof r === 'string') r = JSON.parse(r);\n"
        "const A = r.avisos || [];\n"
        "if (!A.length) return [];\n"
        "if (!/^\\d+:/.test(String(cfg.telegram_token || '')) || !String(cfg.chat_id || '').trim()) throw new Error('Pon el token del bot y el chat_id en el nodo \"Configuración (avisos)\".');\n"
        "const esc = t => String(t ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');\n"
        "const $$ = n => '$' + Math.round(Math.abs(Number(n || 0))).toLocaleString('es-MX');\n"
        "const falta = a => a.clase === 'retiro' ? 'reportarlo + ticket' : a.clase === 'compra' ? 'comprobante de la compra'\n"
        "  : /COMPRA NO REGISTRADA/.test(a.motivo) ? 'registro de compra en Microsip' : /FALTA COMPROBANTE/.test(a.motivo) ? 'ticket / comprobante' : a.motivo;\n"
        "const L = A.slice(0, 15).map(a => `🔴 <b>${esc(a.folio)}</b> · ${$$(a.importe)} · ${esc(a.empleado || '?')}` +\n"
        "  (a.pedido ? `\\nPedido ${esc(a.pedido)}` : '') + `\\n${esc(a.concepto).slice(0, 80)}` + `\\nFalta: ${esc(falta(a))}${a.horas > 0 ? ' · ' + a.horas + ' h' : ''}`);\n"
        "const url = String(cfg.url_n8n || '').replace(/\\/+$/, '') + '/webhook/auditoria-mov';\n"
        "const text = `⚠️ <b>Comprobación pendiente</b> (${A.length})\\n\\n` + L.join('\\n\\n') + (A.length > 15 ? `\\n\\n…y ${A.length - 15} más.` : '') +\n"
        "  `\\n\\nSe revisa en Auditoría de movimientos (Mis ligas).`;\n"
        "return [{ json: { chat_id: String(cfg.chat_id).trim(), text, parse_mode: 'HTML', disable_web_page_preview: true, claves: A.map(a => a.clave) } }];\n")
    marcar_sql = "INSERT INTO mov_aviso (clave) SELECT unnest($1::text[]) ON CONFLICT (clave) DO NOTHING;\nSELECT 1 AS ok;"
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
        # avisos por Telegram
        nodo('Cada hora', 'n8n-nodes-base.scheduleTrigger', 1.2, [0, 440], {'rule': {'interval': [{'field': 'cronExpression', 'expression': '5 8-22 * * *'}]}}),
        nodo('Configuración (avisos)', 'n8n-nodes-base.set', 3.4, [224, 440], {'assignments': {'assignments': [
            {'id': uid('tg'), 'name': 'telegram_token', 'value': 'PEGA_AQUI_EL_TOKEN_DEL_BOT', 'type': 'string'},
            {'id': uid('chat'), 'name': 'chat_id', 'value': 'PEGA_AQUI_EL_CHAT_ID_DEL_GRUPO', 'type': 'string'},
            {'id': uid('url2'), 'name': 'url_n8n', 'value': URL_N8N, 'type': 'string'}]}, 'options': {}}),
        pg('Pendientes de avisar', [448, 440], avisos_sql, avisos_params),
        nodo('Armar aviso', 'n8n-nodes-base.code', 2, [672, 440], {'jsCode': avisos_js}),
        nodo('Enviar a Telegram', 'n8n-nodes-base.httpRequest', 4.2, [896, 440], {
            'method': 'POST', 'url': "=https://api.telegram.org/bot{{ $('Configuración (avisos)').first().json.telegram_token }}/sendMessage",
            'sendBody': True, 'specifyBody': 'json',
            'jsonBody': '={{ JSON.stringify({ chat_id: $json.chat_id, text: $json.text, parse_mode: $json.parse_mode, disable_web_page_preview: true }) }}', 'options': {}}),
        pg('Marcar avisados', [1120, 440], marcar_sql, "={{ [ '{' + $('Armar aviso').first().json.claves.map(c => '\"' + c + '\"').join(',') + '}' ] }}"),
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
        'Cada hora': c(['Configuración (avisos)']), 'Configuración (avisos)': c(['Pendientes de avisar']), 'Pendientes de avisar': c(['Armar aviso']),
        'Armar aviso': c(['Enviar a Telegram']), 'Enviar a Telegram': c(['Marcar avisados']),
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
