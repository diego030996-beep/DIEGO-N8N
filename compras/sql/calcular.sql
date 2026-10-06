-- Módulos 1 y 2: clasificación A/B (80/20 de la venta de los últimos N meses), C (vendidos fuera de ese periodo),
-- rotación y stock de seguridad / punto de reorden / máximo del mes.
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
per AS (SELECT (m.mes - make_interval(months => cfg.meses))::date AS ini, m.mes AS fin,
               (m.mes - make_interval(months => greatest(cfg.meses_c, cfg.meses)))::date AS ini_c FROM m, cfg),
vt AS (   -- venta real: tickets de punto de venta (menos devoluciones) + remisiones, sin cancelados ni montos anómalos
  SELECT v.origen, v.docto_id, v.fecha, CASE WHEN upper(v.tipo) = 'D' THEN -1 ELSE 1 END AS sg
  FROM ms_ventas v, cfg, per, go
  WHERE go.ok AND v.base = cfg.base AND v.fecha >= per.ini_c AND v.fecha < per.fin AND coalesce(v.estatus, '') <> 'C'
    AND abs(coalesce(v.importe, 0) + coalesce(v.impuestos, 0)) <= cfg.maxm
    AND ((v.origen = 'PV' AND upper(v.tipo) IN ('V', 'D')) OR (v.origen = 'VE' AND v.tipo = 'R'))),
dias AS (SELECT greatest(per.ini, coalesce((SELECT min(fecha) FROM vt), per.ini)) AS desde,
                greatest(per.ini_c, coalesce((SELECT min(fecha) FROM vt), per.ini_c)) AS desde_c FROM per),
nd AS (SELECT greatest(per.fin - dias.desde, 1) AS n, dias.desde, greatest(per.fin - dias.desde_c, 1) AS n_c, dias.desde_c FROM per, dias),
wk AS (    -- venta por artículo y por semana (para la variabilidad y la rotación)
  SELECT d.articulo_id, (vt.fecha - per.ini_c) / 7 AS semana, vt.fecha >= per.ini AS en_ab,
         sum(vt.sg * abs(d.unidades)) AS u, sum(vt.sg * abs(d.importe)) AS imp, count(DISTINCT vt.docto_id) FILTER (WHERE vt.sg > 0) AS tk,
         max(vt.fecha) FILTER (WHERE vt.sg > 0) AS uf
  FROM vt CROSS JOIN per JOIN ms_ventas_det d ON d.base = (SELECT base FROM cfg) AND d.origen = vt.origen AND d.docto_id = vt.docto_id
  WHERE d.articulo_id IS NOT NULL GROUP BY 1, 2, 3),
vd0 AS (   -- u/imp = periodo A/B (6 meses); *_c = periodo largo (12 meses) para los C y para contar ventas
  SELECT articulo_id, sum(u) FILTER (WHERE en_ab) AS u, sum(imp) FILTER (WHERE en_ab) AS imp,
         sum(u * u) FILTER (WHERE en_ab) AS s2, count(*) FILTER (WHERE en_ab AND u > 0) AS sem,
         sum(u) AS u_c, sum(imp) AS imp_c, sum(u * u) AS s2_c, count(*) FILTER (WHERE u > 0) AS sem_c, sum(tk) AS tickets, max(uf) AS ultima
  FROM wk GROUP BY 1),
/*EXCL*/,
vd AS (SELECT vd0.* FROM vd0 WHERE NOT EXISTS (SELECT 1 FROM excl WHERE excl.articulo_id = vd0.articulo_id)),
ov AS (SELECT o.* FROM compras_articulos o, cfg WHERE o.base = cfg.base),
art AS (SELECT a.articulo_id, a.clave, a.nombre, a.unidad FROM ms_articulos a, cfg WHERE a.base = cfg.base),
cand AS (   -- A/B: con venta neta en los 6 meses
  SELECT vd.articulo_id, vd.u, vd.imp, vd.s2, vd.sem, vd.tickets, vd.ultima, art.clave, art.nombre, art.unidad,
         ov.clase AS clase_f, ov.proveedor_id AS prov_f, ov.empaque, ov.minimo AS min_f, ov.maximo AS max_f
  FROM vd LEFT JOIN art USING (articulo_id) LEFT JOIN ov USING (articulo_id)
  WHERE vd.u > 0 AND vd.imp > 0),
abc0 AS (SELECT cand.*, sum(imp) OVER (ORDER BY imp DESC, articulo_id ROWS UNBOUNDED PRECEDING) AS acum, sum(imp) OVER () AS tot,
                NULL::text AS clase_c FROM cand),
