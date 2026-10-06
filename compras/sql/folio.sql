-- Escribe a mano el folio de la OC de un plan (si no se ligó solo). p = {plan_id, folio}
SET LOCAL statement_timeout = '30s';
SET LOCAL lock_timeout = '5s';
WITH /*CTX*/
UPDATE compras_planes pl SET folio = nullif(cfg.p->>'folio', ''), docto_cm_id = NULL, folio_oc = NULL, fecha_oc = NULL, ligado = NULL,
  por = cfg.por, modificado = now()
FROM cfg WHERE pl.id = (cfg.p->>'plan_id')::bigint AND pl.base = cfg.base AND pl.origen = 'planeador';
/*LIGAR*/
WITH /*CTX*/
SELECT json_build_object('ok', true, 'id', pl.id, 'folio', pl.folio, 'folio_oc', pl.folio_oc, 'fecha_oc', pl.fecha_oc) AS r
FROM compras_planes pl, cfg WHERE pl.id = (cfg.p->>'plan_id')::bigint AND pl.base = cfg.base;
