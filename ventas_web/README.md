# Sistema de Control DISACAM · Ventas web (n8n)

El flujo completo está en `n8n/Ventas web.json`. Se guardó tal como estaba en n8n (V8.64) y encima van los cambios de este repo.

## Cómo se arma
```
python3 ventas_web/armar_flujo.py                                 # actualiza n8n/Ventas web.json
python3 ventas_web/armar_flujo.py bajado_de_n8n.json listo.json   # mete los cambios a otra versión del flujo
```
Se puede correr las veces que sea: cada cambio va entre marcas (`>>> V8.65 …` / `<<< V8.65 …`) y se reemplaza, no se duplica.
Así, si el flujo cambia en otro lado, se baja de n8n y se vuelve a correr.

**Tokens:** dentro del repo, los tokens de los bots de Telegram van como `__TOKEN_TELEGRAM_n__`. Al importar, ponlos en estos nodos:
- `__TOKEN_TELEGRAM_1__`: nodo **Configuración del bot**
- `__TOKEN_TELEGRAM_2__`: nodo **Rutas · Configuración**

Si el archivo de salida queda fuera del repo, los tokens se respetan tal como vienen.

## V8.65 · Sugerir qué chats unir
Archivos: `sql/unir_sugerencias.sql` (va al final de **Crear tablas y funciones**) y `js/unir_sugerencias.js` (va al final de la página).

El sistema busca los chats que parecen ser del mismo cliente:
1. **Mismo teléfono** en dos números de WhatsApp (`55…`, `521 55…` y `+52 55…` cuentan igual).
2. **Escribió su teléfono en otro chat** (Facebook, Instagram, página web, Telegram, correo u otro WhatsApp), y ese teléfono tiene chat de WhatsApp.
3. **Mismo nombre completo** (nombre y apellido) en dos canales. Es la pista más débil y sale al final. No se sugiere si son dos WhatsApp con teléfonos distintos, ni si el nombre está en 4 chats o más.

Solo cuentan los chats de la misma marca con plática en los últimos 120 días. Mercado Libre no entra.

**En cuál queda:** el canal de **WhatsApp con más plática** (mensajes del cliente y nuestros, sin avisos del sistema).
- El principal siempre es WhatsApp, porque por ahí se le contesta. Si el otro canal (ej. Facebook) tiene más mensajes, igual queda en WhatsApp y lo dice.
- Si empatan en mensajes: el conectado a la web y, después, el más reciente.
- Si ese número no está conectado a la web, avisa antes de unir.

**En la página (Chats):**
- Botón **🔗 N** arriba de la lista: todas las sugerencias, cada una con ⭐ en la que queda, el porqué, y los botones **Unir**, **No es el mismo** y **Ver chat**. **↻ Buscar de nuevo** recalcula en ese momento.
- Al abrir un chat con sugerencia sale el aviso «🔗 Parece el mismo cliente que…», con **Unir en «…»** y **No es el mismo**.
- **Más → Unir chats** (a mano) ahora marca los sugeridos con 💡, muestra los mensajes de cada chat y también escoge el WhatsApp con más plática.

Nada se une solo: siempre hay que darle «Unir». **No es el mismo** se guarda en `wch_unir_descartes` y esa pareja no se vuelve a sugerir.

**Cuándo se calcula:** cada 15 min en **Revisar cola y avisos de venta** (`wch_unir_sug_cron()`), y desde la página si el cálculo tiene más de 15 min. El mismo teléfono se revisa en vivo al abrir un chat, así que un chat nuevo no espera los 15 min.
Cada usuario solo ve las parejas en las que puede ver los dos chats.

Instalar: importa el flujo, pon los tokens y corre **Instalar** una vez.

## Pruebas
`python3 ventas_web/pruebas/probar_unir.py` (necesita el Postgres de prueba en `/var/tmp/pgc:5544`, como los demás módulos).