cc AS (     -- C: se vendieron en los 12 meses pero no en los 6 meses del A/B
  SELECT vd.articulo_id, vd.u_c AS u, vd.imp_c AS imp, vd.s2_c AS s2, vd.sem_c AS sem, vd.tickets, vd.ultima, art.clave, art.nombre, art.unidad,
         ov.clase AS clase_f, ov.proveedor_id AS prov_f, ov.empaque, ov.minimo AS min_f, ov.maximo AS max_f,
         NULL::numeric AS acum, NULL::numeric AS tot, 'C'::text AS clase_c
  FROM vd LEFT JOIN art USING (articulo_id) LEFT JOIN ov USING (articulo_id)
  WHERE vd.u_c > 0 AND NOT EXISTS (SELECT 1 FROM cand WHERE cand.articulo_id = vd.articulo_id)),
abc AS (SELECT * FROM abc0 UNION ALL SELECT * FROM cc),
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
    WHERE (d.datos->>'ARTICULO_ID') ~ '^[0-9]{1,18}\Z') z
  ORDER BY z.articulo_id, z.fecha DESC),
prv AS (SELECT p.pk AS proveedor_id, p.datos->>'NOMBRE' AS nombre FROM ms_raw p, cfg WHERE p.base = cfg.base AND p.tabla = 'PROVEEDORES'),
c1 AS (
  SELECT abc.*, coalesce(nullif(abc.prov_f, ''), up.prov) AS prov_id,
         coalesce(nullif(abc.clase_f, ''), abc.clase_c, CASE WHEN abc.acum - abc.imp < cfg.corte * abc.tot THEN 'A' ELSE 'B' END) AS clase,
         CASE WHEN abc.clase_c = 'C' THEN nd.n_c ELSE nd.n END AS ndias
  FROM abc LEFT JOIN up USING (articulo_id) CROSS JOIN cfg CROSS JOIN nd),
c2 AS (
  SELECT c1.*, c1.u / c1.ndias AS vdia,
         greatest(ceil(c1.ndias / 7.0), 1) AS nsem,
         cp.dias_entrega AS ent_p, coalesce(cp.dias_entrega, cfg.ent_def) AS ent,
         CASE c1.clase WHEN 'A' THEN cfg.seg_a WHEN 'B' THEN cfg.seg_b ELSE cfg.seg_c END AS seg,
         CASE c1.clase WHEN 'A' THEN cfg.inv_a WHEN 'B' THEN cfg.inv_b ELSE cfg.inv_c END AS inv,
         CASE c1.clase WHEN 'A' THEN cfg.ns_a WHEN 'B' THEN cfg.ns_b ELSE cfg.ns_c END AS ns,
         CASE WHEN c1.clase = 'A' THEN coalesce(cfg.rev_a, 7) ELSE coalesce(cp.frec_b, cfg.frec_b) END AS rev,
         CASE WHEN c1.clase = 'C' THEN cfg.min_c ELSE 1 END AS piso,
         coalesce(nullif(cp.nombre, ''), prv.nombre) AS prov_nom
  FROM c1 CROSS JOIN cfg
  LEFT JOIN compras_proveedores cp ON cp.base = cfg.base AND cp.proveedor_id = c1.prov_id
  LEFT JOIN prv ON prv.proveedor_id = c1.prov_id),
c3 AS (   -- variabilidad semanal (con las semanas sin venta en cero) y rotación = % de semanas con venta
  SELECT c2.*, least(c2.sem::numeric / c2.nsem, 1) AS rot,
         sqrt(greatest(c2.s2 / c2.nsem - power(c2.u / c2.nsem, 2), 0)) / sqrt(7) AS sd,
         CASE WHEN c2.ns >= 99 THEN 2.33 WHEN c2.ns >= 98 THEN 2.05 WHEN c2.ns >= 97 THEN 1.88 WHEN c2.ns >= 95 THEN 1.65
              WHEN c2.ns >= 90 THEN 1.28 WHEN c2.ns >= 85 THEN 1.04 WHEN c2.ns >= 80 THEN 0.84 ELSE 0.67 END AS z
  FROM c2),
c4 AS (
  SELECT c3.*, CASE WHEN c3.rot >= cfg.rot_alta THEN 'alta' WHEN c3.rot >= cfg.rot_media THEN 'media' ELSE 'baja' END AS rotacion,
         cfg.metodo AS met
  FROM c3, cfg),
c5 AS (   -- stock de seguridad (= mínimo), punto de reorden y máximo
  SELECT c4.*,
         greatest(coalesce(c4.min_f,
           CASE WHEN c4.met = 'simple' THEN ceil(c4.vdia * (c4.ent + c4.seg))
                WHEN c4.rotacion = 'baja' THEN c4.piso
                ELSE ceil(c4.z * c4.sd * sqrt(c4.ent + c4.rev)) END), c4.piso) AS ss,
         CASE WHEN c4.met = 'simple' THEN 0 ELSE ceil(c4.vdia * (c4.ent + c4.rev)) END AS dem_lt
  FROM c4),
