-- OCs anteriores al planeador (reconstruidas de Microsip): pone "Autorizó gerencia" donde falta la razón. p = {mes}
SET LOCAL statement_timeout = '15s';
WITH /*CTX*/,
m AS (SELECT date_trunc('month', coalesce(nullif(p->>'mes', '')::date, hoy))::date AS mes FROM cfg)
UPDATE compras_decisiones d SET razon = 'gerencia', por = cfg.por, modificado = now()
FROM compras_planes pl, cfg, m
WHERE pl.id = d.plan_id AND pl.base = cfg.base AND pl.origen = 'reconstruido'
  AND coalesce(pl.fecha_oc, pl.fecha) >= m.mes AND coalesce(pl.fecha_oc, pl.fecha) < (m.mes + interval '1 month')::date
  AND coalesce(d.razon, '') = '' AND coalesce(d.oc_unidades, d.comprado, 0) IS DISTINCT FROM coalesce(d.sugerido, -1);
WITH /*CTX*/,
m AS (SELECT date_trunc('month', coalesce(nullif(p->>'mes', '')::date, hoy))::date AS mes FROM cfg)
SELECT json_build_object('ok', true, 'mes', (SELECT mes FROM m)::text,
  'con_gerencia', (SELECT count(*) FROM compras_decisiones d JOIN compras_planes pl ON pl.id = d.plan_id
                   WHERE pl.base = cfg.base AND pl.origen = 'reconstruido' AND d.razon = 'gerencia'
                     AND coalesce(pl.fecha_oc, pl.fecha) >= (SELECT mes FROM m) AND coalesce(pl.fecha_oc, pl.fecha) < ((SELECT mes FROM m) + interval '1 month')::date)) AS r
FROM cfg;
