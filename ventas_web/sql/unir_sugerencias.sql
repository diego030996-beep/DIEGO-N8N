-- ===================== V8.65 · Sugerir qué chats unir (el mismo cliente por dos canales o dos números) =====================
-- El sistema busca solo los chats que parecen del mismo cliente y sugiere unirlos. No une nada sin que alguien le dé «Unir».
--   1) mismo teléfono en dos números de WhatsApp
--   2) el cliente escribió su teléfono en otro chat (Facebook, Instagram, página web, Telegram, correo u otro WhatsApp)
--   3) mismo nombre completo (nombre y apellido) en dos canales: es la pista más débil, sale al final para que la revises
-- Queda en el canal de WhatsApp con MÁS PLÁTICA (mensajes del cliente y nuestros). Solo WhatsApp puede ser el principal porque por ahí se le contesta.
-- «No es el mismo» lo guarda y esa pareja ya no se vuelve a sugerir.
CREATE TABLE IF NOT EXISTS wch_unir_descartes (a BIGINT NOT NULL, b BIGINT NOT NULL, por INT, en TIMESTAMPTZ NOT NULL DEFAULT now(), PRIMARY KEY (a, b));
CREATE TABLE IF NOT EXISTS wch_unir_sug (a BIGINT NOT NULL, b BIGINT NOT NULL, razon TEXT NOT NULL, fuerza INT NOT NULL, detalle TEXT, calc_en TIMESTAMPTZ NOT NULL DEFAULT now(), PRIMARY KEY (a, b));

-- teléfono de 10 dígitos de un chat de WhatsApp (en los otros canales el «teléfono» es un id de Facebook, Telegram, etc.)
CREATE OR REPLACE FUNCTION wch_tel10(p_tipo TEXT, p_tel TEXT) RETURNS TEXT LANGUAGE sql IMMUTABLE AS
$uni$ SELECT CASE WHEN p_tipo = 'whatsapp' AND length(regexp_replace(coalesce(p_tel, ''), '\D', '', 'g')) BETWEEN 10 AND 13
                  THEN right(regexp_replace(p_tel, '\D', '', 'g'), 10) END $uni$;

-- cuánta plática tiene un chat: mensajes del cliente y nuestros (sin los avisos del sistema)
CREATE OR REPLACE FUNCTION wch_interaccion(p_conv BIGINT) RETURNS INT LANGUAGE sql STABLE AS
$uni$ SELECT count(*)::int FROM wch_mensajes WHERE conv_id = p_conv AND origen <> 'sistema' $uni$;

-- nombre que sirve para comparar: nombre y apellido (2 palabras o más, 8 letras o más) y que no sea genérico
CREATE OR REPLACE FUNCTION wch_nom_cmp(p TEXT) RETURNS TEXT LANGUAGE sql IMMUTABLE AS
$uni$ SELECT CASE WHEN length(n) >= 8 AND n LIKE '% %' AND n !~ '^(cliente|usuario|user|sin nombre|whatsapp|facebook|instagram|visitante|invitado)\M' AND n !~ '^[0-9 ]+$' THEN n END
        FROM (SELECT trim(regexp_replace(translate(lower(coalesce(p, '')), 'áàäâéèëêíìïîóòöôúùüûñ', 'aaaaeeeeiiiioooouuuun'), '[^a-z0-9]+', ' ', 'g')) AS n) s $uni$;

