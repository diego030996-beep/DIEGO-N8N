-- Confirma, corrige o rechaza una presentación. p = {articulo_id, base_id, factor, accion: 'confirmar'|'rechazar'|'quitar', nota}
SET LOCAL statement_timeout = '15s';
WITH /*CTX*/
DELETE FROM compras_equivalencias e USING cfg WHERE e.base = cfg.base AND e.articulo_id = (cfg.p->>'articulo_id')::bigint AND cfg.p->>'accion' = 'quitar';
WITH /*CTX*/
INSERT INTO compras_equivalencias (base, articulo_id, articulo_base_id, factor, confirmado, origen, nota, por)
SELECT cfg.base, (p->>'articulo_id')::bigint, coalesce(nullif(p->>'base_id', '')::bigint, (p->>'articulo_id')::bigint),
       coalesce(nullif(p->>'factor', '')::numeric, 1), p->>'accion' = 'confirmar', 'confirmada en la página', nullif(p->>'nota', ''), cfg.por
FROM cfg WHERE p->>'accion' IN ('confirmar', 'rechazar')
ON CONFLICT (base, articulo_id) DO UPDATE SET articulo_base_id = EXCLUDED.articulo_base_id, factor = EXCLUDED.factor, confirmado = EXCLUDED.confirmado,
  origen = EXCLUDED.origen, nota = EXCLUDED.nota, por = EXCLUDED.por, actualizado = now();
WITH /*CTX*/
SELECT json_build_object('ok', true, 'articulo_id', (cfg.p->>'articulo_id')::bigint, 'accion', cfg.p->>'accion') AS r FROM cfg;
