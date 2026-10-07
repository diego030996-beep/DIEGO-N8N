-- Pantalla principal: cuánto se produjo, cuánto se gastó (materiales y gas), cuánto costó cada tinaco y si hay desviación.
-- p = {periodo: 'dia'|'semana'|'mes', fecha}
SET LOCAL statement_timeout = '30s';
WITH /*CTX*/, /*INV*/,
pp AS (SELECT coalesce(nullif(p->>'periodo', ''), 'dia') AS per, coalesce(nullif(p->>'fecha', '')::date, hoy) AS f FROM cfg),
rg AS (SELECT per, CASE per WHEN 'mes' THEN date_trunc('month', f)::date WHEN 'semana' THEN date_trunc('week', f)::date ELSE f END AS d,
              CASE per WHEN 'mes' THEN (date_trunc('month', f) + interval '1 month - 1 day')::date WHEN 'semana' THEN (date_trunc('week', f) + interval '6 days')::date ELSE f END AS h
       FROM pp),
reg AS (SELECT r.* FROM prod_registro r, cfg WHERE r.base = cfg.base),
det AS (SELECT r.fecha, d.componente_id, d.cantidad, d.costo_unit, a.nombre, a.clave,
               (a.nombre ~* cfg.auditar OR a.clave ~* cfg.auditar) AS es_pol
        FROM reg r JOIN prod_registro_det d ON d.registro_id = r.id CROSS JOIN cfg LEFT JOIN ms_articulos a ON a.base = cfg.base AND a.articulo_id = d.componente_id),
dia AS (SELECT r.fecha, sum(r.cantidad) AS pz, sum(r.cantidad * coalesce(r.costo_unit, 0)) AS mat FROM reg r GROUP BY 1),
-- gas: cada carga paga lo que se gastó desde la carga anterior → se reparte entre los tinacos hechos en ese lapso
-- (dos cargas el mismo día cuentan como una sola)
gas0 AS (SELECT fecha, sum(costo) AS costo, sum(litros) AS litros, lag(fecha) OVER (ORDER BY fecha) AS prev
         FROM prod_gas g, cfg WHERE g.base = cfg.base GROUP BY fecha),
gint AS (SELECT g.fecha, g.prev, g.costo, g.litros, (SELECT coalesce(sum(pz), 0) FROM dia WHERE dia.fecha > g.prev AND dia.fecha <= g.fecha) AS pz
         FROM gas0 g WHERE g.prev IS NOT NULL),
ult_tasa AS (SELECT costo / pz AS t, litros / pz AS tl FROM gint WHERE pz > 0 ORDER BY fecha DESC LIMIT 1),
gdia AS (  -- gas que le toca a cada día de producción (después de la última carga: estimado con la última tasa)
  SELECT dia.fecha, dia.pz,
         coalesce((SELECT dia.pz * gi.costo / nullif(gi.pz, 0) FROM gint gi WHERE dia.fecha > gi.prev AND dia.fecha <= gi.fecha ORDER BY gi.fecha LIMIT 1),
                  dia.pz * (SELECT t FROM ult_tasa)) AS gas,
         NOT EXISTS (SELECT 1 FROM gint gi WHERE dia.fecha > gi.prev AND dia.fecha <= gi.fecha) AS estimado
  FROM dia),
ref AS (SELECT sum(x.monto) AS gas_ref FROM prod_extra x, cfg WHERE x.base = cfg.base AND x.concepto ~* 'gas' AND x.articulo_id IS NULL),
-- periodos para la gráfica: los últimos 12 del tipo elegido
pers AS (SELECT gs::date AS d,
                CASE (SELECT per FROM rg) WHEN 'mes' THEN (gs + interval '1 month - 1 day')::date WHEN 'semana' THEN (gs + interval '6 days')::date ELSE gs::date END AS h
         FROM rg, generate_series(CASE rg.per WHEN 'mes' THEN rg.d - interval '11 months' WHEN 'semana' THEN rg.d - interval '11 weeks' ELSE rg.d - interval '13 days' END,
                                  rg.d, CASE rg.per WHEN 'mes' THEN interval '1 month' WHEN 'semana' THEN interval '1 week' ELSE interval '1 day' END) gs),
