// Planeador de compras: revisa lo que pide la página (o el reloj de cada mes) y arma UNA consulta para Postgres.
// Todo el trabajo pesado lo hace Postgres en una sola petición, con límite de tiempo, para no frenar los demás flujos.
const SQL = __SQL__;
const DEF = __DEF__;
const hoyMX = new Date(Date.now() - 6 * 3600000).toISOString().slice(0, 10);   // Ciudad de México (UTC-6)
const mesHoy = hoyMX.slice(0, 8) + '01';
const arma = (op, p, por, desde, rol) => [{ json: { ok: true, op, desde, rol: rol || '', sql: SQL[op],
  params: ['', JSON.stringify(DEF), String(por).slice(0, 80), JSON.stringify(p || {}), ''] } }];

let desdePagina = false;
try { desdePagina = $('API').isExecuted; } catch (e) { desdePagina = false; }
if (!desdePagina) return arma('calcular', { mes: mesHoy }, 'automático (día 1)', 'reloj');

const fail = msg => [{ json: { ok: false, desde: 'pagina', respuesta: { ok: false, msg } } }];
const rol = String($('Acceso').first().json.rol || '');
if (!rol) return fail('Esta liga no tiene permiso. Pide la liga del planeador al administrador.');
const b = $('API').first().json.body || {};
const op = String(b.op || '');
if (!SQL[op]) return fail('Operación desconocida.');
const ESCRIBE = ['guardar', 'razon', 'folio', 'reconstruir', 'calcular', 'articulo', 'config'];
if (rol === 'auditor' && ESCRIBE.includes(op)) return fail('Esta liga es solo de consulta.');
const quien = String(b.quien || '').replace(/[^\p{L}\p{N} .\-]/gu, '').trim().slice(0, 40);
const por = quien ? quien + ' (' + rol + ')' : rol;

// razones válidas: las guardadas en la base o las de fábrica
const razTxt = String($('Acceso').first().json.razones || DEF.razones || '');
const RAZ = new Set(razTxt.split(/\n+/).map(l => l.split('=')[0].trim()).filter(Boolean));
const numOk = (v, min, max) => v === '' || v === null || v === undefined || (isFinite(Number(v)) && Number(v) >= min && Number(v) <= max);
const txt = (v, n) => String(v ?? '').replace(/\s+/g, ' ').trim().slice(0, n);
const mesOk = v => /^\d{4}-\d{2}(-01)?$/.test(String(v || '')) && String(v).slice(0, 7) <= hoyMX.slice(0, 7) && String(v) >= '2020-01';
const fechaOk = v => /^\d{4}-\d{2}-\d{2}$/.test(String(v || ''));
const idOk = v => Number.isInteger(Number(v)) && Number(v) > 0;
const provOk = v => /^[0-9A-Za-z_\-]{0,40}$/.test(String(v ?? ''));
let p = {};

