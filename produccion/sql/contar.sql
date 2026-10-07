-- Pesaje físico de un polímero. Calcula lo que DEBÍA haber (pesaje anterior + entradas de Microsip − consumo de recetas) y la diferencia.
-- Fuera de tolerancia queda "revisar" (hay que volver a pesar); un nuevo pesaje con reconteo_de lo confirma y reemplaza al anterior.
-- p = {articulo_id, fecha, kg, nota, reconteo_de}
SET LOCAL statement_timeout = '20s';
WITH /*CTX*/, /*INV*/, /*MOV*/,
pp AS (SELECT (p->>'articulo_id')::bigint AS art, (p->>'fecha')::date AS f, (p->>'kg')::numeric AS kg, nullif(p->>'reconteo_de', '')::bigint AS rec FROM cfg),
prev AS (SELECT c.* FROM prod_conteo c, cfg, pp WHERE c.base = cfg.base AND c.articulo_id = pp.art AND c.estado <> 'reemplazado' AND c.fecha <= pp.f
           AND c.id <> coalesce(pp.rec, 0)
           -- si se vuelve a pesar, el punto de partida es el que tenía el pesaje que se corrige
           AND (pp.rec IS NULL OR c.id < pp.rec)
         ORDER BY c.fecha DESC, c.id DESC LIMIT 1),
mov AS (SELECT (SELECT coalesce(sum(e.kg), 0) FROM entm e WHERE e.articulo_id = prev.articulo_id AND e.fecha > prev.fecha AND e.fecha <= pp.f) AS ent,
               -- producción después del pesaje anterior (mismo día: lo capturado después de ese pesaje) y hasta el día de este pesaje
               (SELECT coalesce(sum(u.kg), 0) FROM usom u WHERE u.articulo_id = prev.articulo_id AND (u.fecha, u.creado) > (prev.fecha, prev.creado) AND u.fecha <= pp.f) AS con,
               (SELECT sum(u.exceso) FROM usom u WHERE u.articulo_id = prev.articulo_id AND (u.fecha, u.creado) > (prev.fecha, prev.creado) AND u.fecha <= pp.f) AS exc,
               prev.id AS base_id, prev.kg AS base_kg FROM prev, pp),
nuevo AS (
  INSERT INTO prod_conteo (base, articulo_id, fecha, kg, base_id, teorico, entradas, consumo, exceso, estado, reconteo_de, nota, por)
  SELECT cfg.base, pp.art, pp.f, pp.kg, mov.base_id, mov.base_kg + mov.ent - mov.con, mov.ent, mov.con, mov.exc,
         CASE WHEN mov.base_id IS NULL THEN 'inicial' WHEN pp.rec IS NOT NULL THEN 'confirmado'
              WHEN abs(pp.kg - (mov.base_kg + mov.ent - mov.con)) <= greatest(cfg.tol_kg, cfg.tol_pct * mov.con) THEN 'ok' ELSE 'revisar' END,
         pp.rec, nullif(cfg.p->>'nota', ''), cfg.por
  FROM cfg CROSS JOIN pp LEFT JOIN mov ON true RETURNING *),
rep AS (UPDATE prod_conteo c SET estado = 'reemplazado' FROM pp, cfg WHERE c.base = cfg.base AND c.id = pp.rec RETURNING c.id)
SELECT json_build_object('ok', true, 'id', n.id, 'estado', n.estado, 'kg', n.kg, 'teorico', round(n.teorico, 2), 'dif', round(n.kg - n.teorico, 2),
  'entradas', n.entradas, 'consumo', n.consumo, 'exceso', round(n.exceso, 2), 'costo', cos.costo, 'dinero', round((n.kg - n.teorico) * cos.costo, 2),
  'reemplazo', (SELECT count(*) FROM rep), 'tolerancia', round(greatest(cfg.tol_kg, cfg.tol_pct * coalesce(n.consumo, 0)), 2)) AS r
FROM nuevo n CROSS JOIN cfg LEFT JOIN cos ON cos.articulo_id = n.articulo_id;
