-- Auditoría de polímero: por cada polímero, lo que debe haber hoy, sus pesajes con diferencia (kg y $), cuánto se explica por tinacos más pesados
-- que la receta y cuánto es merma, la trazabilidad (entradas, consumo y pesajes día por día) y las alertas. p = {dias}
SET LOCAL statement_timeout = '30s';
WITH /*CTX*/, /*INV*/, /*MOV*/,
dd AS (SELECT greatest(least(coalesce(nullif(p->>'dias', '')::int, 45), 365), 7) AS dias FROM cfg),
ult AS (SELECT DISTINCT ON (c.articulo_id) c.* FROM prod_conteo c, cfg WHERE c.base = cfg.base AND c.estado <> 'reemplazado' ORDER BY c.articulo_id, c.fecha DESC, c.id DESC),
hoyt AS (  -- lo que debe haber hoy, desde el último pesaje
  SELECT pol.articulo_id, ult.id AS ult_id, ult.fecha AS ult_fecha, ult.kg AS ult_kg, ult.estado AS ult_estado,
         (SELECT coalesce(sum(e.kg), 0) FROM entm e WHERE e.articulo_id = pol.articulo_id AND e.fecha > ult.fecha) AS ent,
         (SELECT coalesce(sum(u.kg), 0) FROM usom u WHERE u.articulo_id = pol.articulo_id AND (u.fecha, u.creado) > (ult.fecha, ult.creado)) AS con
  FROM pol LEFT JOIN ult ON ult.articulo_id = pol.articulo_id),
cont AS (
  SELECT c.*, c.kg - c.teorico AS dif, cos.costo, j.id AS ajuste_id, x.importado AS ajuste_importado, j.exporte_id
  FROM prod_conteo c CROSS JOIN cfg CROSS JOIN dd LEFT JOIN cos ON cos.articulo_id = c.articulo_id
  LEFT JOIN prod_ajuste j ON j.conteo_id = c.id LEFT JOIN prod_exporte x ON x.id = j.exporte_id
  WHERE c.base = cfg.base AND c.fecha >= cfg.hoy - dd.dias),
movs AS (  -- trazabilidad
  SELECT articulo_id, fecha, '-infinity'::timestamptz AS orden, 'entrada' AS tipo, folio AS ref, kg, NULL::numeric AS piezas FROM entm, cfg, dd WHERE fecha >= cfg.hoy - dd.dias
  UNION ALL
  SELECT u.articulo_id, u.fecha, u.creado, 'consumo', a.nombre, -u.kg, u.piezas
  FROM usom u CROSS JOIN cfg CROSS JOIN dd LEFT JOIN ms_articulos a ON a.base = cfg.base AND a.articulo_id = u.tinaco_id
  WHERE u.fecha >= cfg.hoy - dd.dias
  UNION ALL
  SELECT articulo_id, fecha, c.creado, 'pesaje', estado, kg, NULL FROM prod_conteo c, cfg, dd WHERE c.base = cfg.base AND c.fecha >= cfg.hoy - dd.dias AND c.estado <> 'reemplazado')
SELECT json_build_object('ok', true, 'hoy', cfg.hoy, 'dias', (SELECT dias FROM dd), 'tol_kg', cfg.tol_kg, 'tol_pct', cfg.tol_pct * 100, 'dias_conteo', cfg.dias_conteo,
  'polimeros', (SELECT coalesce(json_agg(json_build_object('articulo_id', pol.articulo_id, 'clave', pol.clave, 'nombre', pol.nombre, 'unidad', pol.unidad, 'costo', cos.costo,
      'existencia_ms', coalesce(exi.e, 0), 'ult_fecha', h.ult_fecha, 'ult_kg', h.ult_kg, 'ult_estado', h.ult_estado, 'ult_id', h.ult_id,
      'entradas', h.ent, 'consumo', h.con, 'teorico_hoy', CASE WHEN h.ult_id IS NOT NULL THEN round(h.ult_kg + h.ent - h.con, 2) END,
      'dias_sin_pesar', cfg.hoy - h.ult_fecha,
      'conteos', (SELECT coalesce(json_agg(json_build_object('id', c.id, 'fecha', c.fecha, 'kg', c.kg, 'teorico', round(c.teorico, 2), 'dif', round(c.dif, 2),
            'dinero', round(c.dif * c.costo, 2), 'entradas', c.entradas, 'consumo', c.consumo, 'exceso', round(c.exceso, 2),
            'merma', CASE WHEN c.dif < 0 THEN round(-c.dif - greatest(coalesce(c.exceso, 0), 0), 2) END,
            'estado', c.estado, 'reconteo_de', c.reconteo_de, 'nota', c.nota, 'por', c.por, 'creado', c.creado,
            'ajuste', c.ajuste_id IS NOT NULL, 'ajuste_importado', c.ajuste_importado IS NOT NULL, 'exporte_id', c.exporte_id) ORDER BY c.fecha DESC, c.id DESC), '[]'::json)
          FROM cont c WHERE c.articulo_id = pol.articulo_id),
      'movs', (SELECT coalesce(json_agg(json_build_object('fecha', m.fecha, 'tipo', m.tipo, 'ref', m.ref, 'kg', round(m.kg, 2), 'piezas', m.piezas) ORDER BY m.fecha, m.orden), '[]'::json)
          FROM movs m WHERE m.articulo_id = pol.articulo_id),
      'perdida', (SELECT json_build_object('kg', round(coalesce(sum(-c.dif) FILTER (WHERE c.estado IN ('ok', 'confirmado')), 0), 2),
            'dinero', round(coalesce(sum(-c.dif * c.costo) FILTER (WHERE c.estado IN ('ok', 'confirmado')), 0), 2),
            'exceso', round(coalesce(sum(c.exceso) FILTER (WHERE c.estado IN ('ok', 'confirmado')), 0), 2),
            'consumo', round(coalesce(sum(c.consumo) FILTER (WHERE c.estado IN ('ok', 'confirmado')), 0), 2)) FROM cont c WHERE c.articulo_id = pol.articulo_id))
      ORDER BY pol.nombre), '[]'::json)
    FROM pol CROSS JOIN cfg LEFT JOIN hoyt h ON h.articulo_id = pol.articulo_id LEFT JOIN cos ON cos.articulo_id = pol.articulo_id LEFT JOIN exi ON exi.articulo_id = pol.articulo_id),
  'pendiente_merma', (SELECT json_build_object('conteos', count(*), 'kg', round(coalesce(sum(c.kg - c.teorico), 0), 2), 'dinero', round(coalesce(sum((c.kg - c.teorico) * cos.costo), 0), 2))
    FROM prod_conteo c CROSS JOIN cfg LEFT JOIN cos ON cos.articulo_id = c.articulo_id
    WHERE c.base = cfg.base AND c.estado IN ('ok', 'confirmado') AND c.teorico IS NOT NULL AND c.kg <> c.teorico
      AND NOT EXISTS (SELECT 1 FROM prod_ajuste j WHERE j.conteo_id = c.id))) AS r
FROM cfg;
