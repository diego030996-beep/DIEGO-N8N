-- Todo lo que necesita la página al abrir: tinacos (con receta, costo, precio, utilidad), componentes, gastos extra y lo pendiente de exportar.
SET LOCAL statement_timeout = '30s';
WITH /*CTX*/, /*INV*/,
tin AS (  -- los tinacos: los de las líneas de la configuración (tinaco|cisterna) o los que ya tienen receta
  SELECT a.articulo_id, a.clave, a.nombre, a.unidad, a.linea, a.precio_lista FROM ms_articulos a, cfg
  WHERE a.base = cfg.base AND coalesce(a.estatus, 'A') <> 'B'
    AND ((coalesce(a.linea, '') || ' ' || coalesce(a.grupo, '')) ~* cfg.lineas
         OR EXISTS (SELECT 1 FROM prod_receta r WHERE r.base = cfg.base AND r.articulo_id = a.articulo_id))),
rec AS (
  SELECT r.articulo_id, json_agg(json_build_object('componente_id', r.componente_id, 'clave', c.clave, 'nombre', c.nombre, 'unidad', c.unidad,
           'cantidad', r.cantidad, 'costo', cos.costo, 'fuente', cos.fuente, 'importe', round(r.cantidad * cos.costo, 2)) ORDER BY c.nombre) AS comps,
         sum(r.cantidad * cos.costo) AS costo, bool_or(cos.costo IS NULL) AS sin_costo
  FROM prod_receta r CROSS JOIN cfg LEFT JOIN ms_articulos c ON c.base = r.base AND c.articulo_id = r.componente_id
  LEFT JOIN cos ON cos.articulo_id = r.componente_id
  WHERE r.base = cfg.base GROUP BY 1),
mes AS (SELECT r.articulo_id, sum(r.cantidad) AS u FROM prod_registro r, cfg WHERE r.base = cfg.base AND r.fecha >= date_trunc('month', cfg.hoy) GROUP BY 1),
comp AS (  -- componentes que se usan en alguna receta
  SELECT DISTINCT r.componente_id AS articulo_id FROM prod_receta r, cfg WHERE r.base = cfg.base)
SELECT json_build_object('ok', true, 'hoy', cfg.hoy, 'base', cfg.base, 'cfg', cfg.c,
  'tinacos', (SELECT coalesce(json_agg(json_build_object('articulo_id', t.articulo_id, 'clave', t.clave, 'nombre', t.nombre, 'unidad', t.unidad, 'linea', t.linea,
      'existencia', coalesce(exi.e, 0), 'por_importar', coalesce(fab.u, 0), 'mes', coalesce(mes.u, 0),
      'precio', coalesce(pp.precio, t.precio_lista), 'precio_lista', t.precio_lista, 'precio_propio', pp.precio IS NOT NULL,
      'receta', coalesce(rec.comps, '[]'::json), 'costo', round(rec.costo, 2), 'sin_costo', coalesce(rec.sin_costo, false))
      ORDER BY (rec.articulo_id IS NULL), t.nombre), '[]'::json)
    FROM tin t LEFT JOIN rec ON rec.articulo_id = t.articulo_id LEFT JOIN exi ON exi.articulo_id = t.articulo_id
    LEFT JOIN fab ON fab.articulo_id = t.articulo_id LEFT JOIN mes ON mes.articulo_id = t.articulo_id
    LEFT JOIN prod_precio pp ON pp.base = cfg.base AND pp.articulo_id = t.articulo_id),
  'componentes', (SELECT coalesce(json_agg(json_build_object('articulo_id', a.articulo_id, 'clave', a.clave, 'nombre', a.nombre, 'unidad', a.unidad,
      'existencia', coalesce(exi.e, 0), 'por_importar', coalesce(cons.u, 0), 'disponible', coalesce(exi.e, 0) - coalesce(cons.u, 0),
      'costo', cos.costo, 'fuente', cos.fuente) ORDER BY a.nombre), '[]'::json)
    FROM comp JOIN ms_articulos a ON a.articulo_id = comp.articulo_id CROSS JOIN cfg LEFT JOIN exi ON exi.articulo_id = comp.articulo_id
    LEFT JOIN cons ON cons.articulo_id = comp.articulo_id LEFT JOIN cos ON cos.articulo_id = comp.articulo_id WHERE a.base = cfg.base),
  'extras', (SELECT coalesce(json_agg(json_build_object('id', x.id, 'concepto', x.concepto, 'monto', x.monto, 'articulo_id', x.articulo_id) ORDER BY x.id), '[]'::json)
    FROM prod_extra x WHERE x.base = cfg.base),
  'sin_exportar', (SELECT json_build_object('registros', count(*), 'tinacos', coalesce(sum(cantidad), 0), 'desde', min(fecha), 'hasta', max(fecha))
    FROM prod_registro r WHERE r.base = cfg.base AND r.exporte_id IS NULL),
  'sin_confirmar', (SELECT coalesce(json_agg(json_build_object('id', x.id, 'desde', x.desde, 'hasta', x.hasta, 'registros', x.registros, 'creado', x.creado) ORDER BY x.id), '[]'::json)
    FROM prod_exporte x WHERE x.base = cfg.base AND x.importado IS NULL)) AS r
FROM cfg;
