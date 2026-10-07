excl AS (  -- artículos que no entran al planeador, con el motivo
  SELECT DISTINCT ON (articulo_id) articulo_id, grupo, linea_excl FROM (
    SELECT a.articulo_id,
           CASE WHEN cfg.excl_lin <> '' AND (coalesce(a.linea, '') || ' ' || coalesce(a.grupo, '')) ~* cfg.excl_lin
                  THEN coalesce(nullif(trim(a.linea), ''), nullif(trim(a.grupo), ''), 'Sin línea')
                WHEN cfg.servicios <> '' AND (coalesce(a.nombre, '') || ' ' || coalesce(a.linea, '') || ' ' || coalesce(a.grupo, '')) ~* cfg.servicios
                  THEN 'Servicios (no son mercancía)'
                WHEN cfg.varios <> '' AND (coalesce(a.nombre, '') || ' ' || coalesce(a.linea, '')) ~* cfg.varios THEN 'Varios (artículo genérico)'
                WHEN upper(coalesce(a.estatus, '')) = 'B' THEN 'Dados de baja en Microsip'
                ELSE 'Excluidos por nombre' END AS grupo,
           CASE WHEN cfg.excl_lin <> '' AND (coalesce(a.linea, '') || ' ' || coalesce(a.grupo, '')) ~* cfg.excl_lin
                THEN coalesce(nullif(trim(a.linea), ''), nullif(trim(a.grupo), ''), 'Sin línea') END AS linea_excl, 1 AS prio
    FROM ms_articulos a, cfg
    WHERE a.base = cfg.base AND ((cfg.excl_lin <> '' AND (coalesce(a.linea, '') || ' ' || coalesce(a.grupo, '')) ~* cfg.excl_lin)
      OR (cfg.servicios <> '' AND (coalesce(a.nombre, '') || ' ' || coalesce(a.linea, '') || ' ' || coalesce(a.grupo, '')) ~* cfg.servicios)
      OR (cfg.varios <> '' AND (coalesce(a.nombre, '') || ' ' || coalesce(a.linea, '')) ~* cfg.varios)
      OR (cfg.excl <> '' AND coalesce(a.nombre, '') ~* cfg.excl) OR upper(coalesce(a.estatus, '')) = 'B')
    UNION ALL
    SELECT o.articulo_id, 'Pausados', NULL, 2 FROM compras_articulos o, cfg WHERE o.base = cfg.base AND o.excluir
    UNION ALL
    SELECT p.articulo_id, 'Pausados', NULL, 2 FROM compras_politica p, cfg WHERE p.base = cfg.base AND p.politica = 'pausar'
    UNION ALL
    SELECT eqv.articulo_id, 'Presentaciones de otro artículo', NULL, 3 FROM eqv) x
  ORDER BY articulo_id, prio)