-- Guarda lo que decides comprar (y la razón si es distinto al sugerido).
-- p = {proveedor_id, proveedor, clase: 'A'|'B', folio, lineas: [{articulo_id, clave, articulo, unidad, clase, existencia, pendiente, minimo, maximo, sugerido, comprado, razon, nota}]}
SET LOCAL statement_timeout = '30s';
SET LOCAL lock_timeout = '5s';
WITH /*CTX*/
INSERT INTO compras_planes (base, fecha, proveedor_id, proveedor, clase, origen, folio, por)
SELECT cfg.base, cfg.hoy, cfg.p->>'proveedor_id', cfg.p->>'proveedor', cfg.p->>'clase', 'planeador', nullif(cfg.p->>'folio', ''), cfg.por FROM cfg
ON CONFLICT (base, fecha, proveedor_id) WHERE origen = 'planeador' DO UPDATE
  SET clase = CASE WHEN position(EXCLUDED.clase IN compras_planes.clase) > 0 THEN compras_planes.clase ELSE 'AB' END,
      folio = coalesce(EXCLUDED.folio, compras_planes.folio),
      docto_cm_id = CASE WHEN EXCLUDED.folio IS NOT NULL AND EXCLUDED.folio IS DISTINCT FROM compras_planes.folio THEN NULL ELSE compras_planes.docto_cm_id END,
      por = EXCLUDED.por, modificado = now();

WITH /*CTX*/,
pl AS (SELECT pl.id FROM compras_planes pl, cfg WHERE pl.base = cfg.base AND pl.fecha = cfg.hoy AND pl.origen = 'planeador'
         AND pl.proveedor_id = cfg.p->>'proveedor_id'),
l AS (SELECT x.* FROM cfg, jsonb_to_recordset(cfg.p->'lineas') AS x(articulo_id bigint, clave text, articulo text, unidad text, clase text,
        existencia numeric, pendiente numeric, minimo numeric, maximo numeric, sugerido numeric, comprado numeric, razon text, nota text))
INSERT INTO compras_decisiones (plan_id, articulo_id, clave, articulo, unidad, clase, existencia, pendiente, minimo, maximo, sugerido, comprado, razon, nota, fuente, por)
SELECT pl.id, l.articulo_id, l.clave, l.articulo, l.unidad, l.clase, l.existencia, l.pendiente, l.minimo, l.maximo, l.sugerido, l.comprado,
       CASE WHEN l.comprado = l.sugerido THEN 'igual' ELSE nullif(l.razon, '') END, nullif(l.nota, ''), 'planeador', cfg.por
FROM pl, l, cfg
ON CONFLICT (plan_id, articulo_id) DO UPDATE
  SET comprado = EXCLUDED.comprado, razon = EXCLUDED.razon, nota = EXCLUDED.nota, existencia = EXCLUDED.existencia, pendiente = EXCLUDED.pendiente,
      minimo = EXCLUDED.minimo, maximo = EXCLUDED.maximo, sugerido = EXCLUDED.sugerido, clase = EXCLUDED.clase, por = EXCLUDED.por, modificado = now();

/*LIGAR*/
WITH /*CTX*/
SELECT json_build_object('ok', true, 'plan', json_build_object('id', pl.id, 'folio', pl.folio, 'folio_oc', pl.folio_oc, 'clase', pl.clase),
  'lineas', (SELECT count(*) FROM compras_decisiones d WHERE d.plan_id = pl.id)) AS r
FROM compras_planes pl, cfg WHERE pl.base = cfg.base AND pl.fecha = cfg.hoy AND pl.origen = 'planeador' AND pl.proveedor_id = cfg.p->>'proveedor_id';