-- Recalcula las sugerencias (lo corre «Revisar cola y avisos» cada 15 min, y la página si tienen más de 15 min). Regresa cuántas hay.
CREATE OR REPLACE FUNCTION wch_unir_sug_calc(p_forzar BOOLEAN DEFAULT false) RETURNS INT LANGUAGE plpgsql AS
$uni$
DECLARE n INT;
BEGIN
  IF to_regclass('public.wch_conversaciones') IS NULL THEN RETURN 0; END IF;
  IF NOT p_forzar AND EXISTS (SELECT 1 FROM vw_avisos WHERE clave = 'wch_unir_sug' AND momento > now() - interval '15 minutes') THEN
    RETURN (SELECT count(*) FROM wch_unir_sug);
  END IF;
  IF NOT pg_try_advisory_xact_lock(865065) THEN RETURN (SELECT count(*) FROM wch_unir_sug); END IF;   -- ya lo está calculando otro
  INSERT INTO vw_avisos (clave, momento) VALUES ('wch_unir_sug', now()) ON CONFLICT (clave) DO UPDATE SET momento = now();
  CREATE TEMP TABLE IF NOT EXISTS _wus (a BIGINT, b BIGINT, razon TEXT, fuerza INT, detalle TEXT) ON COMMIT DROP;
  TRUNCATE _wus;
  -- chats que cuentan: sin unir, no de Mercado Libre, con plática en los últimos 120 días
  CREATE TEMP TABLE IF NOT EXISTS _wuc ON COMMIT DROP AS
    SELECT x.id, x.marca, k.tipo, wch_tel10(k.tipo, x.telefono) AS tel, wch_nom_cmp(x.nombre) AS nom
      FROM wch_conversaciones x JOIN wch_canales k ON k.id = x.canal_id
     WHERE false;
  TRUNCATE _wuc;
  INSERT INTO _wuc
    SELECT x.id, x.marca, k.tipo, wch_tel10(k.tipo, x.telefono), wch_nom_cmp(x.nombre)
      FROM wch_conversaciones x JOIN wch_canales k ON k.id = x.canal_id
     WHERE x.unida_a IS NULL AND k.tipo <> 'mercadolibre' AND coalesce(x.ultimo_en, x.creado_en) > now() - interval '120 days';
  -- 1) mismo teléfono (dos números de WhatsApp)
  INSERT INTO _wus
    SELECT a.id, b.id, 'mismo teléfono', 1, NULL FROM _wuc a JOIN _wuc b ON b.tel = a.tel AND b.id > a.id AND b.marca = a.marca WHERE a.tel IS NOT NULL;
  -- 2) escribió su teléfono en otro chat
  INSERT INTO _wus
    SELECT least(s.conv_id, w.id), greatest(s.conv_id, w.id), 'dio su teléfono en el chat', 2, 'Escribió ' || s.tel || ' en el chat #' || s.conv_id
      FROM (SELECT DISTINCT m.conv_id, right(d, 10) AS tel
              FROM wch_mensajes m
              CROSS JOIN LATERAL regexp_matches(m.texto, '(\+?\d[\d .()-]{8,18}\d)', 'g') AS mm(g)
              CROSS JOIN LATERAL (SELECT regexp_replace(mm.g[1], '\D', '', 'g') AS d) dd
             WHERE m.dir = 'in' AND m.creado_en > now() - interval '120 days' AND m.texto ~ '\d{3}'
               AND length(dd.d) BETWEEN 10 AND 13 AND (length(dd.d) = 10 OR dd.d ~ '^(52|521|1)')) s
      JOIN _wuc o ON o.id = s.conv_id
      JOIN _wuc w ON w.tel = s.tel AND w.id <> s.conv_id AND w.marca = o.marca
     WHERE o.tel IS DISTINCT FROM s.tel;
  -- 3) mismo nombre completo en dos canales distintos
  INSERT INTO _wus
    SELECT a.id, b.id, 'mismo nombre', 3, NULL
      FROM _wuc a JOIN _wuc b ON b.nom = a.nom AND b.id > a.id AND b.marca = a.marca
     WHERE a.nom IS NOT NULL AND (a.tipo = 'whatsapp' OR b.tipo = 'whatsapp')
       AND NOT (a.tel IS NOT NULL AND b.tel IS NOT NULL AND a.tel <> b.tel AND a.tipo = b.tipo)   -- dos WhatsApp con teléfonos distintos y mismo nombre: casi siempre son dos personas
       AND (SELECT count(*) FROM _wuc z WHERE z.nom = a.nom) <= 3;                                  -- nombres muy comunes (4 o más chats) no se sugieren
  DELETE FROM wch_unir_sug;
  INSERT INTO wch_unir_sug (a, b, razon, fuerza, detalle)
    SELECT DISTINCT ON (s.a, s.b) s.a, s.b, s.razon, s.fuerza, s.detalle
      FROM _wus s JOIN _wuc x ON x.id = s.a JOIN _wuc y ON y.id = s.b
     WHERE (x.tipo = 'whatsapp' OR y.tipo = 'whatsapp')                               -- uno de los dos tiene que ser WhatsApp (por ahí se le contesta)
       AND NOT EXISTS (SELECT 1 FROM wch_unir_descartes d WHERE d.a = s.a AND d.b = s.b)
     ORDER BY s.a, s.b, s.fuerza;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END $uni$;

