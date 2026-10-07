-- Firma el corte de caja del día (reemplaza la libreta). Guarda lo que se esperaba, lo entregado, la diferencia y lo que quedaba pendiente.
-- p = {fecha, esperado, entregado, nota, pendientes, pendiente_monto}
SET LOCAL statement_timeout = '15s';
WITH /*CTX*/,
up AS (INSERT INTO mov_corte (base, fecha, esperado, entregado, diferencia, pendientes, pendiente_monto, nota, firmado_por, firmado_en)
       SELECT cfg.base, (p->>'fecha')::date, (p->>'esperado')::numeric, (p->>'entregado')::numeric, (p->>'entregado')::numeric - (p->>'esperado')::numeric,
              (p->>'pendientes')::int, (p->>'pendiente_monto')::numeric, nullif(p->>'nota', ''), cfg.por, now()
       FROM cfg
       ON CONFLICT (base, fecha) DO UPDATE SET esperado = EXCLUDED.esperado, entregado = EXCLUDED.entregado, diferencia = EXCLUDED.diferencia,
         pendientes = EXCLUDED.pendientes, pendiente_monto = EXCLUDED.pendiente_monto, nota = EXCLUDED.nota, firmado_por = EXCLUDED.firmado_por, firmado_en = now()
       RETURNING fecha, diferencia),
bit AS (INSERT INTO mov_bitacora (ref, accion, detalle, por)
        SELECT 'corte:' || up.fecha, 'firmar corte', 'entregado ' || (cfg.p->>'entregado') || ' · diferencia ' || up.diferencia || coalesce(' · ' || nullif(cfg.p->>'nota', ''), ''), cfg.por
        FROM up, cfg RETURNING id)
SELECT json_build_object('ok', EXISTS (SELECT 1 FROM up), 'diferencia', (SELECT diferencia FROM up), 'bit', (SELECT count(*) FROM bit)) AS r;
