-- Cambia el proveedor de un artículo desde el planeador (sin tocar sus otros ajustes). p = {articulo_id, proveedor_id ('' = el del cálculo)}
SET LOCAL statement_timeout = '15s';
WITH /*CTX*/
INSERT INTO compras_articulos (base, articulo_id, proveedor_id, nota, por)
SELECT cfg.base, (p->>'articulo_id')::bigint, nullif(p->>'proveedor_id', ''), 'Proveedor cambiado en el planeador', cfg.por FROM cfg
ON CONFLICT (base, articulo_id) DO UPDATE SET proveedor_id = EXCLUDED.proveedor_id, por = EXCLUDED.por, actualizado = now();
WITH /*CTX*/
SELECT json_build_object('ok', true, 'articulo_id', (cfg.p->>'articulo_id')::bigint, 'proveedor_id', cfg.p->>'proveedor_id') AS r FROM cfg;
