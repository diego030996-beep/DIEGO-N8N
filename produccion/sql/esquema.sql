-- Tablas del módulo de producción de tinacos. No toca ninguna tabla de Microsip (ms_*): solo las lee.
CREATE TABLE IF NOT EXISTS prod_config (clave TEXT PRIMARY KEY, valor TEXT, por TEXT, actualizado TIMESTAMPTZ NOT NULL DEFAULT now());
-- receta: qué sale del inventario por cada tinaco (polímero en kg, tapa, kit...)
CREATE TABLE IF NOT EXISTS prod_receta (base TEXT NOT NULL, articulo_id BIGINT NOT NULL, componente_id BIGINT NOT NULL, cantidad NUMERIC NOT NULL,
  por TEXT, actualizado TIMESTAMPTZ NOT NULL DEFAULT now(), PRIMARY KEY (base, articulo_id, componente_id));
-- gastos que NO salen del inventario (mano de obra del quemador, gas, luz, etiquetas): solo para la simulación de utilidad, por tinaco
CREATE TABLE IF NOT EXISTS prod_extra (id BIGSERIAL PRIMARY KEY, base TEXT NOT NULL, concepto TEXT NOT NULL, monto NUMERIC NOT NULL,
  articulo_id BIGINT, por TEXT, actualizado TIMESTAMPTZ NOT NULL DEFAULT now());
-- precio de venta para la simulación (si no hay, el precio de lista de Microsip)
CREATE TABLE IF NOT EXISTS prod_precio (base TEXT NOT NULL, articulo_id BIGINT NOT NULL, precio NUMERIC NOT NULL, por TEXT,
  actualizado TIMESTAMPTZ NOT NULL DEFAULT now(), PRIMARY KEY (base, articulo_id));
-- lo que se fabricó (con la receta y el costo de ese momento)
CREATE TABLE IF NOT EXISTS prod_exporte (id BIGSERIAL PRIMARY KEY, base TEXT NOT NULL, desde DATE, hasta DATE, registros INT, por TEXT,
  creado TIMESTAMPTZ NOT NULL DEFAULT now(), importado TIMESTAMPTZ, importado_por TEXT);
CREATE TABLE IF NOT EXISTS prod_registro (id BIGSERIAL PRIMARY KEY, base TEXT NOT NULL, fecha DATE NOT NULL, articulo_id BIGINT NOT NULL,
  cantidad NUMERIC NOT NULL, costo_unit NUMERIC, nota TEXT, por TEXT, creado TIMESTAMPTZ NOT NULL DEFAULT now(),
  exporte_id BIGINT REFERENCES prod_exporte(id));
CREATE INDEX IF NOT EXISTS prod_registro_fecha ON prod_registro (base, fecha);
CREATE TABLE IF NOT EXISTS prod_registro_det (registro_id BIGINT NOT NULL REFERENCES prod_registro(id) ON DELETE CASCADE, componente_id BIGINT NOT NULL,
  cantidad NUMERIC NOT NULL, costo_unit NUMERIC, PRIMARY KEY (registro_id, componente_id));
