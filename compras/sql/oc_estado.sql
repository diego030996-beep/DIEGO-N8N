-- Qué pasó con una OC atrasada. p = {docto_cm_id, estado: 'en_camino'|'cancelada'|'recibida'|'' (quitar), nota}
SET LOCAL statement_timeout = '15s';
WITH /*CTX*/
DELETE FROM compras_oc_seguimiento s USING cfg WHERE s.base = cfg.base AND s.docto_cm_id = cfg.p->>'docto_cm_id' AND coalesce(cfg.p->>'estado', '') = '';
WITH /*CTX*/
INSERT INTO compras_oc_seguimiento (base, docto_cm_id, estado, nota, por)
SELECT cfg.base, p->>'docto_cm_id', p->>'estado', nullif(p->>'nota', ''), cfg.por FROM cfg WHERE coalesce(p->>'estado', '') <> ''
ON CONFLICT (base, docto_cm_id) DO UPDATE SET estado = EXCLUDED.estado, nota = EXCLUDED.nota, por = EXCLUDED.por, actualizado = now();
WITH /*CTX*/
SELECT json_build_object('ok', true, 'docto_cm_id', cfg.p->>'docto_cm_id', 'estado', cfg.p->>'estado') AS r FROM cfg;
