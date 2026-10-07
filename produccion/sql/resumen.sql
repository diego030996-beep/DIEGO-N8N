-- Producción por semana (últimas 12) y por tinaco en el periodo. p = {desde, hasta}
SET LOCAL statement_timeout = '20s';
WITH /*CTX*/,
rg AS (SELECT coalesce(nullif(p->>'desde', '')::date, date_trunc('month', hoy)::date) AS d, coalesce(nullif(p->>'hasta', '')::date, hoy) AS h FROM cfg),
reg AS (SELECT r.*, a.clave, a.nombre, coalesce(pp.precio, a.precio_lista) AS precio FROM prod_registro r CROSS JOIN cfg
        LEFT JOIN ms_articulos a ON a.base = r.base AND a.articulo_id = r.articulo_id LEFT JOIN prod_precio pp ON pp.base = r.base AND pp.articulo_id = r.articulo_id
        WHERE r.base = cfg.base)
SELECT json_build_object('ok', true, 'desde', (SELECT d FROM rg), 'hasta', (SELECT h FROM rg),
  'semanas', (SELECT coalesce(json_agg(z ORDER BY z.semana), '[]'::json) FROM (
      SELECT date_trunc('week', fecha)::date AS semana, sum(cantidad) AS tinacos, round(sum(cantidad * coalesce(costo_unit, 0)), 2) AS costo,
             round(sum(cantidad * coalesce(precio, 0)), 2) AS venta, count(DISTINCT fecha) AS dias
      FROM reg, cfg WHERE fecha >= date_trunc('week', cfg.hoy) - interval '11 weeks' GROUP BY 1) z),
  'por_tinaco', (SELECT coalesce(json_agg(z ORDER BY z.tinacos DESC), '[]'::json) FROM (
      SELECT articulo_id, clave, nombre, sum(cantidad) AS tinacos, round(sum(cantidad * coalesce(costo_unit, 0)), 2) AS costo,
             round(sum(cantidad * coalesce(costo_unit, 0)) / nullif(sum(cantidad), 0), 2) AS costo_unit, max(precio) AS precio
      FROM reg, rg WHERE fecha BETWEEN rg.d AND rg.h GROUP BY 1, 2, 3) z)) AS r
FROM cfg;
