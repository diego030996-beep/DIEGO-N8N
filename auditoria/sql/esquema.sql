-- Auditoría de movimientos: lo que reporta cada empleado (retiro → comprobantes → compra en Microsip → pedido) y lo que revisa la auditora.
CREATE TABLE IF NOT EXISTS tablero_acceso (token TEXT PRIMARY KEY, rol TEXT NOT NULL, activo BOOLEAN NOT NULL DEFAULT true, creado TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE TABLE IF NOT EXISTS mov_empleado (token TEXT PRIMARY KEY, nombre TEXT NOT NULL, activo BOOLEAN NOT NULL DEFAULT true, creado TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE TABLE IF NOT EXISTS mov_config (clave TEXT PRIMARY KEY, valor TEXT, por TEXT, actualizado TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE TABLE IF NOT EXISTS mov_registro (id BIGSERIAL PRIMARY KEY, base TEXT NOT NULL DEFAULT '', fecha DATE NOT NULL, hora TEXT,
  retiro_id TEXT, retiro_folio TEXT, metodo TEXT NOT NULL, tipo TEXT NOT NULL, concepto TEXT NOT NULL, proveedor TEXT, pedido TEXT,
  importe NUMERIC NOT NULL, empleado TEXT NOT NULL, compra_id TEXT, revision TEXT, revision_nota TEXT, revisado_por TEXT, revisado_en TIMESTAMPTZ,
  borrado BOOLEAN NOT NULL DEFAULT false, creado TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE UNIQUE INDEX IF NOT EXISTS mov_registro_retiro ON mov_registro (base, retiro_id) WHERE retiro_id IS NOT NULL AND NOT borrado;
CREATE INDEX IF NOT EXISTS mov_registro_fecha ON mov_registro (fecha);
-- cobros con tarjeta / transferencia / Mercado Pago: "ticket:forma" de Microsip
DO 'BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = ''mov_registro'' AND column_name = ''cobro_id'') THEN
    ALTER TABLE mov_registro ADD COLUMN cobro_id TEXT;
    CREATE UNIQUE INDEX mov_registro_cobro ON mov_registro (base, cobro_id) WHERE cobro_id IS NOT NULL AND NOT borrado;
  END IF;
END';
CREATE TABLE IF NOT EXISTS mov_comprobante (id BIGSERIAL PRIMARY KEY, registro_id BIGINT NOT NULL REFERENCES mov_registro (id), importe NUMERIC NOT NULL,
  tipo TEXT NOT NULL DEFAULT 'ticket', foto TEXT NOT NULL, por TEXT, creado TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE INDEX IF NOT EXISTS mov_comprobante_reg ON mov_comprobante (registro_id);
-- retiros o compras de Microsip que la auditora marcó como "no requiere comprobación" (depósito al banco, compra a crédito, etc.)
CREATE TABLE IF NOT EXISTS mov_ignorado (base TEXT NOT NULL DEFAULT '', tipo TEXT NOT NULL, ref TEXT NOT NULL, motivo TEXT, por TEXT,
  creado TIMESTAMPTZ NOT NULL DEFAULT now(), PRIMARY KEY (base, tipo, ref));
-- bitácora: quién hizo qué (registrar, aprobar, vincular, ignorar…)
CREATE TABLE IF NOT EXISTS mov_bitacora (id BIGSERIAL PRIMARY KEY, registro_id BIGINT, ref TEXT, accion TEXT NOT NULL, detalle TEXT, por TEXT,
  creado TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE INDEX IF NOT EXISTS mov_bitacora_reg ON mov_bitacora (registro_id);
-- corte de caja firmado (en lugar de la libreta): lo que había que entregar, lo que se entregó y quién firmó
CREATE TABLE IF NOT EXISTS mov_corte (base TEXT NOT NULL DEFAULT '', fecha DATE NOT NULL, esperado NUMERIC, entregado NUMERIC, diferencia NUMERIC,
  pendientes INT, pendiente_monto NUMERIC, nota TEXT, firmado_por TEXT, firmado_en TIMESTAMPTZ NOT NULL DEFAULT now(), PRIMARY KEY (base, fecha));
CREATE TABLE IF NOT EXISTS mov_aviso (clave TEXT PRIMARY KEY, enviado TIMESTAMPTZ NOT NULL DEFAULT now());
-- la auditoría empieza el día que se instala (no revisa todo el pasado de Microsip)
INSERT INTO mov_config (clave, valor, por) SELECT 'desde', to_char((now() AT TIME ZONE 'America/Mexico_City')::date, 'YYYY-MM-DD'), 'instalación'
WHERE NOT EXISTS (SELECT 1 FROM mov_config WHERE clave = 'desde');
