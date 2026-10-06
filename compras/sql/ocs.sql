-- Para validar contra el "Diario de compras" de Microsip: OCs de un rango con sus importes. p = {desde, hasta}
SET LOCAL statement_timeout = '30s';
WITH /*CTX*/, /*OC*/,
rg AS (SELECT coalesce(nullif(p->>'desde', '')::date, date_trunc('month', hoy)::date) AS d, coalesce(nullif(p->>'hasta', '')::date, hoy) AS h FROM cfg),
sel AS (SELECT o.* FROM oc o, rg WHERE o.fecha BETWEEN rg.d AND rg.h),
ids AS (SELECT id FROM sel), /*OCD*/,
nr AS (SELECT id, count(*) AS n FROM ocd GROUP BY 1)
SELECT json_build_object('ok', true, 'desde', (SELECT d FROM rg)::text, 'hasta', (SELECT h FROM rg)::text,
  'ocs', (SELECT coalesce(json_agg(json_build_object('folio', s.folio, 'fecha', s.fecha, 'proveedor', prv.nombre, 'importe', s.importe,
            'impuestos', s.impuestos, 'renglones', coalesce(nr.n, 0),
            'plan', (SELECT q.origen FROM compras_planes q WHERE q.base = cfg.base AND q.docto_cm_id = s.id)) ORDER BY s.fecha, s.folio), '[]'::json)
          FROM sel s LEFT JOIN prv ON prv.proveedor_id = s.prov LEFT JOIN nr ON nr.id = s.id)) AS r
FROM cfg;
