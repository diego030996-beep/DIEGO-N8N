"""Genera el flujo de n8n "Planeador de compras (Microsip)" listo para importar.

Uso:  python3 compras/armar_flujo.py
Lee pagina.html, n8n/*.js, n8n/defaults.json y sql/*.sql y escribe n8n/Planeador de compras (Microsip).json
"""
import json
import os
import uuid

from sqlops import todas

AQUI = os.path.dirname(os.path.abspath(__file__))
SALIDA = os.path.join(AQUI, 'n8n', 'Planeador de compras (Microsip).json')
CRED = {'postgres': {'id': 'nkJBZ7x5YYLa9MRx', 'name': 'Postgres account'}}
URL_N8N = 'https://ai.adhesipro.com.mx'
JSON_HDR = {'entries': [{'name': 'Content-Type', 'value': 'application/json; charset=utf-8'}, {'name': 'Cache-Control', 'value': 'no-store'}]}


def leer(*ruta):
    with open(os.path.join(AQUI, *ruta), encoding='utf-8') as f:
        return f.read()


def uid(nombre):
    return str(uuid.uuid5(uuid.NAMESPACE_URL, 'planeador-compras/' + nombre))


def nodo(nombre, tipo, version, pos, params, **extra):
    n = {'parameters': params, 'id': uid(nombre), 'name': nombre, 'type': tipo, 'typeVersion': version, 'position': pos}
    n.update(extra)
    return n


def si(nombre, pos, expr):
    return nodo(nombre, 'n8n-nodes-base.if', 2.2, pos, {
        'conditions': {'options': {'caseSensitive': True, 'leftValue': '', 'typeValidation': 'loose', 'version': 2},
                       'conditions': [{'id': uid(nombre + '/c'), 'leftValue': expr, 'rightValue': '',
                                       'operator': {'type': 'boolean', 'operation': 'true', 'singleValue': True}}],
                       'combinator': 'and'},
        'options': {}})


