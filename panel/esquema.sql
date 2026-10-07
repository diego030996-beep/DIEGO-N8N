-- Panel general: PIN (uno solo, con sal) + sesiones + ligas propias. Las tablas de llaves son las mismas de los otros flujos.
CREATE TABLE IF NOT EXISTS tablero_acceso (token TEXT PRIMARY KEY, rol TEXT NOT NULL, activo BOOLEAN NOT NULL DEFAULT true, creado TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE TABLE IF NOT EXISTS choferes_web (token TEXT PRIMARY KEY, nombre TEXT NOT NULL, activo BOOLEAN NOT NULL DEFAULT true, creado TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE TABLE IF NOT EXISTS panel_pin (id INT PRIMARY KEY DEFAULT 1 CHECK (id = 1), pin_sal TEXT NOT NULL, pin_hash TEXT NOT NULL,
  intentos INT NOT NULL DEFAULT 0, bloqueado_hasta TIMESTAMPTZ, cambiado TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE TABLE IF NOT EXISTS panel_sesion (token TEXT PRIMARY KEY, vence TIMESTAMPTZ NOT NULL, creado TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE TABLE IF NOT EXISTS panel_liga (id SERIAL PRIMARY KEY, titulo TEXT NOT NULL, url TEXT NOT NULL, grupo TEXT NOT NULL DEFAULT 'Otras ligas',
  creado TIMESTAMPTZ NOT NULL DEFAULT now());
DELETE FROM panel_sesion WHERE vence < now();
-- Bitácora de regeneraciones: guarda solo el hash de la llave nueva (nunca la llave) para saber cuándo se regeneró cada una.
CREATE TABLE IF NOT EXISTS panel_rotacion (id SERIAL PRIMARY KEY, fuente TEXT NOT NULL, etiqueta TEXT NOT NULL, token_hash TEXT NOT NULL,
  tipo TEXT NOT NULL DEFAULT 'una', fecha TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE INDEX IF NOT EXISTS panel_rotacion_hash ON panel_rotacion (token_hash);
