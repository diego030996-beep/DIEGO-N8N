// Conecta el bot de auditoría a este flujo (correr una vez a mano, después de activar el flujo)
const cfg = $('Configuración del bot').first().json;
if (!/^\d+:/.test(String(cfg.telegram_token || ''))) throw new Error('Pon el token del bot de auditoría en "Configuración del bot".');
const url = String(cfg.url_n8n || '').replace(/\/+$/, '') + '/webhook/auditoria-mov-tg';
return [{ json: { url, secret_token: String(cfg.secreto || ''), allowed_updates: ['message'], drop_pending_updates: true } }];
