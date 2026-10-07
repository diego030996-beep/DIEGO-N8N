// ¿Qué disparó el flujo? (mensaje del grupo, avisos de cada hora, resumen del día o conectar el bot)
const cfg = $input.first().json;
const corrio = n => { try { return $(n).isExecuted; } catch (e) { return false; } };
const origen = corrio('Telegram') ? 'telegram' : corrio('Cada hora') ? 'avisos' : corrio('Resumen del día') ? 'resumen' : 'conectar';
if (origen !== 'conectar' && (!/^\d+:/.test(String(cfg.telegram_token || '')) || !/^-?\d+$/.test(String(cfg.chat_id || '').trim())))
  throw new Error('Pon el token del bot de auditoría y el chat_id del grupo de choferes en "Configuración del bot".');
return [{ json: { origen } }];
