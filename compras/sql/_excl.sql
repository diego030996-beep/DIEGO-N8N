excl AS (  -- artículos que no entran al planeador: líneas/grupos excluidos (tinacos), nombre excluido, dados de baja o marcados a mano
  SELECT a.articulo_id, CASE WHEN cfg.excl_lin <> '' AND (coalesce(a.linea, '') || ' ' || coalesce(a.grupo, '')) ~* cfg.excl_lin
                             THEN coalesce(nullif(trim(a.linea), ''), nullif(trim(a.grupo), ''), 'Sin línea') END AS linea_excl
  FROM ms_articulos a, cfg
  WHERE a.base = cfg.base AND ((cfg.excl_lin <> '' AND (coalesce(a.linea, '') || ' ' || coalesce(a.grupo, '')) ~* cfg.excl_lin)
    OR (cfg.excl <> '' AND coalesce(a.nombre, '') ~* cfg.excl) OR upper(coalesce(a.estatus, '')) = 'B')
  UNION
  SELECT o.articulo_id, NULL FROM compras_articulos o, cfg WHERE o.base = cfg.base AND o.excluir)
