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

WITH /*CTX*/, /*OC*/, /*EQV*/, /*LT*/,
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
du AS (    -- venta por documento, con las presentaciones (tonelada, millar, viaje…) convertidas a su artículo base
  SELECT coalesce(q.base_id, d.articulo_id) AS articulo_id, vt.origen, vt.docto_id, vt.fecha, vt.sg,
         sum(abs(d.unidades) * coalesce(q.factor, 1)) AS u, sum(abs(d.importe)) AS imp
  FROM vt JOIN ms_ventas_det d ON d.base = (SELECT base FROM cfg) AND d.origen = vt.origen AND d.docto_id = vt.docto_id
  LEFT JOIN eqv q ON q.articulo_id = d.articulo_id
  WHERE d.articulo_id IS NOT NULL GROUP BY 1, 2, 3, 4, 5),
wk AS (    -- venta por artículo y por semana (para la variabilidad y la rotación)
  SELECT du.articulo_id, (du.fecha - per.ini_c) / 7 AS semana, du.fecha >= per.ini AS en_ab,
         sum(du.sg * du.u) AS u, sum(du.sg * du.imp) AS imp, count(DISTINCT du.docto_id) FILTER (WHERE du.sg > 0) AS tk,
         max(du.fecha) FILTER (WHERE du.sg > 0) AS uf, max(du.u) FILTER (WHERE du.sg > 0) AS umax
  FROM du CROSS JOIN per GROUP BY 1, 2, 3),
vd0 AS (   -- u/imp = periodo A/B (6 meses); *_c = periodo largo (12 meses) para los C y para contar ventas
  SELECT articulo_id, sum(u) FILTER (WHERE en_ab) AS u, sum(imp) FILTER (WHERE en_ab) AS imp,
         sum(u * u) FILTER (WHERE en_ab) AS s2, count(*) FILTER (WHERE en_ab AND u > 0) AS sem,
         sum(u) AS u_c, sum(imp) AS imp_c, sum(u * u) AS s2_c, count(*) FILTER (WHERE u > 0) AS sem_c, sum(tk) AS tickets, max(uf) AS ultima,
         max(umax) AS umax
  FROM wk GROUP BY 1),
/*EXCLSOLO*/,
vd AS (SELECT vd0.* FROM vd0 WHERE NOT EXISTS (SELECT 1 FROM excl WHERE excl.articulo_id = vd0.articulo_id)),
ov AS (SELECT o.* FROM compras_articulos o, cfg WHERE o.base = cfg.base),
art AS (SELECT a.articulo_id, a.clave, a.nombre, a.unidad FROM ms_articulos a, cfg WHERE a.base = cfg.base),
cand AS (   -- A/B: con venta neta en los 6 meses
  SELECT vd.articulo_id, vd.u, vd.imp, vd.s2, vd.sem, vd.tickets, vd.ultima, vd.umax, art.clave, art.nombre, art.unidad,
         ov.clase AS clase_f, ov.proveedor_id AS prov_f, ov.empaque, ov.minimo AS min_f, ov.maximo AS max_f
  FROM vd LEFT JOIN art USING (articulo_id) LEFT JOIN ov USING (articulo_id)
  WHERE vd.u > 0 AND vd.imp > 0),
abc0 AS (SELECT cand.*, sum(imp) OVER (ORDER BY imp DESC, articulo_id ROWS UNBOUNDED PRECEDING) AS acum, sum(imp) OVER () AS tot,
                NULL::text AS clase_c FROM cand),
cc AS (     -- C: se vendieron en los 12 meses pero no en los 6 meses del A/B
  SELECT vd.articulo_id, vd.u_c AS u, vd.imp_c AS imp, vd.s2_c AS s2, vd.sem_c AS sem, vd.tickets, vd.ultima, vd.umax, art.clave, art.nombre, art.unidad,
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
    SELECT coalesce(q.base_id, (d.datos->>'ARTICULO_ID')::bigint) AS articulo_id, cmh.prov, cmh.fecha, cmh.id
    FROM cmh JOIN ms_raw d ON d.base = (SELECT base FROM cfg) AND d.tabla = 'DOCTOS_CM_DET' AND d.datos->>'DOCTO_CM_ID' = cmh.id
    LEFT JOIN eqv q ON q.articulo_id = (CASE WHEN (d.datos->>'ARTICULO_ID') ~ '^[0-9]{1,18}\Z' THEN (d.datos->>'ARTICULO_ID')::bigint END)
    WHERE (d.datos->>'ARTICULO_ID') ~ '^[0-9]{1,18}\Z') z
  ORDER BY z.articulo_id, z.fecha DESC, length(z.id) DESC, z.id DESC),
