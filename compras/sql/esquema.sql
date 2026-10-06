-- Tablas del planeador de compras. Todo con IF NOT EXISTS: se puede correr cuantas veces sea.
CREATE TABLE IF NOT EXISTS compras_config (clave TEXT PRIMARY KEY, valor TEXT, por TEXT, actualizado TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE TABLE IF NOT EXISTS compras_proveedores (base TEXT NOT NULL, proveedor_id TEXT NOT NULL, nombre TEXT, dias_entrega NUMERIC,
  dia_a INT, frec_b INT, activo BOOLEAN NOT NULL DEFAULT true, nota TEXT, por TEXT, actualizado TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (base, proveedor_id));
CREATE TABLE IF NOT EXISTS compras_articulos (base TEXT NOT NULL, articulo_id BIGINT NOT NULL, proveedor_id TEXT, clase TEXT, empaque NUMERIC,
  minimo NUMERIC, maximo NUMERIC, excluir BOOLEAN NOT NULL DEFAULT false, nota TEXT, por TEXT, actualizado TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (base, articulo_id));
CREATE TABLE IF NOT EXISTS compras_maxmin (mes DATE NOT NULL, base TEXT NOT NULL, articulo_id BIGINT NOT NULL, clave TEXT, articulo TEXT, unidad TEXT,
  proveedor_id TEXT, proveedor TEXT, clase TEXT, venta NUMERIC, unidades NUMERIC, pct NUMERIC, pct_acum NUMERIC, venta_diaria NUMERIC,
  dias_entrega NUMERIC, dias_seguridad NUMERIC, dias_inventario NUMERIC, empaque NUMERIC, minimo NUMERIC, maximo NUMERIC, origen TEXT, alerta TEXT,
  periodo_ini DATE, periodo_fin DATE, dias_periodo INT, por TEXT, calculado TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (mes, base, articulo_id));
CREATE INDEX IF NOT EXISTS compras_maxmin_prov ON compras_maxmin (base, mes, proveedor_id);
ALTER TABLE compras_maxmin ADD COLUMN IF NOT EXISTS punto_reorden NUMERIC, ADD COLUMN IF NOT EXISTS rotacion TEXT,
  ADD COLUMN IF NOT EXISTS semanas_venta INT, ADD COLUMN IF NOT EXISTS semanas INT, ADD COLUMN IF NOT EXISTS tickets INT,
  ADD COLUMN IF NOT EXISTS desv_diaria NUMERIC, ADD COLUMN IF NOT EXISTS nivel_servicio NUMERIC, ADD COLUMN IF NOT EXISTS dias_revision NUMERIC,
  ADD COLUMN IF NOT EXISTS metodo TEXT;
CREATE TABLE IF NOT EXISTS compras_revision (base TEXT NOT NULL, articulo_id BIGINT NOT NULL, tipo TEXT NOT NULL, decision TEXT NOT NULL,
  grupo TEXT, nota TEXT, por TEXT, fecha TIMESTAMPTZ NOT NULL DEFAULT now(), PRIMARY KEY (base, articulo_id, tipo));
CREATE TABLE IF NOT EXISTS compras_planes (id BIGSERIAL PRIMARY KEY, base TEXT NOT NULL, fecha DATE NOT NULL, proveedor_id TEXT, proveedor TEXT,
  clase TEXT NOT NULL, origen TEXT NOT NULL DEFAULT 'planeador', folio TEXT, docto_cm_id TEXT, folio_oc TEXT, fecha_oc DATE, ligado TIMESTAMPTZ,
  por TEXT, creado TIMESTAMPTZ NOT NULL DEFAULT now(), modificado TIMESTAMPTZ);
CREATE UNIQUE INDEX IF NOT EXISTS compras_planes_oc ON compras_planes (base, docto_cm_id) WHERE docto_cm_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS compras_planes_dia ON compras_planes (base, fecha, proveedor_id) WHERE origen = 'planeador';
CREATE INDEX IF NOT EXISTS compras_planes_fecha ON compras_planes (base, fecha);
CREATE TABLE IF NOT EXISTS compras_decisiones (id BIGSERIAL PRIMARY KEY, plan_id BIGINT NOT NULL REFERENCES compras_planes (id) ON DELETE CASCADE,
  articulo_id BIGINT NOT NULL, clave TEXT, articulo TEXT, unidad TEXT, clase TEXT, existencia NUMERIC, pendiente NUMERIC, minimo NUMERIC, maximo NUMERIC,
  sugerido NUMERIC, comprado NUMERIC, razon TEXT, nota TEXT, oc_unidades NUMERIC, fuente TEXT, por TEXT,
  creado TIMESTAMPTZ NOT NULL DEFAULT now(), modificado TIMESTAMPTZ, UNIQUE (plan_id, articulo_id));
-- la foto diaria de inventario (flujo "Historial de inventario diario"); se crea aquí por si ese flujo está apagado
CREATE TABLE IF NOT EXISTS ms_existencias_hist (fecha DATE NOT NULL, base TEXT NOT NULL, almacen_id BIGINT NOT NULL, almacen TEXT,
  articulo_id BIGINT NOT NULL, clave TEXT, articulo TEXT, existencia NUMERIC, valor NUMERIC, guardado TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (fecha, base, almacen_id, articulo_id));
ALTER TABLE compras_decisiones ADD COLUMN IF NOT EXISTS punto_reorden NUMERIC;