-- versión para el cron: si algo falla no detiene los demás avisos
CREATE OR REPLACE FUNCTION wch_unir_sug_cron() RETURNS INT LANGUAGE plpgsql AS
$uni$ BEGIN RETURN wch_unir_sug_calc(true);
EXCEPTION WHEN OTHERS THEN RAISE WARNING 'wch_unir_sug_calc: %', SQLERRM; RETURN -1; END $uni$;

-- datos de un chat para la sugerencia
CREATE OR REPLACE FUNCTION wch_unir_info(p_conv BIGINT) RETURNS JSONB LANGUAGE sql STABLE AS
$uni$ SELECT jsonb_build_object('id', x.id, 'nombre', x.nombre, 'telefono', x.telefono, 'canal', k.nombre, 'canal_tipo', k.tipo,
               'conectado', (k.phone_number_id IS NOT NULL), 'msgs', wch_interaccion(x.id), 'ultimo_en', x.ultimo_en, 'ultimo_texto', left(x.ultimo_texto, 80))
        FROM wch_conversaciones x JOIN wch_canales k ON k.id = x.canal_id WHERE x.id = p_conv $uni$;

-- en cuál de los dos queda: WhatsApp → más plática → conectado a la web → el más reciente
CREATE OR REPLACE FUNCTION wch_unir_prin(ia JSONB, ib JSONB) RETURNS INT LANGUAGE sql IMMUTABLE AS
$uni$ SELECT CASE
  WHEN (ia ->> 'canal_tipo' = 'whatsapp') <> (ib ->> 'canal_tipo' = 'whatsapp') THEN CASE WHEN ia ->> 'canal_tipo' = 'whatsapp' THEN 1 ELSE 2 END
  WHEN (ia ->> 'msgs')::int <> (ib ->> 'msgs')::int THEN CASE WHEN (ia ->> 'msgs')::int > (ib ->> 'msgs')::int THEN 1 ELSE 2 END
  WHEN (ia ->> 'conectado')::boolean <> (ib ->> 'conectado')::boolean THEN CASE WHEN (ia ->> 'conectado')::boolean THEN 1 ELSE 2 END
  WHEN coalesce((ia ->> 'ultimo_en')::timestamptz, '-infinity') >= coalesce((ib ->> 'ultimo_en')::timestamptz, '-infinity') THEN 1 ELSE 2 END $uni$;