hcov AS (  -- historial diario de existencias dentro del periodo (para distinguir "vende poco" de "no había")
  SELECT count(DISTINCT h.fecha) AS n FROM ms_existencias_hist h, cfg, per WHERE h.base = cfg.base AND h.fecha >= per.ini AND h.fecha < per.fin),
hag AS (
  SELECT z.articulo_id, count(*) FILTER (WHERE z.e <= 0) AS agot, count(*) AS dias FROM (
    SELECT coalesce(q.base_id, h.articulo_id) AS articulo_id, h.fecha, sum(coalesce(h.existencia, 0) * coalesce(q.factor, 1)) AS e
    FROM ms_existencias_hist h CROSS JOIN cfg CROSS JOIN per LEFT JOIN eqv q ON q.articulo_id = h.articulo_id
    WHERE h.base = cfg.base AND h.fecha >= per.ini AND h.fecha < per.fin AND (cfg.alm = '' OR coalesce(h.almacen, '') ~* cfg.alm)
      AND (SELECT n FROM hcov) >= 30
    GROUP BY 1, 2) z GROUP BY 1),
pres AS (  -- qué presentaciones se suman a cada artículo base
  SELECT q.base_id AS articulo_id, string_agg(a.nombre || ' (×' || trim(to_char(q.factor, 'FM999999990.####')) || ')', '; ') AS txt
  FROM eqv q CROSS JOIN cfg JOIN ms_articulos a ON a.base = cfg.base AND a.articulo_id = q.articulo_id GROUP BY 1),
pol AS (SELECT p.articulo_id, p.politica, p.minimo FROM compras_politica p, cfg WHERE p.base = cfg.base),
c1 AS (
  SELECT abc.*, coalesce(nullif(abc.prov_f, ''), up.prov) AS prov_id,
         coalesce(nullif(abc.clase_f, ''), abc.clase_c, CASE WHEN abc.acum - abc.imp < cfg.corte * abc.tot THEN 'A'
                                                             WHEN abc.acum - abc.imp < cfg.corte_b * abc.tot THEN 'B' ELSE 'C' END) AS clase,
         CASE WHEN abc.clase_c = 'C' THEN nd.n_c ELSE nd.n END AS ndias
  FROM abc LEFT JOIN up USING (articulo_id) CROSS JOIN cfg CROSS JOIN nd),
c2 AS (
  SELECT c1.*,
         -- si estuvo agotado parte del periodo, la venta diaria se calcula sobre los días que sí hubo (máximo la mitad del periodo)
         c1.u / c1.ndias / (1 - least(coalesce(hag.agot::numeric / nullif(hag.dias, 0), 0), 0.5)) AS vdia,
         coalesce(hag.agot, 0) AS agot, pol.politica, pol.minimo AS pol_min, ltp.medido AS lt_med,
         greatest(ceil(c1.ndias / 7.0), 1) AS nsem,
         ltp.dias AS ent_p, coalesce(ltp.dias, cfg.ent_def) AS ent,
         CASE c1.clase WHEN 'A' THEN cfg.seg_a WHEN 'B' THEN cfg.seg_b ELSE cfg.seg_c END AS seg,
         CASE c1.clase WHEN 'A' THEN cfg.inv_a WHEN 'B' THEN cfg.inv_b ELSE cfg.inv_c END AS inv,
         CASE c1.clase WHEN 'A' THEN cfg.ns_a WHEN 'B' THEN cfg.ns_b ELSE cfg.ns_c END AS ns,
         CASE WHEN c1.clase = 'A' THEN coalesce(cfg.rev_a, 7) ELSE coalesce(cp.frec_b, cfg.frec_b) END AS rev,
         CASE WHEN c1.clase = 'C' THEN cfg.min_c ELSE 1 END AS piso,
         coalesce(nullif(cp.nombre, ''), prv.nombre) AS prov_nom
  FROM c1 CROSS JOIN cfg
  LEFT JOIN compras_proveedores cp ON cp.base = cfg.base AND cp.proveedor_id = c1.prov_id
  LEFT JOIN ltp ON ltp.prov = c1.prov_id
  LEFT JOIN hag ON hag.articulo_id = c1.articulo_id
  LEFT JOIN pol ON pol.articulo_id = c1.articulo_id
  LEFT JOIN prv ON prv.proveedor_id = c1.prov_id),
