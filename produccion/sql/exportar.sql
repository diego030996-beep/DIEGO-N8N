-- Archivos para importar en Microsip: SALIDA de materia prima y ENTRADA de tinacos fabricados (CLAVE,UNIDADES,COSTO).
-- p = {desde, hasta, marcar: 'si'|''}  → lo no exportado del periodo; con marcar='si' se guarda como exportado (no vuelve a salir).
-- p = {exporte_id}                     → vuelve a bajar un exporte anterior.
SET LOCAL statement_timeout = '20s';
WITH /*CTX*/,
rg AS (SELECT coalesce(nullif(p->>'desde', '')::date, '2000-01-01') AS d, coalesce(nullif(p->>'hasta', '')::date, hoy) AS h,
              nullif(p->>'exporte_id', '')::bigint AS ex, coalesce(p->>'marcar', '') = 'si' AS marcar FROM cfg),
sel AS (SELECT r.* FROM prod_registro r CROSS JOIN cfg CROSS JOIN rg
        WHERE r.base = cfg.base AND CASE WHEN rg.ex IS NOT NULL THEN r.exporte_id = rg.ex ELSE r.exporte_id IS NULL AND r.fecha BETWEEN rg.d AND rg.h END),
nuevo AS (INSERT INTO prod_exporte (base, desde, hasta, registros, por)
          SELECT cfg.base, (SELECT min(fecha) FROM sel), (SELECT max(fecha) FROM sel), (SELECT count(*) FROM sel), cfg.por
          FROM cfg, rg WHERE rg.marcar AND rg.ex IS NULL AND EXISTS (SELECT 1 FROM sel) RETURNING id),
marca AS (UPDATE prod_registro g SET exporte_id = nuevo.id FROM nuevo WHERE g.id IN (SELECT id FROM sel) RETURNING g.id),
sal AS (SELECT a.clave, a.nombre, a.unidad, sum(d.cantidad) AS u, round(sum(d.cantidad * coalesce(d.costo_unit, 0)) / nullif(sum(d.cantidad), 0), 4) AS costo
        FROM sel JOIN prod_registro_det d ON d.registro_id = sel.id CROSS JOIN cfg LEFT JOIN ms_articulos a ON a.base = cfg.base AND a.articulo_id = d.componente_id
        GROUP BY a.clave, a.nombre, a.unidad),
ent AS (SELECT a.clave, a.nombre, a.unidad, sum(sel.cantidad) AS u, round(sum(sel.cantidad * coalesce(sel.costo_unit, 0)) / nullif(sum(sel.cantidad), 0), 4) AS costo
        FROM sel CROSS JOIN cfg LEFT JOIN ms_articulos a ON a.base = cfg.base AND a.articulo_id = sel.articulo_id
        GROUP BY a.clave, a.nombre, a.unidad)
SELECT json_build_object('ok', true, 'exporte_id', coalesce((SELECT id FROM nuevo), (SELECT ex FROM rg)), 'marcados', (SELECT count(*) FROM marca),
  'registros', (SELECT count(*) FROM sel), 'desde', (SELECT min(fecha) FROM sel), 'hasta', (SELECT max(fecha) FROM sel),
  'salida', (SELECT coalesce(json_agg(sal ORDER BY sal.nombre), '[]'::json) FROM sal),
  'entrada', (SELECT coalesce(json_agg(ent ORDER BY ent.nombre), '[]'::json) FROM ent),
  'anteriores', (SELECT coalesce(json_agg(json_build_object('id', x.id, 'desde', x.desde, 'hasta', x.hasta, 'registros', x.registros, 'creado', x.creado,
                  'por', x.por, 'importado', x.importado, 'importado_por', x.importado_por) ORDER BY x.id DESC), '[]'::json)
                 FROM (SELECT x.* FROM prod_exporte x, cfg WHERE x.base = cfg.base ORDER BY x.id DESC LIMIT 20) x)) AS r
FROM cfg;
