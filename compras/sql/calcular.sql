-- Módulos 1 y 2: clasificación A/B (80/20 de la venta de los últimos N meses) y máximos/mínimos del mes.
-- p = {mes: 'YYYY-MM-01', solo_si_falta: 'si'|''}. Se guarda una foto por mes en compras_maxmin (evidencia).
SET LOCAL statement_timeout = '120s';
SET LOCAL lock_timeout = '10s';
/*ESQUEMA*/
WITH /*CTX*/,
m AS (SELECT date_trunc('month', coalesce(nullif(p->>'mes', '')::date, hoy))::date AS mes, coalesce(p->>'solo_si_falta', '') = 'si' AS ssf FROM cfg)
DELETE FROM compras_maxmin x USING cfg, m
WHERE x.base = cfg.base AND x.mes = m.mes AND NOT m.ssf;

WITH /*CTX*/,
m AS (SELECT date_trunc('month', coalesce(nullif(p->>'mes', '')::date, hoy))::date AS mes FROM cfg),
go AS (SELECT NOT EXISTS (SELECT 1 FROM compras_maxmin y, cfg, m WHERE y.base = cfg.base AND y.mes = m.mes) AS ok),
per AS (SELECT (m.mes - make_interval(months => cfg.meses))::date AS ini, m.mes AS fin FROM m, cfg),
vt AS (   -- venta real: tickets de punto de venta (menos devoluciones) + remisiones, sin cancelados ni montos anómalos
  SELECT v.origen, v.docto_id, v.fecha, CASE WHEN upper(v.tipo) = 'D' THEN -1 ELSE 1 END AS sg
  FROM ms_ventas v, cfg, per, go
  WHERE go.ok AND v.base = cfg.base AND v.fecha >= per.ini AND v.fecha < per.fin AND coalesce(v.estatus, '') <> 'C'
    AND abs(coalesce(v.importe, 0) + coalesce(v.impuestos, 0)) <= cfg.maxm
    AND ((v.origen = 'PV' AND upper(v.tipo) IN ('V', 'D')) OR (v.origen = 'VE' AND v.tipo = 'R'))),
dias AS (SELECT greatest(per.ini, coalesce((SELECT min(fecha) FROM vt), per.ini)) AS desde FROM per),
nd AS (SELECT greatest(per.fin - dias.desde, 1) AS n, dias.desde FROM per, dias),
vd AS (
  SELECT d.articulo_id, sum(vt.sg * abs(d.unidades)) AS u, sum(vt.sg * abs(d.importe)) AS imp
  FROM vt JOIN ms_ventas_det d ON d.base = (SELECT base FROM cfg) AND d.origen = vt.origen AND d.docto_id = vt.docto_id
  WHERE d.articulo_id IS NOT NULL GROUP BY 1),
ov AS (SELECT o.* FROM compras_articulos o, cfg WHERE o.base = cfg.base),
art AS (SELECT a.articulo_id, a.clave, a.nombre, a.unidad, coalesce(a.estatus, '') AS estatus,
               coalesce(a.nombre, '') || ' ' || coalesce(a.linea, '') || ' ' || coalesce(a.grupo, '') AS texto
        FROM ms_articulos a, cfg WHERE a.base = cfg.base),
cand AS (
  SELECT vd.articulo_id, vd.u, vd.imp, art.clave, art.nombre, art.unidad,
         ov.clase AS clase_f, ov.proveedor_id AS prov_f, ov.empaque, ov.minimo AS min_f, ov.maximo AS max_f
  FROM vd LEFT JOIN art USING (articulo_id) LEFT JOIN ov USING (articulo_id) CROSS JOIN cfg
  WHERE vd.u > 0 AND vd.imp > 0 AND NOT coalesce(ov.excluir, false) AND upper(coalesce(art.estatus, '')) <> 'B'
    AND (cfg.excl = '' OR coalesce(art.texto, '') !~* cfg.excl)),
abc AS (SELECT cand.*, sum(imp) OVER (ORDER BY imp DESC, articulo_id ROWS UNBOUNDED PRECEDING) AS acum, sum(imp) OVER () AS tot FROM cand),
cmh AS (  -- documentos de compra (orden, recepción, compra) para saber el proveedor habitual de cada artículo
  SELECT r.datos->>'DOCTO_CM_ID' AS id, r.datos->>'PROVEEDOR_ID' AS prov, coalesce(r.fecha, left(r.datos->>'FECHA', 10)::date) AS fecha
  FROM ms_raw r, cfg, go, m
  WHERE go.ok AND r.base = cfg.base AND r.tabla = 'DOCTOS_CM' AND upper(coalesce(r.datos->>'TIPO_DOCTO', '')) IN ('O', 'R', 'C')
    AND upper(coalesce(r.datos->>'ESTATUS', '')) <> 'C' AND upper(coalesce(r.datos->>'CANCELADO', 'N')) <> 'S'
    AND coalesce(r.fecha, left(r.datos->>'FECHA', 10)::date) < (m.mes + interval '1 month')::date),