switch (op) {
  case 'datos': break;
  case 'planeador':
    if (!provOk(b.proveedor_id)) return fail('Proveedor inválido.');
    p = { proveedor_id: String(b.proveedor_id || '') };
    break;
  case 'guardar': {
    if (!provOk(b.proveedor_id) || !b.proveedor_id) return fail('Elige el proveedor.');
    if (!['A', 'B', 'C'].includes(b.clase)) return fail('Elige productos A, B o C.');
    const L = Array.isArray(b.lineas) ? b.lineas : [];
    if (L.length > 800) return fail('Demasiados renglones.');
    const lineas = [];
    for (const l of L) {
      if (!idOk(l.articulo_id)) return fail('Artículo inválido.');
      if (l.comprado === null || l.comprado === '' || !numOk(l.comprado, 0, 1e7)) return fail('Revisa la cantidad de ' + txt(l.articulo, 60) + '.');
      const distinto = Number(l.comprado) !== Number(l.sugerido);
      const razon = distinto ? String(l.razon || '') : '';
      const nota = txt(l.nota, 300);
      if (distinto && !RAZ.has(razon)) return fail('Falta la razón de ' + txt(l.articulo, 60) + '.');
      if (razon === 'otra' && !nota) return fail('Escribe la nota de ' + txt(l.articulo, 60) + '.');
      const n = k => (l[k] === null || l[k] === undefined || l[k] === '' || !isFinite(Number(l[k]))) ? null : Number(l[k]);
      lineas.push({ articulo_id: Number(l.articulo_id), clave: txt(l.clave, 40), articulo: txt(l.articulo, 160), unidad: txt(l.unidad, 30),
        clase: ['A', 'B', 'C'].includes(l.clase) ? l.clase : 'C', existencia: n('existencia'), pendiente: n('pendiente'), minimo: n('minimo'), maximo: n('maximo'),
        sugerido: n('sugerido'), comprado: Number(l.comprado), razon, nota });
    }
    p = { proveedor_id: String(b.proveedor_id), proveedor: txt(b.proveedor, 120), clase: b.clase, folio: txt(b.folio, 30), lineas };
    break;
  }
  case 'razon': {
    if (!idOk(b.id)) return fail('Renglón inválido.');
    const razon = String(b.razon || ''), nota = txt(b.nota, 300);
    if (razon && !RAZ.has(razon)) return fail('Razón inválida.');
    if (razon === 'otra' && !nota) return fail('Escribe la nota (elegiste Otra).');
    p = { id: Number(b.id), razon, nota };
    break;
  }
  case 'folio':
    if (!idOk(b.plan_id)) return fail('Plan inválido.');
    p = { plan_id: Number(b.plan_id), folio: txt(b.folio, 30) };
    break;
  case 'registro': case 'reporte': case 'calcular': case 'reconstruir':
    if (op === 'reporte' && !b.mes) { p = {}; break; }
    if (!mesOk(b.mes)) return fail('Revisa el mes (no puede ser futuro).');
    p = { mes: String(b.mes).slice(0, 7) + '-01' };
    if (op === 'reconstruir') { p.solo_si_falta = 'si'; if (p.mes >= mesHoy) return fail('Reconstruir es para meses pasados; para este mes usa el planeador.'); }
    break;
  case 'ocs':
    if (!fechaOk(b.desde) || !fechaOk(b.hasta) || b.desde > b.hasta) return fail('Revisa las fechas.');
    p = { desde: b.desde, hasta: b.hasta };
    break;
  case 'buscar':
    p = { q: txt(b.q, 60), solo_ajustados: b.solo_ajustados === 'si' ? 'si' : '' };
    break;
  case 'articulo': {
    if (!idOk(b.articulo_id)) return fail('Artículo inválido.');
    if (!provOk(b.proveedor_id)) return fail('Proveedor inválido.');
    for (const k of ['empaque', 'minimo', 'maximo']) if (!numOk(b[k], 0, 1e7)) return fail('Revisa ' + k + '.');
    const mn = b.minimo === '' ? null : Number(b.minimo), mx = b.maximo === '' ? null : Number(b.maximo);
    if (mn === 0 || mx === 0) return fail('El mínimo y el máximo no pueden ser cero.');
    if (mn !== null && mx !== null && mx <= mn) return fail('El máximo debe ser mayor que el mínimo.');
    p = { articulo_id: Number(b.articulo_id), proveedor_id: String(b.proveedor_id || ''), clase: ['A', 'B', 'C'].includes(b.clase) ? b.clase : '',
          empaque: String(b.empaque ?? ''), minimo: String(b.minimo ?? ''), maximo: String(b.maximo ?? ''),
          excluir: b.excluir === 'true' ? 'true' : 'false', nota: txt(b.nota, 200) };
    break;
  }
  case 'config': {
    const REGLAS = {
      meses_abc: v => numOk(v, 1, 24) && Number.isInteger(Number(v)), corte_a: v => numOk(v, 50, 95),
      seg_a: v => numOk(v, 0, 120), inv_a: v => numOk(v, 1, 365), seg_b: v => numOk(v, 0, 120), inv_b: v => numOk(v, 1, 365),
      meses_c: v => numOk(v, 1, 36) && Number.isInteger(Number(v)), seg_c: v => numOk(v, 0, 120), inv_c: v => numOk(v, 1, 365),
      min_c: v => numOk(v, 1, 1000),
      lineas_excluidas: v => { try { new RegExp(v, 'i'); return String(v).length <= 200; } catch (e) { return false; } },
      entrega_def: v => numOk(v, 0, 120), dia_a: v => ['1', '2', '3', '4', '5', '6', '7'].includes(String(v)), frec_b: v => numOk(v, 1, 90),
      regla: v => ['bajo_minimo', 'hasta_maximo'].includes(v), gracia_oc: v => numOk(v, 0, 60), dias_ligar: v => numOk(v, 0, 30),
      almacenes: v => { try { new RegExp(v, 'i'); return String(v).length <= 200; } catch (e) { return false; } },
      excluir: v => { try { new RegExp(v, 'i'); return String(v).length <= 200; } catch (e) { return false; } },
      monto_maximo: v => numOk(v, 1, 1e9), empresa: v => String(v).length <= 120, tienda: v => String(v).length <= 120,
      razones: v => String(v).length <= 3000 && /^no_documentado=/m.test(v) && /^otra=/m.test(v),
      base: v => String(v).length <= 80,
    };
    const NUM = ['meses_abc', 'corte_a', 'seg_a', 'inv_a', 'seg_b', 'inv_b', 'meses_c', 'seg_c', 'inv_c', 'min_c', 'entrega_def', 'frec_b', 'gracia_oc', 'dias_ligar', 'monto_maximo'];
    const general = {};
    for (const [k, v0] of Object.entries(b.general || {})) {
      if (!REGLAS[k]) continue;
      const v = k === 'razones' ? String(v0 ?? '').trim() : String(v0 ?? '').trim();
      if (v === '' && NUM.includes(k)) { general[k] = ''; continue; }
      if (!REGLAS[k](v)) return fail('Revisa el valor de "' + k + '".');
      general[k] = v;
    }
    const proveedores = [];
    for (const x of (Array.isArray(b.proveedores) ? b.proveedores : []).slice(0, 1000)) {
      if (!provOk(x.proveedor_id) || !x.proveedor_id) return fail('Proveedor inválido.');
      if (!numOk(x.dias_entrega, 0, 120) || !numOk(x.frec_b, 1, 90) || !(x.dia_a === null || x.dia_a === '' || [1, 2, 3, 4, 5, 6, 7].includes(Number(x.dia_a))))
        return fail('Revisa los datos de ' + txt(x.nombre, 60) + '.');
      const n = v => (v === null || v === '' || v === undefined) ? null : Number(v);
      proveedores.push({ proveedor_id: String(x.proveedor_id), nombre: txt(x.nombre, 120), dias_entrega: n(x.dias_entrega), dia_a: n(x.dia_a),
                         frec_b: n(x.frec_b) === null ? null : Math.round(n(x.frec_b)), activo: x.activo !== false, nota: txt(x.nota, 200) });
    }
    p = { general, proveedores };
    break;
  }
}
return arma(op, p, por, 'pagina', rol);