c6 AS (
  SELECT c5.*,
         CASE WHEN c5.met = 'simple' THEN c5.ss ELSE greatest(c5.dem_lt + CASE WHEN c5.rotacion = 'baja' THEN 0 ELSE c5.ss END, c5.ss) END AS pr
  FROM c5),
c7 AS (SELECT c6.*, coalesce(c6.max_f, c6.pr + ceil(c6.vdia * c6.inv)) AS mx0 FROM c6),
c8 AS (SELECT c7.*, greatest(c7.mx0, c7.pr + 1) AS mx,
              concat_ws('; ',
                CASE WHEN c7.tickets <= 1 THEN 'solo 1 venta en ' || (SELECT meses_c FROM cfg) || ' meses' END,
                CASE WHEN c7.mx0 <= c7.pr THEN 'máximo no era mayor al punto de reorden, se ajustó' END,
                CASE WHEN c7.prov_id IS NULL THEN 'sin proveedor' END,
                CASE WHEN c7.prov_id IS NOT NULL AND c7.ent_p IS NULL THEN 'proveedor sin días de entrega (se usó ' || c7.ent || ')' END) AS alerta
       FROM c7)
INSERT INTO compras_maxmin (mes, base, articulo_id, clave, articulo, unidad, proveedor_id, proveedor, clase, venta, unidades, pct, pct_acum,
  venta_diaria, dias_entrega, dias_seguridad, dias_inventario, empaque, minimo, maximo, origen, alerta, periodo_ini, periodo_fin, dias_periodo, por, calculado,
  punto_reorden, rotacion, semanas_venta, semanas, tickets, desv_diaria, nivel_servicio, dias_revision, metodo, ultima_venta)
SELECT m.mes, cfg.base, c8.articulo_id, c8.clave, c8.nombre, c8.unidad, c8.prov_id, c8.prov_nom, c8.clase, round(c8.imp, 2), c8.u,
       round(c8.imp / nullif(c8.tot, 0), 6), round(c8.acum / nullif(c8.tot, 0), 6), round(c8.vdia, 4), c8.ent, c8.seg, c8.inv, c8.empaque,
       c8.ss, c8.mx, CASE WHEN c8.min_f IS NOT NULL OR c8.max_f IS NOT NULL THEN 'manual' ELSE 'calculado' END, nullif(c8.alerta, ''),
       CASE WHEN c8.clase_c = 'C' THEN nd.desde_c ELSE nd.desde END, (m.mes - 1), c8.ndias, cfg.por, now(),
       c8.pr, c8.rotacion, c8.sem, c8.nsem, c8.tickets, round(c8.sd::numeric, 4), c8.ns, c8.rev, c8.met, c8.ultima
FROM c8, cfg, m, nd;
-- @fin_calculo
WITH /*CTX*/,
m AS (SELECT date_trunc('month', coalesce(nullif(p->>'mes', '')::date, hoy))::date AS mes FROM cfg),
x AS (SELECT y.* FROM compras_maxmin y, cfg, m WHERE y.base = cfg.base AND y.mes = m.mes)
SELECT json_build_object('ok', true, 'base', (SELECT base FROM cfg), 'mes', (SELECT mes FROM m)::text,
  'productos', (SELECT count(*) FROM x), 'a', (SELECT count(*) FROM x WHERE clase = 'A'), 'b', (SELECT count(*) FROM x WHERE clase = 'B'), 'c', (SELECT count(*) FROM x WHERE clase = 'C'),
  'venta_a', (SELECT round(sum(venta) FILTER (WHERE clase = 'A') / nullif(sum(venta) FILTER (WHERE clase IN ('A', 'B')), 0) * 100, 1) FROM x),
  'alertas', (SELECT count(*) FROM x WHERE alerta IS NOT NULL),
  'rotacion', (SELECT json_object_agg(coalesce(rotacion, '-'), n) FROM (SELECT rotacion, count(*) AS n FROM x GROUP BY 1) z),
  'una_venta', (SELECT count(*) FROM x WHERE tickets <= 1),
  'sin_proveedor', (SELECT count(*) FROM x WHERE proveedor_id IS NULL),
  'desde', (SELECT min(periodo_ini) FILTER (WHERE clase IN ('A', 'B')) FROM x)::text, 'hasta', (SELECT max(periodo_fin) FROM x)::text,
  'calculado', (SELECT max(calculado) FROM x)) AS r;
