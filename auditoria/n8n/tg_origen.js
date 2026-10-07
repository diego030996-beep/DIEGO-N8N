// ¿Qué disparó el flujo? (avisos de cada hora, resumen del día o un comprobante de la página) y revisa que el bot esté configurado
const cfg = $input.first().json;
const corrio = n => { try { return $(n).isExecuted; } catch (e) { return false; } };
const chats = String(cfg.chat_ids || '').split(/[,\s]+/).filter(x => /^-?\d+$/.test(x));
const origen = corrio('API') ? 'pagina' : corrio('Cada hora') ? 'avisos' : 'resumen';
if (!/^\d+:/.test(String(cfg.telegram_token || '')) || !chats.length) {
  if (origen === 'pagina') return [];   // la página ya contestó; sin bot configurado no se manda copia
  throw new Error('Pon el token del bot y al menos un chat en "Configuración del bot".');
}
return [{ json: { origen, chats } }];
