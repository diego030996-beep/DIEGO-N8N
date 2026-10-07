-- Historial: busca por folio de retiro (R-01842), M-123, pedido, folio de compra, empleado o concepto. p = {q}
SET LOCAL statement_timeout = '25s';
WITH /*CTX*/, /*MOV*/,
q AS (SELECT '%' || lower(cfg.p->>'q') || '%' AS t, regexp_replace(cfg.p->>'q', '[^0-9]', '', 'g') AS num FROM cfg)
SELECT json_build_object('ok', true, 'lista', (SELECT coalesce(json_agg(json_build_object('clase', clase, 'ref', ref, 'fecha', fecha, 'hora', hora, 'folio', folio,
    'empleado', empleado, 'concepto', concepto, 'importe', importe, 'comprobado', comprobado, 'estado', estado, 'motivo', motivo, 'pedido', pedido, 'compra', cm_folio)
    ORDER BY fecha DESC, hora DESC), '[]') FROM (
  SELECT mov.* FROM mov, q, cfg
  WHERE (cfg.p->>'_rol' IN ('admin', 'auditora') OR (mov.clase = 'registro' AND mov.empleado = cfg.por))
    AND (lower(concat_ws(' ', folio, empleado, concepto, pedido, cm_folio, cm_proveedor)) LIKE q.t
         OR (length(q.num) >= 3 AND (ltrim(regexp_replace(coalesce(folio, ''), '[^0-9]', '', 'g'), '0') = ltrim(q.num, '0')
                                    OR ltrim(regexp_replace(coalesce(pedido, ''), '[^0-9]', '', 'g'), '0') = ltrim(q.num, '0')
                                    OR ltrim(regexp_replace(coalesce(cm_folio, ''), '[^0-9]', '', 'g'), '0') = ltrim(q.num, '0'))))
  ORDER BY fecha DESC LIMIT 100) z)) AS r FROM cfg;
