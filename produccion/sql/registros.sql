-- Lo capturado en un periodo, con sus componentes y costo. p = {desde, hasta}
SET LOCAL statement_timeout = '20s';
WITH /*CTX*/,
rg AS (SELECT coalesce(nullif(p->>'desde', '')::date, hoy - 6) AS d, coalesce(nullif(p->>'hasta', '')::date, hoy) AS h FROM cfg)
SELECT json_build_object('ok', true, 'desde', (SELECT d FROM rg), 'hasta', (SELECT h FROM rg),
  'registros', (SELECT coalesce(json_agg(json_build_object('id', r.id, 'fecha', r.fecha, 'articulo_id', r.articulo_id, 'clave', a.clave, 'nombre', a.nombre,
      'cantidad', r.cantidad, 'costo_unit', round(r.costo_unit, 2), 'costo', round(r.costo_unit * r.cantidad, 2), 'nota', r.nota, 'por', r.por,
      'exporte_id', r.exporte_id, 'importado', x.importado IS NOT NULL,
      'comps', (SELECT json_agg(json_build_object('clave', c.clave, 'nombre', c.nombre, 'unidad', c.unidad, 'cantidad', d.cantidad, 'costo_unit', d.costo_unit) ORDER BY c.nombre)
                FROM prod_registro_det d LEFT JOIN ms_articulos c ON c.base = r.base AND c.articulo_id = d.componente_id WHERE d.registro_id = r.id))
      ORDER BY r.fecha DESC, r.id DESC), '[]'::json)
    FROM prod_registro r CROSS JOIN cfg CROSS JOIN rg LEFT JOIN ms_articulos a ON a.base = r.base AND a.articulo_id = r.articulo_id
    LEFT JOIN prod_exporte x ON x.id = r.exporte_id
    WHERE r.base = cfg.base AND r.fecha BETWEEN rg.d AND rg.h)) AS r
FROM cfg;