-- lista de sugerencias para la página (todas, o solo las de un chat). Cada una ya dice en cuál queda y por qué.
CREATE OR REPLACE FUNCTION wch_unir_sug_lista(u vw_usuarios, p_conv BIGINT, p_lim INT DEFAULT 60) RETURNS JSONB LANGUAGE plpgsql AS
$uni$
DECLARE r JSONB;
BEGIN
  WITH s AS (
    SELECT s.a, s.b, s.razon, s.fuerza, s.detalle FROM wch_unir_sug s WHERE p_conv IS NULL OR p_conv IN (s.a, s.b)
    UNION ALL
    -- en vivo para el chat abierto: mismo teléfono (por si el chat es nuevo y el cálculo de cada 15 min todavía no lo ve)
    SELECT least(a.id, b.id), greatest(a.id, b.id), 'mismo teléfono', 1, NULL
      FROM wch_conversaciones a JOIN wch_canales ka ON ka.id = a.canal_id
      JOIN wch_conversaciones b ON b.id <> a.id AND b.marca = a.marca AND b.unida_a IS NULL
      JOIN wch_canales kb ON kb.id = b.canal_id AND kb.tipo = 'whatsapp'
     WHERE p_conv IS NOT NULL AND a.id = p_conv AND a.unida_a IS NULL AND wch_tel10(ka.tipo, a.telefono) IS NOT NULL
       AND wch_tel10(kb.tipo, b.telefono) = wch_tel10(ka.tipo, a.telefono)
  ), s1 AS (
    SELECT DISTINCT ON (a, b) * FROM s ORDER BY a, b, fuerza
  ), d AS (
    SELECT s1.*, wch_unir_info(s1.a) AS ia, wch_unir_info(s1.b) AS ib, greatest(x.ultimo_en, y.ultimo_en) AS reciente
      FROM s1 JOIN wch_conversaciones x ON x.id = s1.a JOIN wch_conversaciones y ON y.id = s1.b
     WHERE x.unida_a IS NULL AND y.unida_a IS NULL AND x.marca = y.marca
       AND wch_vc(u, x.marca, x.canal_id) AND wch_vc(u, y.marca, y.canal_id)
       AND NOT EXISTS (SELECT 1 FROM wch_unir_descartes z WHERE z.a = s1.a AND z.b = s1.b)
     ORDER BY s1.fuerza, greatest(x.ultimo_en, y.ultimo_en) DESC NULLS LAST LIMIT p_lim
  ), e AS (
    SELECT d.*, CASE WHEN wch_unir_prin(ia, ib) = 1 THEN ia ELSE ib END AS pr, CASE WHEN wch_unir_prin(ia, ib) = 1 THEN ib ELSE ia END AS ot FROM d
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object('principal', pr, 'otro', ot, 'razon', razon, 'fuerza', fuerza, 'detalle', detalle,
           'por_que', CASE
             WHEN ot ->> 'canal_tipo' <> 'whatsapp' AND (ot ->> 'msgs')::int > (pr ->> 'msgs')::int
               THEN 'Queda en WhatsApp: el de ' || coalesce(ot ->> 'canal', '') || ' tiene más mensajes, pero solo por WhatsApp se le contesta desde aquí.'
             WHEN ot ->> 'canal_tipo' <> 'whatsapp' THEN 'Queda en WhatsApp: ahí tiene más plática (' || (pr ->> 'msgs') || ' contra ' || (ot ->> 'msgs') || ' mensajes) y por ahí se le contesta.'
             WHEN (pr ->> 'msgs')::int > (ot ->> 'msgs')::int THEN 'Queda en «' || coalesce(pr ->> 'canal', '') || '»: ahí tiene más plática (' || (pr ->> 'msgs') || ' contra ' || (ot ->> 'msgs') || ' mensajes).'
             ELSE 'Los dos tienen la misma plática (' || (pr ->> 'msgs') || ' mensajes cada uno); queda en el ' || CASE WHEN (pr ->> 'conectado')::boolean AND NOT (ot ->> 'conectado')::boolean THEN 'que está conectado a la web.' ELSE 'más reciente.' END
           END,
           'aviso', CASE WHEN NOT (pr ->> 'conectado')::boolean THEN 'Ese número de WhatsApp no está conectado a la web: desde aquí no le vas a poder contestar.' END)
         ORDER BY fuerza, reciente DESC NULLS LAST), '[]'::jsonb) INTO r FROM e;
  RETURN r;
END $uni$;

