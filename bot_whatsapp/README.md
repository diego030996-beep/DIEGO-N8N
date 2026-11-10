# Cerebro Super Tank · WhatsApp (n8n)

`n8n/Cerebro Super Tank WhatsApp.json` es el bot de WhatsApp de Super Tank (v4.27), tal como está en n8n.

- v4.27: no repite pedidos. Antes de crear uno busca si el cliente ya tiene un pedido vivo:
  - por chat;
  - por teléfono (el de WhatsApp o el que dio);
  - por nombre más capacidad;
  - por «mismos datos»: tinaco, cantidad, color y dirección.
  
  Solo actualiza el folio si es el mismo chat.
- Las reglas de venta consultiva (v4.26) viven en la base; las instala Ventas web V8.64.

**Token:** en el repo el token del bot de Telegram va como `__TOKEN_TELEGRAM_1__`, en los nodos **Avisar falla de IA** y **Avisar a administración**. Ponlo al importar.
