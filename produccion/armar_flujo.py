"""Genera el flujo de n8n "Producción de tinacos (Microsip)" listo para importar.

Uso:  python3 produccion/armar_flujo.py
Lee pagina.html, n8n/*.js, n8n/defaults.json y sql/*.sql y escribe n8n/Producción de tinacos (Microsip).json
"""
import json
import os
import uuid

from sqlops import todas

AQUI = os.path.dirname(os.path.abspath(__file__))
SALIDA = os.path.join(AQUI, 'n8n', 'Producción de tinacos (Microsip).json')
CRED = {'postgres': {'id': 'nkJBZ7x5YYLa9MRx', 'name': 'Postgres account'}}
URL_N8N = 'https://ai.adhesipro.com.mx'
JSON_HDR = {'entries': [{'name': 'Content-Type', 'value': 'application/json; charset=utf-8'}, {'name': 'Cache-Control', 'value': 'no-store'}]}


def leer(*ruta):
    with open(os.path.join(AQUI, *ruta), encoding='utf-8') as f:
        return f.read()


def uid(nombre):
    return str(uuid.uuid5(uuid.NAMESPACE_URL, 'produccion-tinacos/' + nombre))


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
    tablas = "CREATE TABLE IF NOT EXISTS tablero_acceso (token TEXT PRIMARY KEY, rol TEXT NOT NULL, activo BOOLEAN NOT NULL DEFAULT true, creado TIMESTAMPTZ NOT NULL DEFAULT now());\n"
    # las tablas propias se crean aquí (si no existen), antes de cualquier consulta
    acceso_sql = (tablas + leer('sql', 'esquema.sql') + "\n"
                  "SELECT (SELECT rol FROM tablero_acceso WHERE token = $1 AND activo AND rol IN ('admin', 'produccion', 'auditor') LIMIT 1) AS rol;")
    ligas_sql = (tablas +
        "INSERT INTO tablero_acceso (token, rol) SELECT md5(random()::text || clock_timestamp()::text || v.r), v.r FROM (VALUES ('produccion')) AS v(r)\n"
        "WHERE NOT EXISTS (SELECT 1 FROM tablero_acceso a WHERE a.rol = v.r AND a.activo);\n"
        "SELECT (SELECT token FROM tablero_acceso WHERE rol = 'produccion' AND activo ORDER BY creado LIMIT 1) AS t_prod,\n"
        "       (SELECT token FROM tablero_acceso WHERE rol = 'auditor' AND activo ORDER BY creado LIMIT 1) AS t_auditor,\n"
        "       (SELECT token FROM tablero_acceso WHERE rol = 'admin' AND activo ORDER BY creado LIMIT 1) AS t_admin;")
    ligas_js = (
        "// Ligas de producción. produccion = captura; auditor = solo consulta; admin = la misma llave del tablero.\n"
        "const cfg = $('Configuración (ligas)').first().json, a = $('Ligas').first().json;\n"
        "const url = String(cfg.url_n8n || '').replace(/\\/+$/, '') + '/webhook/produccion-tinacos?k=';\n"
        "return [{ json: { produccion: url + a.t_prod, auditor: a.t_auditor ? url + a.t_auditor : '(sin llave de auditor)', administrador: a.t_admin ? url + a.t_admin : '(sin llave de admin)' } }];")
    nodes = [
        nodo('Página', 'n8n-nodes-base.webhook', 2, [0, -300], {'path': 'produccion-tinacos', 'responseMode': 'responseNode', 'options': {}},
             webhookId=uid('webhook/produccion-tinacos')),
        nodo('Mostrar página', 'n8n-nodes-base.respondToWebhook', 1.1, [224, -300], {
            'respondWith': 'text', 'responseBody': leer('pagina.html'),
            'options': {'responseHeaders': {'entries': [{'name': 'Content-Type', 'value': 'text/html; charset=utf-8'},
                                                        {'name': 'Cache-Control', 'value': 'no-store'}]}}}),
        nodo('API', 'n8n-nodes-base.webhook', 2, [0, -60], {'httpMethod': 'POST', 'path': 'produccion-tinacos-api', 'responseMode': 'responseNode', 'options': {}},
             webhookId=uid('webhook/produccion-tinacos-api')),
        nodo('Acceso', 'n8n-nodes-base.postgres', 2.5, [224, -60], {
            'operation': 'executeQuery', 'query': acceso_sql,
            'options': {'queryReplacement': "={{ [ String(($('API').first().json.body || {}).k || '').slice(0, 64) ] }}"}}, credentials=CRED),
        nodo('Preparar', 'n8n-nodes-base.code', 2, [448, -60], {'jsCode': preparar}),
        si('¿Válido?', [672, -60], '={{ $json.ok === true }}'),
        nodo('Consultar', 'n8n-nodes-base.postgres', 2.5, [896, -140], {
            'operation': 'executeQuery', 'query': '={{ $json.sql }}',
            'options': {'queryReplacement': '={{ $json.params }}'}}, credentials=CRED, alwaysOutputData=True, onError='continueRegularOutput'),
        nodo('Armar respuesta', 'n8n-nodes-base.code', 2, [1120, -140], {'jsCode': leer('n8n', 'armar.js')}),
        nodo('Responder', 'n8n-nodes-base.respondToWebhook', 1.1, [1344, -60], {
            'respondWith': 'text', 'responseBody': '={{ JSON.stringify($json.respuesta) }}', 'options': {'responseHeaders': JSON_HDR}}),
        nodo('Ver ligas', 'n8n-nodes-base.manualTrigger', 1, [0, 220], {}),
        nodo('Configuración (ligas)', 'n8n-nodes-base.set', 3.4, [224, 220], {
            'assignments': {'assignments': [{'id': uid('url'), 'name': 'url_n8n', 'value': URL_N8N, 'type': 'string'}]}, 'options': {}}),
        nodo('Ligas', 'n8n-nodes-base.postgres', 2.5, [448, 220], {'operation': 'executeQuery', 'query': ligas_sql, 'options': {}}, credentials=CRED),
        nodo('Ligas para abrir', 'n8n-nodes-base.code', 2, [672, 220], {'jsCode': ligas_js}),
    ]
    c = lambda *dest: {'main': [[{'node': d, 'type': 'main', 'index': 0} for d in rama] for rama in dest]}
    connections = {
        'Página': c(['Mostrar página']), 'API': c(['Acceso']), 'Acceso': c(['Preparar']), 'Preparar': c(['¿Válido?']),
        '¿Válido?': c(['Consultar'], ['Responder']), 'Consultar': c(['Armar respuesta']), 'Armar respuesta': c(['Responder']),
        'Ver ligas': c(['Configuración (ligas)']), 'Configuración (ligas)': c(['Ligas']), 'Ligas': c(['Ligas para abrir']),
    }
    flujo = {'name': 'Producción de tinacos (Microsip)', 'nodes': nodes, 'connections': connections, 'pinData': {}, 'active': False,
             'settings': {'executionOrder': 'v1', 'saveDataSuccessExecution': 'none', 'saveDataErrorExecution': 'all',
                          'saveManualExecutions': True, 'executionTimeout': 120}}
    with open(SALIDA, 'w', encoding='utf-8') as f:
        json.dump(flujo, f, ensure_ascii=False, indent=2)
    return flujo


if __name__ == '__main__':
    f = armar()
    print('Listo:', SALIDA, '·', len(f['nodes']), 'nodos ·', os.path.getsize(SALIDA) // 1024, 'KB')