serie AS (SELECT pers.d, pers.h, coalesce((SELECT sum(pz) FROM dia WHERE dia.fecha BETWEEN pers.d AND pers.h), 0) AS pz,
                 coalesce((SELECT sum(mat) FROM dia WHERE dia.fecha BETWEEN pers.d AND pers.h), 0) AS mat,
                 coalesce((SELECT sum(gas) FROM gdia WHERE gdia.fecha BETWEEN pers.d AND pers.h), 0) AS gas,
                 coalesce((SELECT sum(costo) FROM prod_gas g, cfg WHERE g.base = cfg.base AND g.fecha BETWEEN pers.d AND pers.h), 0) AS pagado
          FROM pers),
cons30 AS (SELECT componente_id, sum(cantidad) / 30.0 AS diario FROM det, cfg WHERE det.fecha > cfg.hoy - 30 GROUP BY 1),
comp AS (SELECT DISTINCT r.componente_id AS articulo_id FROM prod_receta r, cfg WHERE r.base = cfg.base),
desv AS (SELECT count(*) AS pesajes, min(c.fecha) AS desde, sum(c.teorico - c.kg) AS kg, sum((c.teorico - c.kg) * cos.costo) AS dinero, sum(c.consumo) AS consumo
         FROM prod_conteo c CROSS JOIN cfg LEFT JOIN cos ON cos.articulo_id = c.articulo_id
         WHERE c.base = cfg.base AND c.estado IN ('ok', 'confirmado') AND c.teorico IS NOT NULL AND NOT EXISTS (SELECT 1 FROM prod_ajuste j WHERE j.conteo_id = c.id)),
