-- Reporte de retiros del dueño (lo ven el administrador, la auditora y la directora). p = {desde, hasta}
SET LOCAL statement_timeout = '20s';
WITH /*CTX*/, /*MOV*/,
rg AS (SELECT coalesce(nullif(p->>'desde', '')::date, date_trunc('month', hoy)::date) AS d1, coalesce(nullif(p->>'hasta', '')::date, hoy) AS d2 FROM cfg),
x AS (SELECT d.* FROM mov_retiro_dueno d, cfg, rg WHERE d.base = cfg.base AND d.fecha BETWEEN rg.d1 AND rg.d2)
SELECT json_build_object('ok', true, 'desde', rg.d1, 'hasta', rg.d2,
  'lista', (SELECT coalesce(json_agg(json_build_object('id', id, 'fecha', fecha, 'hora', hora, 'importe', importe, 'nota', nota, 'retiro_folio', retiro_folio,
              'por', por, 'creado', creado, 'huella', huella, 'anulado', anulado, 'anulado_nota', anulado_nota) ORDER BY fecha DESC, hora DESC, id DESC), '[]') FROM x),
  'total', (SELECT coalesce(sum(importe), 0) FROM x WHERE NOT anulado), 'n', (SELECT count(*) FROM x WHERE NOT anulado),
  'meses', (SELECT coalesce(json_agg(m ORDER BY m.mes DESC), '[]') FROM (
              SELECT to_char(d.fecha, 'YYYY-MM') AS mes, count(*) AS n, sum(d.importe) AS total FROM mov_retiro_dueno d, cfg
              WHERE d.base = cfg.base AND NOT d.anulado AND d.fecha >= (date_trunc('month', cfg.hoy) - interval '5 months')::date GROUP BY 1) m),
  'candidatos', CASE WHEN cfg.p->>'_rol' = 'admin' THEN (SELECT coalesce(json_agg(json_build_object('id', r.id, 'folio', r.folio, 'fecha', r.fecha, 'hora', r.hora,
              'descripcion', r.descripcion, 'importe', r.importe) ORDER BY r.fecha DESC, r.hora DESC), '[]') FROM rsr r WHERE r.fecha >= cfg.hoy - 7) END
) AS r FROM cfg, rg;