up AS (   -- proveedor de la última compra del artículo
  SELECT DISTINCT ON (z.articulo_id) z.articulo_id, z.prov FROM (
    SELECT (d.datos->>'ARTICULO_ID')::bigint AS articulo_id, cmh.prov, cmh.fecha
    FROM cmh JOIN ms_raw d ON d.base = (SELECT base FROM cfg) AND d.tabla = 'DOCTOS_CM_DET' AND d.datos->>'DOCTO_CM_ID' = cmh.id
    WHERE (d.datos->>'ARTICULO_ID') ~ '^[0-9]+$') z
  ORDER BY z.articulo_id, z.fecha DESC),
prv AS (SELECT p.pk AS proveedor_id, p.datos->>'NOMBRE' AS nombre FROM ms_raw p, cfg WHERE p.base = cfg.base AND p.tabla = 'PROVEEDORES'),
c1 AS (
  SELECT abc.*, coalesce(nullif(abc.prov_f, ''), up.prov) AS prov_id,
         coalesce(nullif(abc.clase_f, ''), CASE WHEN abc.acum - abc.imp < cfg.corte * abc.tot THEN 'A' ELSE 'B' END) AS clase,
         abc.u / nd.n AS vdia
  FROM abc LEFT JOIN up USING (articulo_id) CROSS JOIN cfg CROSS JOIN nd),
c2 AS (
  SELECT c1.*, cp.dias_entrega AS ent_p, coalesce(cp.dias_entrega, cfg.ent_def) AS ent,
         CASE WHEN c1.clase = 'A' THEN cfg.seg_a ELSE cfg.seg_b END AS seg,
         CASE WHEN c1.clase = 'A' THEN cfg.inv_a ELSE cfg.inv_b END AS inv,
         coalesce(nullif(cp.nombre, ''), prv.nombre) AS prov_nom
  FROM c1 CROSS JOIN cfg
  LEFT JOIN compras_proveedores cp ON cp.base = cfg.base AND cp.proveedor_id = c1.prov_id
  LEFT JOIN prv ON prv.proveedor_id = c1.prov_id),
c3 AS (SELECT c2.*, ceil(c2.vdia * (c2.ent + c2.seg)) AS min_c, ceil(c2.vdia * c2.inv) AS rango FROM c2),
c4 AS (SELECT c3.*, greatest(coalesce(c3.min_f, c3.min_c), 1) AS mn, coalesce(c3.max_f, c3.min_c + c3.rango) AS mx0 FROM c3),
c5 AS (SELECT c4.*, greatest(c4.mx0, c4.mn + 1) AS mx,
              concat_ws('; ',
                CASE WHEN c4.min_f IS NULL AND c4.min_c < 1 THEN 'mínimo daba 0, se dejó en 1' END,
                CASE WHEN c4.mx0 <= c4.mn THEN 'máximo no era mayor al mínimo, se ajustó' END,
                CASE WHEN c4.prov_id IS NULL THEN 'sin proveedor' END,
                CASE WHEN c4.prov_id IS NOT NULL AND c4.ent_p IS NULL THEN 'proveedor sin días de entrega (se usó ' || c4.ent || ')' END) AS alerta
       FROM c4)
INSERT INTO compras_maxmin (mes, base, articulo_id, clave, articulo, unidad, proveedor_id, proveedor, clase, venta, unidades, pct, pct_acum,
  venta_diaria, dias_entrega, dias_seguridad, dias_inventario, empaque, minimo, maximo, origen, alerta, periodo_ini, periodo_fin, dias_periodo, por, calculado)
SELECT m.mes, cfg.base, c5.articulo_id, c5.clave, c5.nombre, c5.unidad, c5.prov_id, c5.prov_nom, c5.clase, round(c5.imp, 2), c5.u,
       round(c5.imp / nullif(c5.tot, 0), 6), round(c5.acum / nullif(c5.tot, 0), 6), round(c5.vdia, 4), c5.ent, c5.seg, c5.inv, c5.empaque,
       c5.mn, c5.mx, CASE WHEN c5.min_f IS NOT NULL OR c5.max_f IS NOT NULL THEN 'manual' ELSE 'calculado' END, nullif(c5.alerta, ''),
       nd.desde, (m.mes - 1), nd.n, cfg.por, now()
FROM c5, cfg, m, nd;
-- @fin_calculo
WITH /*CTX*/,
m AS (SELECT date_trunc('month', coalesce(nullif(p->>'mes', '')::date, hoy))::date AS mes FROM cfg),
x AS (SELECT y.* FROM compras_maxmin y, cfg, m WHERE y.base = cfg.base AND y.mes = m.mes)
SELECT json_build_object('ok', true, 'base', (SELECT base FROM cfg), 'mes', (SELECT mes FROM m)::text,
  'productos', (SELECT count(*) FROM x), 'a', (SELECT count(*) FROM x WHERE clase = 'A'), 'b', (SELECT count(*) FROM x WHERE clase = 'B'),
  'venta_a', (SELECT round(sum(venta) FILTER (WHERE clase = 'A') / nullif(sum(venta), 0) * 100, 1) FROM x),
  'alertas', (SELECT count(*) FROM x WHERE alerta IS NOT NULL),
  'sin_proveedor', (SELECT count(*) FROM x WHERE proveedor_id IS NULL),
  'desde', (SELECT min(periodo_ini) FROM x)::text, 'hasta', (SELECT max(periodo_fin) FROM x)::text,
  'calculado', (SELECT max(calculado) FROM x)) AS r;
