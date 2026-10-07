// ¿Qué disparó el flujo? (avisos de cada hora o resumen del día) y revisa que el bot esté configurado
const cfg = $input.first().json;
const corrio = n => { try { return $(n).isExecuted; } catch (e) { return false; } };
const chats = String(cfg.chat_ids || '').split(/[,\s]+/).filter(x => /^-?\d+$/.test(x));
if (!/^\d+:/.test(String(cfg.telegram_token || '')) || !chats.length)
  throw new Error('Pon el token del bot y al menos un chat en "Configuración del bot".');
return [{ json: { origen: corrio('Cada hora') ? 'avisos' : 'resumen', chats } }];
