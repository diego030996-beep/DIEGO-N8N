-- Todos los retiros de caja de un mes (aunque sean de antes de empezar la auditoría), para ver en qué se va el efectivo.
-- Agrupa por categoría (no pide comprobante / gasto / compra) y por palabra de la descripción. p = {mes: 'YYYY-MM'}
SET LOCAL statement_timeout = '30s';
WITH /*CTX*/,
m AS (SELECT coalesce(nullif(p->>'mes', ''), to_char(hoy, 'YYYY-MM')) || '-01' AS d1 FROM cfg),
r0 AS (SELECT v.docto_id::text AS id, v.folio, v.fecha, left(coalesce(v.hora, ''), 5) AS hora, trim(coalesce(v.descripcion, '')) AS descripcion, coalesce(v.usuario, '') AS usuario
       FROM ms_ventas_v v CROSS JOIN cfg CROSS JOIN m
       WHERE v.base = cfg.base AND v.origen = 'PV' AND upper(v.tipo) = 'R' AND NOT v.cancelado
         AND v.fecha >= m.d1::date AND v.fecha < (m.d1::date + interval '1 month')::date),
imp AS (SELECT c.datos->>'DOCTO_PV_ID' AS id, abs(sum(CASE WHEN jsonb_typeof(c.datos->'IMPORTE') = 'number' THEN (c.datos->>'IMPORTE')::numeric ELSE 0 END)) AS importe
        FROM ms_raw c, cfg WHERE c.base = cfg.base AND c.tabla = 'DOCTOS_PV_COBROS' AND c.datos->>'DOCTO_PV_ID' IN (SELECT id FROM r0) GROUP BY 1),
r AS (SELECT r0.*, coalesce(nullif(imp.importe, 0), 0) AS importe,
             CASE WHEN cfg.excl <> '' AND r0.descripcion ~* cfg.excl THEN 'sin comprobante'
                  WHEN coalesce(cfg.c->>'retiros_gasto', '') <> '' AND r0.descripcion ~* (cfg.c->>'retiros_gasto') THEN 'gasto'
                  ELSE 'compra / otro' END AS categoria,
             EXISTS (SELECT 1 FROM mov_registro mr WHERE mr.base = cfg.base AND mr.retiro_id = r0.id AND NOT mr.borrado) AS reportado
      FROM r0 CROSS JOIN cfg LEFT JOIN imp ON imp.id = r0.id),
pal AS (SELECT upper(w) AS palabra, count(*) AS n, sum(r.importe) AS importe
        FROM r, regexp_split_to_table(regexp_replace(r.descripcion, '[^A-Za-zÁÉÍÓÚÑáéíóúñ ]', ' ', 'g'), '\s+') AS w
        WHERE length(w) >= 4 GROUP BY 1 HAVING count(*) >= 2 ORDER BY 3 DESC LIMIT 30)
SELECT json_build_object('ok', true, 'mes', left((SELECT d1 FROM m), 7),
  'categorias', (SELECT coalesce(json_agg(x ORDER BY x.importe DESC), '[]') FROM (SELECT categoria, count(*) AS n, sum(importe) AS importe FROM r GROUP BY 1) x),
  'palabras', (SELECT coalesce(json_agg(pal), '[]') FROM pal),
  'lista', (SELECT coalesce(json_agg(json_build_object('folio', folio, 'fecha', fecha, 'hora', hora, 'descripcion', descripcion, 'usuario', usuario, 'importe', importe,
              'categoria', categoria, 'reportado', reportado) ORDER BY fecha, hora), '[]') FROM r),
  'total', (SELECT coalesce(sum(importe), 0) FROM r), 'n', (SELECT count(*) FROM r)) AS r;