def armar():
    defaults = json.loads(leer('n8n', 'defaults.json'))
    preparar = (leer('n8n', 'preparar.js')
                .replace('__SQL__', json.dumps(todas(), ensure_ascii=False))
                .replace('__DEF__', json.dumps(defaults, ensure_ascii=False)))
    acceso_sql = (
        "CREATE TABLE IF NOT EXISTS tablero_acceso (token TEXT PRIMARY KEY, rol TEXT NOT NULL, activo BOOLEAN NOT NULL DEFAULT true, "
        "creado TIMESTAMPTZ NOT NULL DEFAULT now());\n"
        "CREATE TABLE IF NOT EXISTS compras_config (clave TEXT PRIMARY KEY, valor TEXT, por TEXT, actualizado TIMESTAMPTZ NOT NULL DEFAULT now());\n"
        "SELECT (SELECT rol FROM tablero_acceso WHERE token = $1 AND activo AND rol IN ('admin', 'compras', 'auditor') LIMIT 1) AS rol,\n"
        "       (SELECT valor FROM compras_config WHERE clave = 'razones') AS razones;")
    ligas_sql = (
        "CREATE TABLE IF NOT EXISTS tablero_acceso (token TEXT PRIMARY KEY, rol TEXT NOT NULL, activo BOOLEAN NOT NULL DEFAULT true, "
        "creado TIMESTAMPTZ NOT NULL DEFAULT now());\n"
        "INSERT INTO tablero_acceso (token, rol) SELECT md5(random()::text || clock_timestamp()::text || v.r), v.r FROM (VALUES ('compras'), ('auditor')) AS v(r)\n"
        "WHERE NOT EXISTS (SELECT 1 FROM tablero_acceso a WHERE a.rol = v.r AND a.activo);\n"
        "SELECT (SELECT token FROM tablero_acceso WHERE rol = 'compras' AND activo ORDER BY creado LIMIT 1) AS t_compras,\n"
        "       (SELECT token FROM tablero_acceso WHERE rol = 'auditor' AND activo ORDER BY creado LIMIT 1) AS t_auditor,\n"
        "       (SELECT token FROM tablero_acceso WHERE rol = 'admin' AND activo ORDER BY creado LIMIT 1) AS t_admin;")
    ligas_js = (
        "// Ligas del planeador de compras. compras = captura; auditor = solo consulta (para el Sello); admin = la misma llave del tablero.\n"
        "const cfg = $('Configuración (ligas)').first().json, a = $('Ligas').first().json;\n"
        "const url = String(cfg.url_n8n || '').replace(/\\/+$/, '') + '/webhook/compras?k=';\n"
        "return [{ json: { compras: url + a.t_compras, auditor: url + a.t_auditor, administrador: a.t_admin ? url + a.t_admin : '(sin llave de admin)' } }];")

    nodes = [
        nodo('Página', 'n8n-nodes-base.webhook', 2, [0, -400], {'path': 'compras', 'responseMode': 'responseNode', 'options': {}},
             webhookId=uid('webhook/compras')),
        nodo('Mostrar página', 'n8n-nodes-base.respondToWebhook', 1.1, [224, -400], {
            'respondWith': 'text', 'responseBody': leer('pagina.html'),
            'options': {'responseHeaders': {'entries': [{'name': 'Content-Type', 'value': 'text/html; charset=utf-8'},
                                                        {'name': 'Cache-Control', 'value': 'no-store'}]}}}),
        nodo('API', 'n8n-nodes-base.webhook', 2, [0, -160], {'httpMethod': 'POST', 'path': 'compras-api', 'responseMode': 'responseNode', 'options': {}},
             webhookId=uid('webhook/compras-api')),
        nodo('Acceso', 'n8n-nodes-base.postgres', 2.5, [224, -160], {
            'operation': 'executeQuery', 'query': acceso_sql,
            'options': {'queryReplacement': "={{ [ String(($('API').first().json.body || {}).k || '').slice(0, 64) ] }}"}}, credentials=CRED),
        nodo('Día 1 de cada mes', 'n8n-nodes-base.scheduleTrigger', 1.2, [224, 80], {
            'rule': {'interval': [{'field': 'cronExpression', 'expression': '40 3 1 * *'}]}}),
        nodo('Preparar', 'n8n-nodes-base.code', 2, [448, -160], {'jsCode': preparar}),
        si('¿Válido?', [672, -160], '={{ $json.ok === true }}'),
        nodo('Consultar', 'n8n-nodes-base.postgres', 2.5, [896, -240], {
            'operation': 'executeQuery', 'query': '={{ $json.sql }}',
            'options': {'queryReplacement': '={{ $json.params }}'}}, credentials=CRED, alwaysOutputData=True, onError='continueRegularOutput'),
        nodo('Armar respuesta', 'n8n-nodes-base.code', 2, [1120, -240], {'jsCode': leer('n8n', 'armar.js')}),
        si('¿Desde la página?', [1344, -240], "={{ $json.desde === 'pagina' }}"),
        nodo('Responder', 'n8n-nodes-base.respondToWebhook', 1.1, [1568, -160], {
            'respondWith': 'text', 'responseBody': '={{ JSON.stringify($json.respuesta) }}', 'options': {'responseHeaders': JSON_HDR}}),
        nodo('Ver ligas', 'n8n-nodes-base.manualTrigger', 1, [0, 320], {}),
        nodo('Configuración (ligas)', 'n8n-nodes-base.set', 3.4, [224, 320], {
            'assignments': {'assignments': [{'id': uid('url'), 'name': 'url_n8n', 'value': URL_N8N, 'type': 'string'}]}, 'options': {}}),
        nodo('Ligas', 'n8n-nodes-base.postgres', 2.5, [448, 320], {'operation': 'executeQuery', 'query': ligas_sql, 'options': {}}, credentials=CRED),
        nodo('Ligas para abrir', 'n8n-nodes-base.code', 2, [672, 320], {'jsCode': ligas_js}),
    ]
    c = lambda *dest: {'main': [[{'node': d, 'type': 'main', 'index': 0} for d in rama] for rama in dest]}
    connections = {
        'Página': c(['Mostrar página']),
        'API': c(['Acceso']),
        'Acceso': c(['Preparar']),
        'Día 1 de cada mes': c(['Preparar']),
        'Preparar': c(['¿Válido?']),
        '¿Válido?': c(['Consultar'], ['Responder']),
        'Consultar': c(['Armar respuesta']),
        'Armar respuesta': c(['¿Desde la página?']),
        '¿Desde la página?': c(['Responder'], []),
        'Ver ligas': c(['Configuración (ligas)']),
        'Configuración (ligas)': c(['Ligas']),
        'Ligas': c(['Ligas para abrir']),
    }
    flujo = {
        'name': 'Planeador de compras (Microsip)',
        'nodes': nodes,
        'connections': connections,
        'pinData': {},
        'active': False,
        # ligero: no guarda cada apertura de la página en el historial de ejecuciones (sí guarda errores)
        'settings': {'executionOrder': 'v1', 'saveDataSuccessExecution': 'none', 'saveDataErrorExecution': 'all',
                     'saveManualExecutions': True, 'executionTimeout': 240},
    }
    with open(SALIDA, 'w', encoding='utf-8') as f:
        json.dump(flujo, f, ensure_ascii=False, indent=2)
    return flujo


if __name__ == '__main__':
    f = armar()
    print('Listo:', SALIDA, '·', len(f['nodes']), 'nodos ·', os.path.getsize(SALIDA) // 1024, 'KB')
