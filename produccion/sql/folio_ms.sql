-- Busca en la copia de Microsip (RESUMEN_MOVTOS_IN: movimientos de inventario) el documento donde se importó un archivo:
-- movimientos de inventario (origen IN) desde el día del archivo, con los mismos artículos. p = {exporte_id}
SET LOCAL statement_timeout = '20s';
WITH /*CTX*/,
ex AS (SELECT x.* FROM prod_exporte x, cfg WHERE x.base = cfg.base AND x.id = (cfg.p->>'exporte_id')::bigint),
arts AS (  -- artículos del archivo: materia prima y tinacos (producción) o polímero (merma)
  SELECT DISTINCT d.componente_id AS articulo_id FROM ex JOIN prod_registro r ON r.exporte_id = ex.id JOIN prod_registro_det d ON d.registro_id = r.id
  UNION SELECT DISTINCT r.articulo_id FROM ex JOIN prod_registro r ON r.exporte_id = ex.id
  UNION SELECT DISTINCT j.articulo_id FROM ex JOIN prod_ajuste j ON j.exporte_id = ex.id),
mv AS (
  SELECT coalesce(nullif(r.datos->>'folio', ''), nullif(r.datos->>'FOLIO', ''), nullif(r.datos->>'docto_in_id', ''), r.fecha::text || ' ' || coalesce(r.datos->>'concepto', '')) AS folio,
         r.fecha, coalesce(r.datos->>'concepto', r.datos->>'CONCEPTO', '') AS concepto,
         coalesce(nullif(r.datos->>'articulo_id', ''), r.datos->>'ARTICULO_ID')::bigint AS articulo_id
  FROM ms_raw r, cfg, ex
  WHERE r.base = cfg.base AND r.tabla = 'RESUMEN_MOVTOS_IN' AND upper(coalesce(r.datos->>'origen', r.datos->>'ORIGEN', '')) = 'IN'
    AND r.fecha BETWEEN ex.creado::date - 1 AND ex.creado::date + 21
    AND coalesce(nullif(r.datos->>'articulo_id', ''), r.datos->>'ARTICULO_ID') ~ '^[0-9]{1,18}\Z'),
cand AS (SELECT folio, min(fecha) AS fecha, max(concepto) AS concepto, count(DISTINCT articulo_id) FILTER (WHERE articulo_id IN (SELECT articulo_id FROM arts)) AS coinciden,
                count(DISTINCT articulo_id) AS articulos
         FROM mv GROUP BY folio HAVING count(DISTINCT articulo_id) FILTER (WHERE articulo_id IN (SELECT articulo_id FROM arts)) > 0)
SELECT json_build_object('ok', true, 'exporte_id', (SELECT id FROM ex), 'articulos', (SELECT count(*) FROM arts),
  'hay_copia', EXISTS (SELECT 1 FROM ms_raw r, cfg WHERE r.base = cfg.base AND r.tabla = 'RESUMEN_MOVTOS_IN' LIMIT 1),
  'candidatos', (SELECT coalesce(json_agg(k ORDER BY k.coinciden DESC, k.fecha), '[]'::json) FROM (SELECT * FROM cand ORDER BY coinciden DESC, fecha LIMIT 8) k)) AS r
FROM cfg;