c3 AS (   -- variabilidad semanal (con las semanas sin venta en cero) y rotación = % de semanas con venta
  SELECT c2.*, least(c2.sem::numeric / c2.nsem, 1) AS rot,
         sqrt(greatest(c2.s2 / c2.nsem - power(c2.u / c2.nsem, 2), 0)) / sqrt(7) AS sd,
         CASE WHEN c2.ns >= 99 THEN 2.33 WHEN c2.ns >= 98 THEN 2.05 WHEN c2.ns >= 97 THEN 1.88 WHEN c2.ns >= 95 THEN 1.65
              WHEN c2.ns >= 90 THEN 1.28 WHEN c2.ns >= 85 THEN 1.04 WHEN c2.ns >= 80 THEN 0.84 ELSE 0.67 END AS z
  FROM c2),
c4 AS (
  SELECT c3.*, CASE WHEN c3.rot >= cfg.rot_alta THEN 'alta' WHEN c3.rot >= cfg.rot_media THEN 'media' ELSE 'baja' END AS rotacion,
         cfg.metodo AS met,
         -- "vende de vez en cuando" (tener 1 y pedir cuando se acabe) solo si entre pedidos se vende menos de 1;
         -- si vende poco seguido pero mucho volumen (ej. 400 sacos en 5 semanas) se calcula normal
         (c3.rot < cfg.rot_media AND c3.vdia * (coalesce(c3.ent, 0) + c3.rev) < 1) AS lento
  FROM c3, cfg),
c5 AS (   -- stock de seguridad (= mínimo), punto de reorden y máximo
  SELECT c4.*,
         greatest(coalesce(c4.min_f,
           CASE WHEN c4.met = 'simple' THEN ceil(c4.vdia * (c4.ent + c4.seg))
                WHEN c4.lento OR c4.rotacion = 'baja' THEN c4.piso   -- vende en pocas semanas: sin colchón por variación
                ELSE ceil(c4.z * c4.sd * sqrt(c4.ent + c4.rev)) END), c4.piso) AS ss,
         CASE WHEN c4.met = 'simple' THEN 0 ELSE ceil(c4.vdia * (c4.ent + c4.rev)) END AS dem_lt
  FROM c4),
c6 AS (
  SELECT c5.*,
         CASE WHEN c5.met = 'simple' THEN c5.ss
              -- rota poco: tener pocas piezas (1 de fábrica) y pedir solo cuando se acaben: punto de reorden = máximo − 1
              WHEN c5.lento THEN greatest(coalesce(c5.max_f, (SELECT max_lento FROM cfg)), c5.ss) - 1
              ELSE greatest(c5.dem_lt + CASE WHEN c5.rotacion = 'baja' THEN 0 ELSE c5.ss END, c5.ss) END AS pr
  FROM c5),
c7 AS (SELECT c6.*, coalesce(c6.max_f, CASE WHEN c6.met <> 'simple' AND c6.lento THEN c6.pr + 1
                                         ELSE c6.pr + ceil(c6.vdia * c6.inv) END) AS mx0 FROM c6),
c7b AS (  -- política por producto: mantener un mínimo (en su unidad y empaque) o solo bajo pedido
  SELECT c7.*, CASE WHEN c7.politica = 'minimo' AND c7.pol_min > 0
                    THEN ceil(c7.pol_min / coalesce(nullif(c7.empaque, 0), 1)) * coalesce(nullif(c7.empaque, 0), 1) END AS pmin
  FROM c7),
c7c AS (
  SELECT c7b.*,
         CASE WHEN c7b.politica = 'bajo_pedido' THEN 0 WHEN c7b.pmin IS NOT NULL THEN greatest(c7b.ss, c7b.pmin) ELSE c7b.ss END AS ss2,
         CASE WHEN c7b.politica = 'bajo_pedido' THEN -1 WHEN c7b.pmin IS NOT NULL THEN greatest(c7b.pr, c7b.pmin - 1) ELSE c7b.pr END AS pr2,
         CASE WHEN c7b.politica = 'bajo_pedido' THEN 0 WHEN c7b.pmin IS NOT NULL THEN greatest(c7b.mx0, c7b.pmin) ELSE c7b.mx0 END AS mx1
  FROM c7b),
