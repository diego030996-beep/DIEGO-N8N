-- Pedidos que tienen compras ligadas: lo pedido contra lo que ha llegado en las recepciones (compras por partes). p = {dias}
SET LOCAL statement_timeout = '25s';
WITH /*CTX*/, /*MOV*/,
pp AS (SELECT DISTINCT g.ped_norm, g.ped_folio, g.ped_cliente FROM reg g, cfg
       WHERE g.ped_folio IS NOT NULL AND g.fecha >= cfg.hoy - coalesce(nullif(cfg.p->>'dias', '')::int, 60)),
rec AS (SELECT g.ped_norm, x.articulo_id, sum(x.u) AS u FROM reg g JOIN cdet x ON x.id = g.cm_id WHERE g.ped_norm IN (SELECT ped_norm FROM pp) GROUP BY 1, 2),
lin AS (SELECT coalesce(pp.ped_norm, r.ped_norm) AS ped_norm, coalesce(p.articulo_id, r.articulo_id) AS articulo_id, p.articulo, p.u AS pu, coalesce(r.u, 0) AS ru
        FROM pp LEFT JOIN pdet p ON p.fn = pp.ped_norm
        FULL JOIN rec r ON r.ped_norm = pp.ped_norm AND r.articulo_id = p.articulo_id),
mv AS (SELECT g.ped_norm, count(*) AS n, sum(g.importe) AS gastado, count(g.cm_id) AS con_recepcion,
              json_agg(json_build_object('ref', g.id, 'folio', coalesce(g.retiro_folio, 'M-' || g.id), 'fecha', g.fecha, 'importe', g.importe, 'recepcion', g.cm_folio) ORDER BY g.fecha) AS movs
       FROM reg g WHERE g.ped_norm IN (SELECT ped_norm FROM pp) GROUP BY 1)
SELECT json_build_object('ok', true, 'pedidos', (SELECT coalesce(json_agg(json_build_object('pedido', pp.ped_folio, 'cliente', pp.ped_cliente,
    'movimientos', mv.n, 'gastado', mv.gastado, 'con_recepcion', mv.con_recepcion, 'movs', mv.movs,
    'articulos', (SELECT json_agg(json_build_object('articulo', coalesce(a.nombre, l.articulo, 'artículo ' || l.articulo_id), 'pedido', l.pu, 'recibido', l.ru) ORDER BY l.pu IS NULL, a.nombre)
                  FROM lin l CROSS JOIN cfg LEFT JOIN ms_articulos a ON a.base = cfg.base AND a.articulo_id = l.articulo_id WHERE l.ped_norm = pp.ped_norm AND (l.ru > 0 OR l.pu IS NOT NULL))
  ) ORDER BY pp.ped_folio DESC), '[]') FROM pp LEFT JOIN mv ON mv.ped_norm = pp.ped_norm)) AS r FROM cfg;
