-- Captura lo que se fabricó: cada renglón descuenta los componentes de su receta al costo de hoy (se guarda tal cual, aunque la receta cambie después).
-- p = {fecha, nota, lineas: [{articulo_id, cantidad}]}. Responde con los componentes que se quedan en negativo.
SET LOCAL statement_timeout = '20s';
WITH /*CTX*/, /*INV*/,
ins AS (
  INSERT INTO prod_registro (base, fecha, articulo_id, cantidad, peso_real, costo_unit, nota, por)
  SELECT cfg.base, (cfg.p->>'fecha')::date, (x->>'articulo_id')::bigint, (x->>'cantidad')::numeric, nullif(x->>'peso_real', '')::numeric,
         (SELECT sum(r.cantidad * coalesce(cos.costo, 0)) FROM prod_receta r LEFT JOIN cos ON cos.articulo_id = r.componente_id
          WHERE r.base = cfg.base AND r.articulo_id = (x->>'articulo_id')::bigint),
         nullif(cfg.p->>'nota', ''), cfg.por
  FROM cfg, jsonb_array_elements(cfg.p->'lineas') x
  WHERE (x->>'cantidad')::numeric > 0 AND EXISTS (SELECT 1 FROM prod_receta r WHERE r.base = cfg.base AND r.articulo_id = (x->>'articulo_id')::bigint)
  RETURNING id, articulo_id, cantidad),
det AS (
  INSERT INTO prod_registro_det (registro_id, componente_id, cantidad, costo_unit)
  SELECT ins.id, r.componente_id, r.cantidad * ins.cantidad, cos.costo
  FROM ins JOIN prod_receta r ON r.articulo_id = ins.articulo_id CROSS JOIN cfg LEFT JOIN cos ON cos.articulo_id = r.componente_id
  WHERE r.base = cfg.base
  RETURNING registro_id, componente_id, cantidad, costo_unit),
neg AS (  -- componentes que quedarían en negativo con esta captura
  SELECT a.clave, a.nombre, a.unidad, coalesce(exi.e, 0) - coalesce(cons.u, 0) - sum(det.cantidad) AS queda, sum(det.cantidad) AS usa
  FROM det JOIN ms_articulos a ON a.articulo_id = det.componente_id CROSS JOIN cfg
  LEFT JOIN exi ON exi.articulo_id = det.componente_id LEFT JOIN cons ON cons.articulo_id = det.componente_id
  WHERE a.base = cfg.base GROUP BY a.clave, a.nombre, a.unidad, exi.e, cons.u
  HAVING coalesce(exi.e, 0) - coalesce(cons.u, 0) - sum(det.cantidad) < 0)
SELECT json_build_object('ok', true, 'registros', (SELECT count(*) FROM ins), 'tinacos', (SELECT coalesce(sum(cantidad), 0) FROM ins),
  'sin_receta', (SELECT coalesce(json_agg(x->>'articulo_id'), '[]'::json) FROM cfg, jsonb_array_elements(cfg.p->'lineas') x
                 WHERE NOT EXISTS (SELECT 1 FROM prod_receta r WHERE r.base = cfg.base AND r.articulo_id = (x->>'articulo_id')::bigint)),
  'negativos', (SELECT coalesce(json_agg(neg), '[]'::json) FROM neg)) AS r
FROM cfg;
