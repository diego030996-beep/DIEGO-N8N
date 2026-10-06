-- Guarda la configuración general y la de proveedores. p = {general: {clave: valor}, proveedores: [{proveedor_id, nombre, dias_entrega, dia_a, frec_b, activo, nota}]}
SET LOCAL statement_timeout = '15s';
WITH /*CTX*/
INSERT INTO compras_config (clave, valor, por)
SELECT x.key, x.value, cfg.por FROM cfg, jsonb_each_text(coalesce(cfg.p->'general', '{}'::jsonb)) AS x
ON CONFLICT (clave) DO UPDATE SET valor = EXCLUDED.valor, por = EXCLUDED.por, actualizado = now();
WITH /*CTX*/
INSERT INTO compras_proveedores (base, proveedor_id, nombre, dias_entrega, dia_a, frec_b, activo, nota, por)
SELECT cfg.base, x.proveedor_id, x.nombre, x.dias_entrega, x.dia_a, x.frec_b, coalesce(x.activo, true), x.nota, cfg.por
FROM cfg, jsonb_to_recordset(coalesce(cfg.p->'proveedores', '[]'::jsonb)) AS x(proveedor_id text, nombre text, dias_entrega numeric, dia_a int,
       frec_b int, activo boolean, nota text)
WHERE coalesce(x.proveedor_id, '') <> ''
ON CONFLICT (base, proveedor_id) DO UPDATE SET nombre = EXCLUDED.nombre, dias_entrega = EXCLUDED.dias_entrega, dia_a = EXCLUDED.dia_a,
  frec_b = EXCLUDED.frec_b, activo = EXCLUDED.activo, nota = EXCLUDED.nota, por = EXCLUDED.por, actualizado = now();
WITH /*CTX*/
SELECT json_build_object('ok', true, 'proveedores', jsonb_array_length(coalesce(cfg.p->'proveedores', '[]'::jsonb))) AS r FROM cfg;
