oc AS (   -- órdenes de compra (tipo O) de Microsip, sin canceladas
  SELECT r.datos->>'DOCTO_CM_ID' AS id, r.datos->>'PROVEEDOR_ID' AS prov, coalesce(r.fecha, left(r.datos->>'FECHA', 10)::date) AS fecha,
         r.datos->>'FOLIO' AS folio, upper(coalesce(r.datos->>'ESTATUS', '')) AS estatus, r.actualizado AS copiado,
         CASE WHEN (r.datos->>'IMPORTE_NETO') ~ '^-?[0-9]+(\.[0-9]+)?\Z' THEN (r.datos->>'IMPORTE_NETO')::numeric ELSE 0 END AS importe,
         CASE WHEN (r.datos->>'TOTAL_IMPUESTOS') ~ '^-?[0-9]+(\.[0-9]+)?\Z' THEN (r.datos->>'TOTAL_IMPUESTOS')::numeric ELSE 0 END AS impuestos
  FROM ms_raw r, cfg
  WHERE r.base = cfg.base AND r.tabla = 'DOCTOS_CM' AND upper(coalesce(r.datos->>'TIPO_DOCTO', '')) = 'O'
    AND upper(coalesce(r.datos->>'ESTATUS', '')) <> 'C' AND upper(coalesce(r.datos->>'CANCELADO', 'N')) NOT IN ('S', 'SI', 'Y', 'T', '1', 'TRUE')
    AND coalesce(nullif(trim(r.datos->>'FECHA_HORA_CANCELACION'), ''), nullif(trim(r.datos->>'USUARIO_CANCELACION'), '')) IS NULL),
lig AS (  -- ligas de compras: de qué documento (fte) salió cuál (dst)
  SELECT DISTINCT coalesce(r.datos->>'DOCTO_CM_FTE_ID', r.datos->>'DOCTO_CM_ID_FTE', r.datos->>'DOCTO_FTE_ID') AS fte,
         coalesce(r.datos->>'DOCTO_CM_DEST_ID', r.datos->>'DOCTO_CM_ID_DEST', r.datos->>'DOCTO_DEST_ID') AS dst
  FROM ms_raw r, cfg WHERE r.base = cfg.base AND r.tabla = 'DOCTOS_CM_LIGAS'),
prv AS (SELECT p.pk AS proveedor_id, p.datos->>'NOMBRE' AS nombre FROM ms_raw p, cfg WHERE p.base = cfg.base AND p.tabla = 'PROVEEDORES')
