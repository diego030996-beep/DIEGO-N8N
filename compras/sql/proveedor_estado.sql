-- Pausa (eventual) o reactiva un proveedor. p = {proveedor_id, nombre, activo: 'si'|'no'}
-- Pausado: sus productos no salen en la vista general del planeador ni en los totales; se siguen calculando.
SET LOCAL statement_timeout = '15s';
WITH /*CTX*/
INSERT INTO compras_proveedores (base, proveedor_id, nombre, activo, por)
SELECT cfg.base, p->>'proveedor_id', nullif(p->>'nombre', ''), p->>'activo' = 'si', cfg.por FROM cfg
ON CONFLICT (base, proveedor_id) DO UPDATE SET activo = EXCLUDED.activo, nombre = coalesce(compras_proveedores.nombre, EXCLUDED.nombre),
  por = EXCLUDED.por, actualizado = now();
WITH /*CTX*/
SELECT json_build_object('ok', true, 'proveedor_id', cfg.p->>'proveedor_id', 'activo', cfg.p->>'activo' = 'si') AS r FROM cfg;
