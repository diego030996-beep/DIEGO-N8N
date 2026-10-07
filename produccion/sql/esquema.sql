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
-- ---- auditoría de polímero ----
-- columnas nuevas (peso real del tinaco, tipo de exporte, precios por canal): solo se agregan si faltan, sin bloquear las tablas en cada petición
DO 'BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = ''prod_registro'' AND column_name = ''peso_real'') THEN
    ALTER TABLE prod_registro ADD COLUMN peso_real NUMERIC;
    ALTER TABLE prod_exporte ADD COLUMN tipo TEXT NOT NULL DEFAULT ''produccion'';
    ALTER TABLE prod_precio ALTER COLUMN precio DROP NOT NULL;
    ALTER TABLE prod_precio ADD COLUMN dist NUMERIC;
    ALTER TABLE prod_precio ADD COLUMN ml NUMERIC;
  END IF;
END';
-- pesajes físicos del polímero. teorico = lo que debía haber según el pesaje anterior + entradas − consumo de recetas
CREATE TABLE IF NOT EXISTS prod_conteo (id BIGSERIAL PRIMARY KEY, base TEXT NOT NULL, articulo_id BIGINT NOT NULL, fecha DATE NOT NULL, kg NUMERIC NOT NULL,
  base_id BIGINT, teorico NUMERIC, entradas NUMERIC, consumo NUMERIC, exceso NUMERIC, estado TEXT NOT NULL,   -- inicial | ok | revisar | confirmado | reemplazado
  reconteo_de BIGINT, nota TEXT, por TEXT, creado TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE INDEX IF NOT EXISTS prod_conteo_art ON prod_conteo (base, articulo_id, fecha);
-- ajustes por merma (diferencias confirmadas) que se mandan a Microsip
CREATE TABLE IF NOT EXISTS prod_ajuste (id BIGSERIAL PRIMARY KEY, base TEXT NOT NULL, conteo_id BIGINT NOT NULL UNIQUE, articulo_id BIGINT NOT NULL,
  kg NUMERIC NOT NULL, costo NUMERIC, exporte_id BIGINT, por TEXT, creado TIMESTAMPTZ NOT NULL DEFAULT now());
-- piezas fabricadas entre un pesaje y el anterior (para la predicción) y folio del documento de Microsip donde se importó cada archivo
DO 'BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = ''prod_conteo'' AND column_name = ''piezas'') THEN
    ALTER TABLE prod_conteo ADD COLUMN piezas NUMERIC;
    ALTER TABLE prod_exporte ADD COLUMN folio_ms TEXT;
  END IF;
END';
-- cargas de gas (lo que se cargó o compró). Cada carga llena el tanque: lo cargado es lo que se gastó desde la carga anterior.
CREATE TABLE IF NOT EXISTS prod_gas (id BIGSERIAL PRIMARY KEY, base TEXT NOT NULL, fecha DATE NOT NULL, litros NUMERIC, costo NUMERIC NOT NULL,
  nota TEXT, por TEXT, creado TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE INDEX IF NOT EXISTS prod_gas_fecha ON prod_gas (base, fecha);