c8 AS (SELECT c7c.*, CASE WHEN c7c.politica = 'bajo_pedido' THEN 0 ELSE greatest(c7c.mx1, c7c.pr2 + 1) END AS mx,
              concat_ws('; ',
                CASE WHEN c7c.tickets <= 1 THEN 'solo 1 venta en ' || (SELECT meses_c FROM cfg) || ' meses' END,
                CASE WHEN c7c.politica IS DISTINCT FROM 'bajo_pedido' AND c7c.mx1 <= c7c.pr2 THEN 'máximo no era mayor al punto de reorden, se ajustó' END,
                CASE WHEN c7c.prov_id IS NULL THEN 'sin proveedor' END,
                CASE WHEN c7c.prov_id IS NOT NULL AND c7c.ent_p IS NULL THEN 'días de entrega desconocidos (se usó ' || c7c.ent || ')' END,
                CASE WHEN c7c.agot > 0 THEN 'estuvo agotado ' || c7c.agot || ' días: la venta diaria se calculó sobre los días con existencia' END,
                CASE WHEN c7c.umax >= 0.5 * nullif(c7c.u, 0) AND c7c.u > 2 THEN 'más de la mitad de la venta fue en un solo pedido' END) AS alerta
       FROM c7c)
INSERT INTO compras_maxmin (mes, base, articulo_id, clave, articulo, unidad, proveedor_id, proveedor, clase, venta, unidades, pct, pct_acum,
  venta_diaria, dias_entrega, dias_seguridad, dias_inventario, empaque, minimo, maximo, origen, alerta, periodo_ini, periodo_fin, dias_periodo, por, calculado,
  punto_reorden, rotacion, semanas_venta, semanas, tickets, desv_diaria, nivel_servicio, dias_revision, metodo, ultima_venta,
  presentaciones, dias_agotado, lt_medido, venta_max_doc, politica)
SELECT m.mes, cfg.base, c8.articulo_id, c8.clave, c8.nombre, c8.unidad, c8.prov_id, c8.prov_nom, c8.clase, round(c8.imp, 2), c8.u,
       round(c8.imp / nullif(c8.tot, 0), 6), round(c8.acum / nullif(c8.tot, 0), 6), round(c8.vdia, 4), c8.ent, c8.seg, c8.inv, c8.empaque,
       c8.ss2, c8.mx, CASE WHEN c8.politica IS NOT NULL THEN 'política' WHEN c8.min_f IS NOT NULL OR c8.max_f IS NOT NULL THEN 'manual' ELSE 'calculado' END, nullif(c8.alerta, ''),
       CASE WHEN c8.clase_c = 'C' THEN nd.desde_c ELSE nd.desde END, (m.mes - 1), c8.ndias, cfg.por, now(),
       c8.pr2, c8.rotacion, c8.sem, c8.nsem, c8.tickets, round(c8.sd::numeric, 4), c8.ns, c8.rev, c8.met, c8.ultima,
       (SELECT txt FROM pres WHERE pres.articulo_id = c8.articulo_id), c8.agot, c8.lt_med, c8.umax, c8.politica
FROM c8, cfg, m, nd;
-- @fin_calculo
WITH /*CTX*/,
m AS (SELECT date_trunc('month', coalesce(nullif(p->>'mes', '')::date, hoy))::date AS mes FROM cfg),
x AS (SELECT y.* FROM compras_maxmin y, cfg, m WHERE y.base = cfg.base AND y.mes = m.mes)
SELECT json_build_object('ok', true, 'base', (SELECT base FROM cfg), 'mes', (SELECT mes FROM m)::text,
  'productos', (SELECT count(*) FROM x), 'a', (SELECT count(*) FROM x WHERE clase = 'A'), 'b', (SELECT count(*) FROM x WHERE clase = 'B'), 'c', (SELECT count(*) FROM x WHERE clase = 'C'),
  'venta_a', (SELECT round(sum(venta) FILTER (WHERE clase = 'A') / nullif(sum(venta) FILTER (WHERE pct IS NOT NULL), 0) * 100, 1) FROM x),
  'alertas', (SELECT count(*) FROM x WHERE alerta IS NOT NULL),
  'rotacion', (SELECT json_object_agg(coalesce(rotacion, '-'), n) FROM (SELECT rotacion, count(*) AS n FROM x GROUP BY 1) z),
  'una_venta', (SELECT count(*) FROM x WHERE tickets <= 1),
  'sin_proveedor', (SELECT count(*) FROM x WHERE proveedor_id IS NULL),
  'desde', (SELECT min(periodo_ini) FILTER (WHERE clase IN ('A', 'B')) FROM x)::text, 'hasta', (SELECT max(periodo_fin) FROM x)::text,
  'calculado', (SELECT max(calculado) FROM x)) AS r;
