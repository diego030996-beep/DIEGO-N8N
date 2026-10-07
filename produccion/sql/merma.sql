-- Ajuste por merma: las diferencias de pesaje confirmadas (ok o confirmado) que todavía no se ajustan, como archivo para Microsip.
-- Faltante → SALIDA por merma; sobrante → ENTRADA. p = {marcar: 'si'|''} o {exporte_id} para volver a bajarlo.
SET LOCAL statement_timeout = '20s';
WITH /*CTX*/, /*INV*/,
rg AS (SELECT nullif(p->>'exporte_id', '')::bigint AS ex, coalesce(p->>'marcar', '') = 'si' AS marcar FROM cfg),
pend AS (SELECT c.*, c.kg - c.teorico AS dif FROM prod_conteo c, cfg, rg
         -- también los que cuadraron (diferencia 0): el ajuste cierra el periodo y las estadísticas empiezan de cero
         WHERE rg.ex IS NULL AND c.base = cfg.base AND c.estado IN ('ok', 'confirmado') AND c.teorico IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM prod_ajuste j WHERE j.conteo_id = c.id)),
nuevo AS (INSERT INTO prod_exporte (base, desde, hasta, registros, por, tipo)
          SELECT cfg.base, (SELECT min(fecha) FROM pend), (SELECT max(fecha) FROM pend), (SELECT count(*) FROM pend), cfg.por, 'merma'
          FROM cfg, rg WHERE rg.marcar AND EXISTS (SELECT 1 FROM pend WHERE dif <> 0) RETURNING id),
aj AS (INSERT INTO prod_ajuste (base, conteo_id, articulo_id, kg, costo, exporte_id, por)
       SELECT cfg.base, pend.id, pend.articulo_id, pend.dif, cos.costo, nuevo.id, cfg.por FROM pend CROSS JOIN cfg CROSS JOIN nuevo LEFT JOIN cos ON cos.articulo_id = pend.articulo_id
       RETURNING *),
lin AS (  -- lo que va al archivo: lo pendiente, o lo de un exporte anterior
  SELECT articulo_id, dif AS kg, (SELECT costo FROM cos WHERE cos.articulo_id = pend.articulo_id) AS costo, fecha FROM pend
  UNION ALL
  SELECT j.articulo_id, j.kg, j.costo, c.fecha FROM prod_ajuste j JOIN prod_conteo c ON c.id = j.conteo_id, rg WHERE rg.ex IS NOT NULL AND j.exporte_id = rg.ex),
tot AS (SELECT a.clave, a.nombre, a.unidad, sum(l.kg) AS kg, max(l.costo) AS costo FROM lin l CROSS JOIN cfg LEFT JOIN ms_articulos a ON a.base = cfg.base AND a.articulo_id = l.articulo_id
        GROUP BY a.clave, a.nombre, a.unidad)
SELECT json_build_object('ok', true, 'exporte_id', coalesce((SELECT id FROM nuevo), (SELECT ex FROM rg)), 'marcados', (SELECT count(*) FROM aj),
  'conteos', (SELECT count(*) FROM lin WHERE kg <> 0), 'desde', (SELECT min(fecha) FROM lin), 'hasta', (SELECT max(fecha) FROM lin),
  'salida', (SELECT coalesce(json_agg(json_build_object('clave', clave, 'nombre', nombre, 'unidad', unidad, 'u', round(-kg, 4), 'costo', costo) ORDER BY nombre), '[]'::json) FROM tot WHERE kg < 0),
  'entrada', (SELECT coalesce(json_agg(json_build_object('clave', clave, 'nombre', nombre, 'unidad', unidad, 'u', round(kg, 4), 'costo', costo) ORDER BY nombre), '[]'::json) FROM tot WHERE kg > 0),
  'dinero', (SELECT round(sum(kg * coalesce(costo, 0)), 2) FROM tot),
  'anteriores', (SELECT coalesce(json_agg(json_build_object('id', x.id, 'desde', x.desde, 'hasta', x.hasta, 'registros', x.registros, 'creado', x.creado, 'por', x.por,
                 'importado', x.importado, 'folio_ms', x.folio_ms) ORDER BY x.id DESC), '[]'::json) FROM (SELECT x.* FROM prod_exporte x, cfg WHERE x.base = cfg.base AND x.tipo = 'merma' ORDER BY x.id DESC LIMIT 20) x)) AS r
FROM cfg;
