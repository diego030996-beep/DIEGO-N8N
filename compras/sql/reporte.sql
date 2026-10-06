-- Lista A/B y máximos/mínimos de un mes (para ver y exportar). p = {mes}
SET LOCAL statement_timeout = '30s';
WITH /*CTX*/,
m AS (SELECT coalesce(date_trunc('month', nullif(p->>'mes', '')::date)::date,
                      (SELECT max(mes) FROM compras_maxmin x WHERE x.base = cfg.base AND x.mes <= cfg.hoy)) AS mes FROM cfg)
SELECT json_build_object('ok', true, 'mes', (SELECT mes FROM m)::text,
  'filas', (SELECT coalesce(json_agg(json_build_object('articulo_id', x.articulo_id, 'clave', x.clave, 'articulo', x.articulo, 'unidad', x.unidad,
              'proveedor_id', x.proveedor_id, 'proveedor', x.proveedor, 'clase', x.clase, 'venta', x.venta, 'unidades', x.unidades,
              'pct', x.pct, 'pct_acum', x.pct_acum, 'vd', x.venta_diaria, 'entrega', x.dias_entrega, 'seguridad', x.dias_seguridad,
              'inventario', x.dias_inventario, 'empaque', x.empaque, 'minimo', x.minimo, 'maximo', x.maximo, 'origen', x.origen,
              'alerta', x.alerta, 'ini', x.periodo_ini, 'fin', x.periodo_fin, 'dias', x.dias_periodo, 'calculado', x.calculado)
            ORDER BY x.venta DESC), '[]'::json)
          FROM compras_maxmin x, m WHERE x.base = cfg.base AND x.mes = m.mes)) AS r
FROM cfg;