-- acciones nuevas de Chats (el resto de «Unir chats» sigue en wch_unir_fn)
CREATE OR REPLACE FUNCTION wch_unir_fn2(acc TEXT, u vw_usuarios, p JSONB) RETURNS JSONB LANGUAGE plpgsql AS
$uni$
DECLARE r JSONB; v_a BIGINT; v_b BIGINT; v_n INT; v_cand JSONB; v_conv BIGINT := nullif(p ->> 'conv_id', '')::bigint;
BEGIN
  IF acc = 'wch_unir_sug' THEN
    -- {conv_id (opcional), refrescar: 'si'}
    BEGIN
      PERFORM wch_unir_sug_calc(coalesce(p ->> 'refrescar', '') = 'si');
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'wch_unir_sug_calc: %', SQLERRM;
    END;
    RETURN jsonb_build_object('ok', true, 'lista', wch_unir_sug_lista(u, v_conv, CASE WHEN v_conv IS NULL THEN 60 ELSE 10 END),
                              'calculado', (SELECT momento FROM vw_avisos WHERE clave = 'wch_unir_sug'));
  ELSIF acc = 'wch_unir_descartar' THEN
    -- «No es el mismo cliente»: esa pareja ya no se vuelve a sugerir
    v_a := least((p ->> 'a')::bigint, (p ->> 'b')::bigint); v_b := greatest((p ->> 'a')::bigint, (p ->> 'b')::bigint);
    IF v_a IS NULL OR v_a = v_b THEN RETURN jsonb_build_object('ok', false, 'msg', 'Escoge dos chats distintos.'); END IF;
    IF NOT EXISTS (SELECT 1 FROM wch_conversaciones x WHERE x.id = v_a AND wch_vc(u, x.marca, x.canal_id))
       OR NOT EXISTS (SELECT 1 FROM wch_conversaciones x WHERE x.id = v_b AND wch_vc(u, x.marca, x.canal_id)) THEN
      RETURN jsonb_build_object('ok', false, 'msg', 'Conversación no disponible.');
    END IF;
    INSERT INTO wch_unir_descartes (a, b, por) VALUES (v_a, v_b, u.id) ON CONFLICT (a, b) DO NOTHING;
    DELETE FROM wch_unir_sug WHERE a = v_a AND b = v_b;
    RETURN jsonb_build_object('ok', true, 'msg', 'Listo: ya no se sugiere unir esos dos chats.');
  ELSIF acc = 'wch_unir' THEN
    r := wch_unir_fn(acc, u, p);
    IF coalesce((r ->> 'ok')::boolean, false) THEN
      -- el chat que se unió ya no se sugiere; las parejas del principal se recalculan al leerlas
      DELETE FROM wch_unir_sug WHERE (p ->> 'otro')::bigint IN (a, b) OR (a = least((p ->> 'otro')::bigint, (p ->> 'principal')::bigint) AND b = greatest((p ->> 'otro')::bigint, (p ->> 'principal')::bigint));
    END IF;
    RETURN r;
  ELSIF acc = 'wch_unir_cand' THEN
    -- los candidatos de siempre + los sugeridos (ej. dio su teléfono en el chat), cada uno con su plática para escoger el principal
    r := wch_unir_fn(acc, u, p);
    IF NOT coalesce((r ->> 'ok')::boolean, false) THEN RETURN r; END IF;
    SELECT coalesce(jsonb_agg(z.j ORDER BY z.o, z.n), '[]'::jsonb) INTO v_cand FROM (
      SELECT e || jsonb_build_object('msgs', wch_interaccion((e ->> 'id')::bigint),
                                     'sugerido', EXISTS (SELECT 1 FROM wch_unir_sug s WHERE s.a = least(v_conv, (e ->> 'id')::bigint) AND s.b = greatest(v_conv, (e ->> 'id')::bigint))) AS j,
             0 AS o, n
        FROM jsonb_array_elements(r -> 'lista') WITH ORDINALITY AS t(e, n)
      UNION ALL
      SELECT jsonb_build_object('id', x.id, 'nombre', x.nombre, 'telefono', x.telefono, 'canal', k.nombre, 'canal_tipo', k.tipo, 'conectado', (k.phone_number_id IS NOT NULL),
               'ultimo_texto', left(x.ultimo_texto, 80), 'ultimo_en', x.ultimo_en, 'rank', 0, 'razon', s.razon || coalesce(' · ' || s.detalle, ''),
               'msgs', wch_interaccion(x.id), 'sugerido', true), -1, x.id
        FROM wch_unir_sug s JOIN wch_conversaciones x ON x.id = CASE WHEN s.a = v_conv THEN s.b ELSE s.a END JOIN wch_canales k ON k.id = x.canal_id
       WHERE v_conv IN (s.a, s.b) AND x.unida_a IS NULL AND wch_vc(u, x.marca, x.canal_id)
         AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r -> 'lista') e WHERE (e ->> 'id')::bigint = x.id)
         AND coalesce(nullif(p ->> 'q', ''), '') = ''
    ) z;
    RETURN r || jsonb_build_object('lista', v_cand, 'yo_msgs', wch_interaccion(v_conv));
  END IF;
  RETURN wch_unir_fn(acc, u, p);
END $uni$;
