-- Cómo está la copia de Microsip en Postgres: última copia de órdenes de compra, qué fechas trajo, y una OC tal como quedó copiada.
-- p = {folio} (opcional). Sirve para saber si una cancelación o recepción hecha en Microsip ya llegó.
SET LOCAL statement_timeout = '20s';
WITH /*CTX*/,
cm AS (SELECT r.pk, r.fecha, r.actualizado, r.sync_id, r.datos FROM ms_raw r, cfg WHERE r.base = cfg.base AND r.tabla = 'DOCTOS_CM'),
ult AS (SELECT max(actualizado) AS t FROM cm),
lote AS (SELECT cm.* FROM cm, ult WHERE cm.actualizado >= ult.t - interval '30 minutes'),   -- lo que trajo la última copia
dig AS (SELECT nullif(regexp_replace(coalesce(p->>'folio', ''), '[^0-9]', '', 'g'), '') AS d FROM cfg),
oc AS (SELECT cm.*, (SELECT r2.datos FROM ms_raw r2, cfg WHERE r2.base = cfg.base AND r2.tabla = 'DOCTOS_CM_DET' AND r2.datos->>'DOCTO_CM_ID' = cm.datos->>'DOCTO_CM_ID' LIMIT 1) AS det
       FROM cm, dig WHERE dig.d IS NOT NULL AND ltrim(regexp_replace(coalesce(cm.datos->>'FOLIO', ''), '[^0-9]', '', 'g'), '0') = ltrim(dig.d, '0')
       ORDER BY cm.actualizado DESC LIMIT 5)
SELECT json_build_object('ok', true, 'ahora', to_char(now() AT TIME ZONE 'America/Mexico_City', 'YYYY-MM-DD HH24:MI'),
  'ultima', to_char((SELECT t FROM ult) AT TIME ZONE 'America/Mexico_City', 'YYYY-MM-DD HH24:MI'),
  'lote', (SELECT json_build_object('docs', count(*), 'desde', min(fecha), 'hasta', max(fecha),
             'ordenes', count(*) FILTER (WHERE upper(coalesce(datos->>'TIPO_DOCTO', '')) = 'O')) FROM lote),
  'ocs', (SELECT coalesce(json_agg(json_build_object('folio', datos->>'FOLIO', 'tipo', datos->>'TIPO_DOCTO', 'fecha', fecha, 'estatus', datos->>'ESTATUS',
             'copiada', to_char(actualizado AT TIME ZONE 'America/Mexico_City', 'YYYY-MM-DD HH24:MI'), 'datos', datos,
             'campos_det', (SELECT string_agg(k, ', ') FROM jsonb_object_keys(det) k))), '[]'::json) FROM oc)) AS r
FROM cfg;
