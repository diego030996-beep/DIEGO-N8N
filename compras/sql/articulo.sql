-- Guarda el ajuste de un artículo (proveedor, clase fija, empaque, mín/máx a mano, excluir). Vacío = usar el cálculo.
-- p = {articulo_id, proveedor_id, clase, empaque, minimo, maximo, excluir, nota}
SET LOCAL statement_timeout = '15s';
WITH /*CTX*/
DELETE FROM compras_articulos o USING cfg
WHERE o.base = cfg.base AND o.articulo_id = (cfg.p->>'articulo_id')::bigint
  AND coalesce(cfg.p->>'proveedor_id', '') = '' AND coalesce(cfg.p->>'clase', '') = '' AND coalesce(cfg.p->>'empaque', '') = ''
  AND coalesce(cfg.p->>'minimo', '') = '' AND coalesce(cfg.p->>'maximo', '') = '' AND coalesce(cfg.p->>'excluir', '') <> 'true'
  AND coalesce(cfg.p->>'nota', '') = '';
WITH /*CTX*/
INSERT INTO compras_articulos (base, articulo_id, proveedor_id, clase, empaque, minimo, maximo, excluir, nota, por)
SELECT cfg.base, (p->>'articulo_id')::bigint, nullif(p->>'proveedor_id', ''), nullif(p->>'clase', ''), nullif(p->>'empaque', '')::numeric,
       nullif(p->>'minimo', '')::numeric, nullif(p->>'maximo', '')::numeric, coalesce(p->>'excluir', '') = 'true', nullif(p->>'nota', ''), cfg.por
FROM cfg
WHERE NOT (coalesce(p->>'proveedor_id', '') = '' AND coalesce(p->>'clase', '') = '' AND coalesce(p->>'empaque', '') = ''
           AND coalesce(p->>'minimo', '') = '' AND coalesce(p->>'maximo', '') = '' AND coalesce(p->>'excluir', '') <> 'true' AND coalesce(p->>'nota', '') = '')
ON CONFLICT (base, articulo_id) DO UPDATE SET proveedor_id = EXCLUDED.proveedor_id, clase = EXCLUDED.clase, empaque = EXCLUDED.empaque,
  minimo = EXCLUDED.minimo, maximo = EXCLUDED.maximo, excluir = EXCLUDED.excluir, nota = EXCLUDED.nota, por = EXCLUDED.por, actualizado = now();
WITH /*CTX*/
SELECT json_build_object('ok', true, 'articulo_id', (cfg.p->>'articulo_id')::bigint) AS r FROM cfg;
