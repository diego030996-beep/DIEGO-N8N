"""Genera el flujo de n8n "Panel general (ligas con PIN)" listo para importar.

Uso:  python3 panel/armar_flujo.py
Lee pagina.html, esquema.sql y n8n/*.js y escribe n8n/Panel general (ligas con PIN).json
"""
import json
import os
import uuid

AQUI = os.path.dirname(os.path.abspath(__file__))
SALIDA = os.path.join(AQUI, 'n8n', 'Panel general (ligas con PIN).json')
CRED = {'postgres': {'id': 'nkJBZ7x5YYLa9MRx', 'name': 'Postgres account'}}
URL_N8N = 'https://ai.adhesipro.com.mx'
NO_CACHE = {'name': 'Cache-Control', 'value': 'no-store'}


def leer(*ruta):
    with open(os.path.join(AQUI, *ruta), encoding='utf-8') as f:
        return f.read()


def uid(nombre):
    return str(uuid.uuid5(uuid.NAMESPACE_URL, 'panel-general/' + nombre))


def nodo(nombre, tipo, version, pos, params, **extra):
    n = {'parameters': params, 'id': uid(nombre), 'name': nombre, 'type': tipo, 'typeVersion': version, 'position': pos}
    n.update(extra)
    return n


def armar():
    esquema = leer('esquema.sql')
    preparar = leer('n8n', 'preparar.js').replace('__ESQUEMA__', json.dumps(esquema, ensure_ascii=False))
    # Liga para crear / reponer el PIN: usa la llave de administrador del tablero (la crea si no existe).
    llave_sql = (esquema + "\n"
        "INSERT INTO tablero_acceso (token, rol) SELECT replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''), 'admin'\n"
        "WHERE NOT EXISTS (SELECT 1 FROM tablero_acceso WHERE rol = 'admin' AND activo);\n"
        "SELECT (SELECT token FROM tablero_acceso WHERE rol = 'admin' AND activo ORDER BY creado LIMIT 1) AS t_admin,\n"
        "       EXISTS (SELECT 1 FROM panel_pin) AS hay_pin;")
    llave_js = (
        "// Liga del panel y liga para poner (o reponer) el PIN. La segunda trae la llave de administrador: no la compartas.\n"
        "const cfg = $('Configuración (liga)').first().json, a = $('Llave de administrador').first().json;\n"
        "const url = String(cfg.url_n8n || '').replace(/\\/+$/, '') + '/webhook/mis-ligas';\n"
        "return [{ json: { panel: url, poner_pin: url + '?k=' + a.t_admin,\n"
        "  nota: a.hay_pin ? 'Ya tienes PIN. Abre poner_pin solo si lo olvidaste: lo reemplaza y cierra las sesiones.' : 'Abre poner_pin una vez para crear tu PIN; luego entra siempre con la liga panel.' } }];")
    nodes = [
        nodo('Página', 'n8n-nodes-base.webhook', 2, [0, -300], {'path': 'mis-ligas', 'responseMode': 'responseNode', 'options': {}},
             webhookId=uid('webhook/mis-ligas')),
        nodo('Mostrar página', 'n8n-nodes-base.respondToWebhook', 1.1, [224, -300], {
            'respondWith': 'text', 'responseBody': leer('pagina.html'),
            'options': {'responseHeaders': {'entries': [{'name': 'Content-Type', 'value': 'text/html; charset=utf-8'}, NO_CACHE,
                                                        {'name': 'X-Robots-Tag', 'value': 'noindex'}, {'name': 'Referrer-Policy', 'value': 'no-referrer'}]}}}),
        nodo('API', 'n8n-nodes-base.webhook', 2, [0, -60], {'httpMethod': 'POST', 'path': 'mis-ligas-api', 'responseMode': 'responseNode', 'options': {}},
             webhookId=uid('webhook/mis-ligas-api')),
        nodo('Preparar', 'n8n-nodes-base.code', 2, [224, -60], {'jsCode': preparar}),
        nodo('¿Válido?', 'n8n-nodes-base.if', 2.2, [448, -60], {
            'conditions': {'options': {'caseSensitive': True, 'leftValue': '', 'typeValidation': 'loose', 'version': 2},
                           'conditions': [{'id': uid('valido/c'), 'leftValue': '={{ $json.ok === true }}', 'rightValue': '',
                                           'operator': {'type': 'boolean', 'operation': 'true', 'singleValue': True}}],
                           'combinator': 'and'}, 'options': {}}),
        nodo('Consultar', 'n8n-nodes-base.postgres', 2.5, [672, -140], {
            'operation': 'executeQuery', 'query': '={{ $json.sql }}',
            'options': {'queryReplacement': '={{ $json.params }}'}}, credentials=CRED, alwaysOutputData=True, onError='continueRegularOutput'),
        nodo('Armar respuesta', 'n8n-nodes-base.code', 2, [896, -140], {'jsCode': leer('n8n', 'armar.js')}),
        nodo('Responder', 'n8n-nodes-base.respondToWebhook', 1.1, [1120, -60], {
            'respondWith': 'text', 'responseBody': '={{ JSON.stringify($json.respuesta) }}',
            'options': {'responseHeaders': {'entries': [{'name': 'Content-Type', 'value': 'application/json; charset=utf-8'}, NO_CACHE]}}}),
        nodo('Mi liga para poner PIN', 'n8n-nodes-base.manualTrigger', 1, [0, 220], {}),
        nodo('Configuración (liga)', 'n8n-nodes-base.set', 3.4, [224, 220], {
            'assignments': {'assignments': [{'id': uid('url'), 'name': 'url_n8n', 'value': URL_N8N, 'type': 'string'}]}, 'options': {}}),
        nodo('Llave de administrador', 'n8n-nodes-base.postgres', 2.5, [448, 220], {'operation': 'executeQuery', 'query': llave_sql, 'options': {}}, credentials=CRED),
        nodo('Ligas para abrir', 'n8n-nodes-base.code', 2, [672, 220], {'jsCode': llave_js}),
    ]
    c = lambda *dest: {'main': [[{'node': d, 'type': 'main', 'index': 0} for d in rama] for rama in dest]}
    connections = {
        'Página': c(['Mostrar página']), 'API': c(['Preparar']), 'Preparar': c(['¿Válido?']),
        '¿Válido?': c(['Consultar'], ['Responder']), 'Consultar': c(['Armar respuesta']), 'Armar respuesta': c(['Responder']),
        'Mi liga para poner PIN': c(['Configuración (liga)']), 'Configuración (liga)': c(['Llave de administrador']),
        'Llave de administrador': c(['Ligas para abrir']),
    }
    flujo = {'name': 'Panel general (ligas con PIN)', 'nodes': nodes, 'connections': connections, 'pinData': {}, 'active': False,
             'settings': {'executionOrder': 'v1', 'saveDataSuccessExecution': 'none', 'saveDataErrorExecution': 'all',
                          'saveManualExecutions': True, 'executionTimeout': 60}}
    with open(SALIDA, 'w', encoding='utf-8') as f:
        json.dump(flujo, f, ensure_ascii=False, indent=2)
    return flujo


if __name__ == '__main__':
    f = armar()
    print('Listo:', SALIDA, '·', len(f['nodes']), 'nodos ·', os.path.getsize(SALIDA) // 1024, 'KB')
