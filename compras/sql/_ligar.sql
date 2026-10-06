-- Módulo 4: liga cada plan con su orden de compra de Microsip.
-- 1) por folio escrito en la página (se comparan solo los números: "O62", "62" y "O00000062" son la misma)
WITH /*CTX*/, /*OC*/,
x0 AS (SELECT pl.id AS plan_id, o.id, o.folio, o.fecha, pl.fecha AS pf
       FROM compras_planes pl JOIN cfg ON pl.base = cfg.base
       JOIN oc o ON ltrim(regexp_replace(o.folio, '\D', '', 'g'), '0') = ltrim(regexp_replace(pl.folio, '\D', '', 'g'), '0')
               AND o.prov = pl.proveedor_id
       WHERE pl.docto_cm_id IS NULL AND regexp_replace(coalesce(pl.folio, ''), '\D', '', 'g') <> ''
         AND NOT EXISTS (SELECT 1 FROM compras_planes q WHERE q.base = cfg.base AND q.docto_cm_id = o.id)),
x1 AS (SELECT DISTINCT ON (id) * FROM x0 ORDER BY id, pf DESC),
x2 AS (SELECT DISTINCT ON (plan_id) * FROM x1 ORDER BY plan_id, fecha)
UPDATE compras_planes pl SET docto_cm_id = x2.id, folio_oc = x2.folio, fecha_oc = x2.fecha, ligado = now()
FROM x2 WHERE pl.id = x2.plan_id;
-- 2) automático: la primera OC del mismo proveedor capturada entre el día del plan y los días para ligar
WITH /*CTX*/, /*OC*/,
y0 AS (SELECT pl.id AS plan_id, o.id, o.folio, o.fecha, pl.fecha AS pf
       FROM compras_planes pl JOIN cfg ON pl.base = cfg.base
       JOIN oc o ON o.prov = pl.proveedor_id AND o.fecha BETWEEN pl.fecha AND pl.fecha + cfg.dias_ligar
       WHERE pl.origen = 'planeador' AND pl.docto_cm_id IS NULL AND regexp_replace(coalesce(pl.folio, ''), '\D', '', 'g') = ''
         AND pl.fecha >= cfg.hoy - 90
         AND NOT EXISTS (SELECT 1 FROM compras_planes q WHERE q.base = cfg.base AND q.docto_cm_id = o.id)),
y1 AS (SELECT DISTINCT ON (id) * FROM y0 ORDER BY id, pf DESC),
y2 AS (SELECT DISTINCT ON (plan_id) * FROM y1 ORDER BY plan_id, fecha)
UPDATE compras_planes pl SET docto_cm_id = y2.id, folio_oc = y2.folio, fecha_oc = y2.fecha, ligado = now()
FROM y2 WHERE pl.id = y2.plan_id;
-- 3) unidades reales de la OC en cada decisión
WITH /*CTX*/,
lk AS (SELECT pl.id AS plan_id, pl.docto_cm_id FROM compras_planes pl, cfg
       WHERE pl.base = cfg.base AND pl.docto_cm_id IS NOT NULL AND coalesce(pl.fecha_oc, pl.fecha) >= cfg.hoy - 120),
ids AS (SELECT docto_cm_id AS id FROM lk), /*OCD*/,
u AS (SELECT lk.plan_id, ocd.articulo_id, ocd.u FROM lk JOIN ocd ON ocd.id = lk.docto_cm_id)
UPDATE compras_decisiones d SET oc_unidades = u.u FROM u
WHERE d.plan_id = u.plan_id AND d.articulo_id = u.articulo_id AND d.oc_unidades IS DISTINCT FROM u.u;
-- 4) artículos que vienen en la OC pero no estaban en el plan: se agregan para que se explique la razón
WITH /*CTX*/,
lk AS (SELECT pl.id AS plan_id, pl.docto_cm_id, coalesce(pl.fecha_oc, pl.fecha) AS f FROM compras_planes pl, cfg
       WHERE pl.base = cfg.base AND pl.origen = 'planeador' AND pl.docto_cm_id IS NOT NULL AND coalesce(pl.fecha_oc, pl.fecha) >= cfg.hoy - 120),
ids AS (SELECT docto_cm_id AS id FROM lk), /*OCD*/, /*EXCL*/
INSERT INTO compras_decisiones (plan_id, articulo_id, clave, articulo, unidad, clase, minimo, maximo, comprado, oc_unidades, fuente, por)
SELECT lk.plan_id, ocd.articulo_id, coalesce(mm.clave, a.clave), coalesce(mm.articulo, a.nombre), coalesce(mm.unidad, a.unidad), mm.clase,
       mm.minimo, mm.maximo, ocd.u, ocd.u, 'en la OC, no estaba en el plan', 'automático'
FROM lk JOIN ocd ON ocd.id = lk.docto_cm_id CROSS JOIN cfg
LEFT JOIN compras_maxmin mm ON mm.base = cfg.base AND mm.mes = date_trunc('month', lk.f)::date AND mm.articulo_id = ocd.articulo_id
LEFT JOIN ms_articulos a ON a.base = cfg.base AND a.articulo_id = ocd.articulo_id
WHERE NOT EXISTS (SELECT 1 FROM excl WHERE excl.articulo_id = ocd.articulo_id)
ON CONFLICT (plan_id, articulo_id) DO NOTHING;
