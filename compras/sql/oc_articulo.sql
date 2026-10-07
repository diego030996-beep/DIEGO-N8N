-- Órdenes de compra de un artículo (y sus presentaciones) del último año, con lo que dice Microsip y lo que entiende la página.
-- p = {articulo_id}. Sirve para ver de dónde sale "por recibir" y "atrasado".
SET LOCAL statement_timeout = '20s';
WITH /*CTX*/, /*OC*/,
ids AS (SELECT DISTINCT d.datos->>'DOCTO_CM_ID' AS id FROM ms_raw d, cfg
        WHERE d.base = cfg.base AND d.tabla = 'DOCTOS_CM_DET' AND d.datos->>'DOCTO_CM_ID' IN (SELECT id FROM oc WHERE oc.fecha >= cfg.hoy - 400)
          AND (d.datos->>'ARTICULO_ID' = cfg.p->>'articulo_id'
               OR d.datos->>'ARTICULO_ID' IN (SELECT e.articulo_id::text FROM compras_equivalencias e WHERE e.base = cfg.base AND e.confirmado
                                              AND e.articulo_base_id = (cfg.p->>'articulo_id')::bigint))),
/*OCD*/, /*EQV*/, /*LT*/, /*EXI*/,
campos AS (SELECT string_agg(DISTINCT k, ', ') AS k FROM ms_raw d CROSS JOIN cfg, jsonb_object_keys(d.datos) AS k
           WHERE d.base = cfg.base AND d.tabla = 'DOCTOS_CM_DET' AND d.datos->>'DOCTO_CM_ID' IN (SELECT id FROM ids))
SELECT json_build_object('ok', true, 'articulo_id', (cfg.p->>'articulo_id')::bigint, 'campos', (SELECT k FROM campos),
  'ocs', (SELECT coalesce(json_agg(json_build_object('folio', l.folio, 'fecha', l.fecha, 'proveedor', prv.nombre, 'estatus', l.estatus,
            'clave', a.clave, 'pedido', l.pedido, 'ligado', l.rec_ligado, 'microsip', l.rec_ms, 'sin_ligar', l.rec_suelto, 'recibido', l.recibido,
            'falta', l.falta, 'estado', l.estado, 'lt', l.lt) ORDER BY l.fecha DESC), '[]'::json)
          FROM ocl l LEFT JOIN prv ON prv.proveedor_id = l.prov LEFT JOIN ms_articulos a ON a.base = cfg.base AND a.articulo_id = l.articulo_id
          LEFT JOIN eqv q ON q.articulo_id = l.articulo_id
          WHERE coalesce(q.base_id, l.articulo_id) = (cfg.p->>'articulo_id')::bigint)) AS r
FROM cfg;