ultp AS (SELECT max(c.fecha) AS f FROM prod_conteo c, cfg WHERE c.base = cfg.base AND c.estado <> 'reemplazado')
SELECT json_build_object('ok', true, 'hoy', cfg.hoy, 'periodo', rg.per, 'desde', rg.d, 'hasta', rg.h, 'meta_diaria', nullif(cfg.c->>'meta_diaria', '')::numeric,
  'dias_habiles', (SELECT count(*) FROM generate_series(rg.d, least(rg.h, cfg.hoy), interval '1 day') x WHERE extract(isodow FROM x) < 7),
  'per', (SELECT json_build_object('piezas', coalesce(sum(pz), 0), 'materiales', round(coalesce(sum(mat), 0), 2),
            'gas', round((SELECT coalesce(sum(gas), 0) FROM gdia WHERE gdia.fecha BETWEEN rg.d AND rg.h), 2),
            'gas_estimado', (SELECT bool_or(estimado AND gas IS NOT NULL) FROM gdia WHERE gdia.fecha BETWEEN rg.d AND rg.h),
            'gas_pagado', (SELECT round(coalesce(sum(costo), 0), 2) FROM prod_gas g WHERE g.base = cfg.base AND g.fecha BETWEEN rg.d AND rg.h),
            'gas_litros', (SELECT coalesce(sum(litros), 0) FROM prod_gas g WHERE g.base = cfg.base AND g.fecha BETWEEN rg.d AND rg.h),
            'dias_con_produccion', count(*))
          FROM dia WHERE dia.fecha BETWEEN rg.d AND rg.h),
  'polimero', (SELECT json_build_object('kg', round(coalesce(sum(cantidad), 0), 2), 'costo', round(coalesce(sum(cantidad * coalesce(costo_unit, 0)), 0), 2),
            'por_tipo', (SELECT coalesce(json_agg(json_build_object('nombre', nombre, 'kg', kg) ORDER BY kg DESC), '[]'::json) FROM (
               SELECT nombre, round(sum(cantidad), 2) AS kg FROM det WHERE es_pol AND fecha BETWEEN rg.d AND rg.h GROUP BY 1) z))
          FROM det WHERE es_pol AND fecha BETWEEN rg.d AND rg.h),
  'gas_tasa', (SELECT json_build_object('por_tinaco', round(t, 2), 'litros_tinaco', round(tl, 3)) FROM ult_tasa),
  'gas_ref', (SELECT gas_ref FROM ref),
  'gas_cargas', (SELECT coalesce(json_agg(json_build_object('id', g.id, 'fecha', g.fecha, 'litros', g.litros, 'costo', g.costo, 'nota', g.nota, 'por', g.por,
            'piezas', gi.pz, 'por_tinaco', round(gi.costo / nullif(gi.pz, 0), 2), 'desde', gi.prev,
            'mismo_dia', (SELECT count(*) FROM prod_gas g2 WHERE g2.base = g.base AND g2.fecha = g.fecha) > 1) ORDER BY g.fecha DESC, g.id DESC), '[]'::json)
          FROM (SELECT g.* FROM prod_gas g, cfg WHERE g.base = cfg.base ORDER BY g.fecha DESC, g.id DESC LIMIT 30) g LEFT JOIN gint gi ON gi.fecha = g.fecha),
  'serie', (SELECT coalesce(json_agg(json_build_object('d', d, 'h', h, 'piezas', pz, 'materiales', round(mat, 2), 'gas', round(gas, 2), 'pagado', round(pagado, 2)) ORDER BY d), '[]'::json) FROM serie),
  'materia', (SELECT coalesce(json_agg(json_build_object('clave', a.clave, 'nombre', a.nombre, 'unidad', a.unidad, 'disponible', coalesce(exi.e, 0) - coalesce(cons.u, 0),
            'diario', round(cons30.diario, 3), 'dias', CASE WHEN cons30.diario > 0 THEN floor((coalesce(exi.e, 0) - coalesce(cons.u, 0)) / cons30.diario) END,
            'es_pol', (a.nombre ~* cfg.auditar OR a.clave ~* cfg.auditar)) ORDER BY CASE WHEN cons30.diario > 0 THEN (coalesce(exi.e, 0) - coalesce(cons.u, 0)) / cons30.diario END NULLS LAST), '[]'::json)
          FROM comp JOIN ms_articulos a ON a.base = cfg.base AND a.articulo_id = comp.articulo_id LEFT JOIN exi ON exi.articulo_id = comp.articulo_id
          LEFT JOIN cons ON cons.articulo_id = comp.articulo_id LEFT JOIN cons30 ON cons30.componente_id = comp.articulo_id),
  'desviacion', (SELECT json_build_object('pesajes', pesajes, 'desde', desde, 'kg', round(coalesce(kg, 0), 2), 'dinero', round(coalesce(dinero, 0), 2),
            'pct', round(kg / nullif(consumo, 0) * 100, 2), 'revisar', (SELECT count(*) FROM prod_conteo c WHERE c.base = cfg.base AND c.estado = 'revisar'),
            'ultimo_pesaje', (SELECT f FROM ultp), 'dias_sin_pesar', cfg.hoy - (SELECT f FROM ultp), 'dias_conteo', cfg.dias_conteo) FROM desv),
  'sin_exportar', (SELECT json_build_object('registros', count(*), 'desde', min(fecha)) FROM reg WHERE exporte_id IS NULL),
  'sin_receta', (SELECT count(*) FROM ms_articulos a WHERE a.base = cfg.base AND coalesce(a.estatus, 'A') <> 'B' AND (coalesce(a.linea, '') || ' ' || coalesce(a.grupo, '')) ~* cfg.lineas
                 AND NOT EXISTS (SELECT 1 FROM prod_receta r WHERE r.base = cfg.base AND r.articulo_id = a.articulo_id))) AS r
FROM cfg, rg;
