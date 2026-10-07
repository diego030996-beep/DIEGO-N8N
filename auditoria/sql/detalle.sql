-- Expediente completo de un movimiento: registro, comprobantes, retiro, compra de Microsip, pedido, compras candidatas y bitácora.
-- p = {clase: 'registro' | 'retiro' | 'compra', ref}
SET LOCAL statement_timeout = '25s';
WITH /*CTX*/, /*MOV*/,
x AS (SELECT mov.* FROM mov, cfg WHERE mov.clase = cfg.p->>'clase' AND mov.ref = cfg.p->>'ref'
        AND (cfg.p->>'_rol' IN ('admin', 'auditora') OR (mov.clase = 'registro' AND mov.empleado = cfg.por))),
e AS (SELECT est.* FROM est, x WHERE x.clase = 'registro' AND est.id = x.registro_id),
cand AS (   -- compras de Microsip cercanas para vincular a mano (las ya usadas por otro movimiento no salen)
  SELECT c.id, c.folio, c.tipo, c.fecha, c.total, c.proveedor, abs(c.total - coalesce(nullif(e.comprobado, 0), e.importe)) AS dif
  FROM e CROSS JOIN cmp c
  WHERE c.fecha BETWEEN e.fecha - 7 AND e.fecha + 10 AND c.id NOT IN (SELECT cm_id FROM reg WHERE cm_id IS NOT NULL AND id <> e.id)
  ORDER BY dif, abs(c.fecha - e.fecha) LIMIT 15)
SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM x) THEN json_build_object('ok', false, 'msg', 'No encontré ese movimiento (o no tienes permiso de verlo).')
ELSE json_build_object('ok', true,
  'mov', (SELECT json_build_object('clase', clase, 'ref', ref, 'fecha', fecha, 'hora', hora, 'folio', folio, 'empleado', empleado, 'concepto', concepto,
            'tipo', tipo, 'metodo', metodo, 'importe', importe, 'comprobado', comprobado, 'falta', falta, 'estado', estado, 'motivo', motivo,
            'vence', to_char(vence, 'YYYY-MM-DD HH24:MI'), 'pedido', pedido, 'revision', revision) FROM x),
  'registro', (SELECT json_build_object('id', e.id, 'proveedor', e.proveedor, 'retiro_folio', e.retiro_folio, 'ret_importe', e.ret_importe,
            'revision', e.revision, 'revision_nota', e.revision_nota, 'revisado_por', e.revisado_por, 'revisado_en', e.revisado_en, 'creado', e.creado,
            'compra', CASE WHEN e.cm_id IS NOT NULL THEN json_build_object('id', e.cm_id, 'folio', e.cm_folio, 'total', e.cm_total, 'proveedor', e.cm_proveedor,
                       'fecha', e.cm_fecha, 'auto', e.cm_auto) END,
            'pedido', CASE WHEN e.ped_norm <> '' THEN json_build_object('escrito', e.pedido, 'folio', e.ped_folio, 'cliente', e.ped_cliente,
                       'cancelado', e.ped_cancelado, 'tipo', e.ped_tipo) END,
            'req_compra', e.req_compra, 'candidatas', e.cands) FROM e),
  'comprobantes', (SELECT coalesce(json_agg(json_build_object('id', k.id, 'importe', k.importe, 'tipo', k.tipo, 'por', k.por, 'creado', k.creado) ORDER BY k.id), '[]')
                   FROM mov_comprobante k, e WHERE k.registro_id = e.id),
  'retiro', (SELECT json_build_object('folio', r.folio, 'fecha', r.fecha, 'hora', r.hora, 'descripcion', r.descripcion, 'usuario', r.usuario, 'importe', r.importe)
             FROM ret r, x LEFT JOIN e ON true WHERE r.id = CASE WHEN x.clase = 'retiro' THEN x.ref ELSE e.retiro_id END),
  'compra', (SELECT json_build_object('folio', c.folio, 'fecha', c.fecha, 'total', c.total, 'proveedor', c.proveedor, 'condicion', c.cond_nombre)
             FROM cmp c, x WHERE x.clase = 'compra' AND c.id = x.ref),
  'cand', CASE WHEN cfg.p->>'_rol' IN ('admin', 'auditora') THEN (SELECT coalesce(json_agg(cand), '[]') FROM cand) END,
  'ignorado', (SELECT json_build_object('motivo', i.motivo, 'por', i.por, 'creado', i.creado) FROM ign i, x WHERE i.tipo = x.clase AND i.ref = x.ref),
  'bitacora', (SELECT coalesce(json_agg(json_build_object('accion', b.accion, 'detalle', b.detalle, 'por', b.por, 'creado', b.creado) ORDER BY b.id), '[]')
               FROM mov_bitacora b, x LEFT JOIN e ON true WHERE (e.id IS NOT NULL AND b.registro_id = e.id) OR (b.ref = x.clase || ':' || x.ref)))
END AS r FROM cfg;
