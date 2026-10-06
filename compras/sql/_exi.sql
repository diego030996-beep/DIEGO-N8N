exi AS (SELECT e.articulo_id, sum(coalesce(e.existencia, 0)) AS e FROM ms_existencias e, cfg
        WHERE e.base = cfg.base AND (cfg.alm = '' OR coalesce(e.almacen, '') ~* cfg.alm) GROUP BY 1),
pend AS (  -- pendiente por recibir: OCs sin recepción ligada, dentro de los días de entrega del proveedor + gracia
  SELECT d.articulo_id, sum(d.u) AS u, string_agg(DISTINCT o.folio, ', ') AS folios
  FROM oc o JOIN ocd d ON d.id = o.id
  CROSS JOIN cfg
  LEFT JOIN compras_proveedores cp ON cp.base = cfg.base AND cp.proveedor_id = o.prov
  WHERE o.estatus NOT IN ('S', 'R') AND NOT EXISTS (SELECT 1 FROM lig WHERE lig.fte = o.id)
    AND o.fecha >= cfg.hoy - (coalesce(cp.dias_entrega, cfg.ent_def) + cfg.gracia)::int
  GROUP BY 1)
