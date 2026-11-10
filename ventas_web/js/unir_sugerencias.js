// ===== V8.65 · Sugerir qué chats unir (mismo cliente por dos canales o dos números) =====
// El sistema busca los chats que parecen del mismo cliente; aquí solo se muestran y se unen con un toque.
// Siempre queda en el WhatsApp con más plática (mensajes del cliente y nuestros).
const CHU = { t: 0, lista: [], porConv: {}, cargando: null };
function chUniTxt(x) { return esc(x.nombre || chTel(x.telefono)) + ' <span class="tag">' + esc(x.canal || '') + '</span> <span class="tag acc">#' + x.id + '</span>'; }
function chUniMsgs(x) { return (x.msgs || 0) + ' mensaje' + (x.msgs === 1 ? '' : 's'); }
async function chUniSugCarga(forzar) {
  if (!forzar && CHU.cargando) return CHU.cargando;
  if (!forzar && Date.now() - CHU.t < 120000) return CHU.lista;
  CHU.t = Date.now();
  CHU.cargando = call('wch_unir_sug', { refrescar: forzar ? 'si' : '' }, { quiet: true }).then(r => {
    if (r && r.ok) { CHU.lista = r.lista || []; CHU.calc = r.calculado; }
    return CHU.lista;
  }).catch(() => CHU.lista).finally(() => { CHU.cargando = null; chUniBtn(); });
  return CHU.cargando;
}
// botón 🔗 en la cabecera de la lista de chats, con cuántas sugerencias hay
function chUniBtn() {
  const top = document.querySelector('#chHL .chx-top'); if (!top) return;
  let b = $('chUniB'); const n = (CHU.lista || []).length;
  if (!n) { if (b) b.remove(); return; }
  if (!b) { b = document.createElement('button'); b.id = 'chUniB'; b.className = 'chx-ib'; b.onclick = () => chUniSugModal(); const m = $('chMuteB'); top.insertBefore(b, m || null); }
  b.title = n + ' pareja(s) de chats que parecen del mismo cliente'; b.innerHTML = '🔗<span class="chx-n" style="margin-left:2px">' + n + '</span>';
}
{ const chCabU = chPintaCab;
  chPintaCab = function () { chCabU.apply(this, arguments); try { chUniBtn(); chUniSugCarga(false); } catch (e) { } };
}
// aviso dentro del chat abierto: «parece el mismo cliente que…»
async function chUniSugConv(id, forzar) {
  const c = CHU.porConv[id];
  if (!forzar && c && Date.now() - c.t < 60000) return c.lista;
  const r = await call('wch_unir_sug', { conv_id: id }, { quiet: true }).catch(() => null);
  CHU.porConv[id] = { t: Date.now(), lista: (r && r.ok && r.lista) || [] };
  return CHU.porConv[id].lista;
}
function chUniBanner() {
  const c = CH.chat && CH.chat.conv, hd = $('chHd'); if (!c || !hd) return;
  const old = $('chUniBan'); if (old) old.remove();
  const l = (CHU.porConv[c.id] || {}).lista || []; if (!l.length) return;
  const s = l[0], o = s.principal.id === c.id ? s.otro : s.principal;
  const d = document.createElement('div'); d.id = 'chUniBan'; d.className = 'banner warn'; d.style.cssText = 'margin:6px 10px;font-size:13px';
  d.innerHTML = '🔗 Parece el mismo cliente que ' + chUniTxt(o) + ' (' + esc(s.razon) + ').<br><span class="mut">' + esc(s.por_que) + (s.aviso ? ' ⚠️ ' + esc(s.aviso) : '') + '</span>' +
    (l.length > 1 ? '<br><span class="mut">Y ' + (l.length - 1) + ' chat(s) más que también parecen suyos.</span>' : '') +
    '<div class="auto" style="margin-top:6px"><button class="p" onclick="chUniHacer(' + s.principal.id + ',' + s.otro.id + ')">🔗 Unir en «' + esc(s.principal.canal || '') + '»</button>' +
    '<button onclick="chUniNo(' + s.principal.id + ',' + s.otro.id + ')">No es el mismo</button>' + (l.length > 1 ? '<button onclick="chUnirModal()">Ver todos</button>' : '') + '</div>';
  hd.appendChild(d);
}
{ const chChatU = chPintaChat;
  chPintaChat = function (abrir) {
    chChatU.apply(this, arguments);
    try {
      const c = CH.chat && CH.chat.conv; if (!c) return;
      chUniBanner();
      const id = c.id; chUniSugConv(id, false).then(() => { if (CH.chat && CH.chat.conv && CH.chat.conv.id === id) chUniBanner(); });
    } catch (e) { }
  };
}
// unir una pareja sugerida (ya viene cuál queda de principal)
async function chUniHacer(prinId, otroId) {
  const s = [...(CHU.lista || []), ...Object.values(CHU.porConv).flatMap(x => x.lista || [])].find(y => y.principal.id === prinId && y.otro.id === otroId);
  const pr = s ? s.principal : { id: prinId }, ot = s ? s.otro : { id: otroId };
  if (!confirm('Se unen en el chat de «' + (pr.canal || '') + '» (#' + pr.id + (pr.msgs != null ? ', ' + chUniMsgs(pr) : '') + ').\n' +
    'El de «' + (ot.canal || '') + '» (#' + ot.id + (ot.msgs != null ? ', ' + chUniMsgs(ot) : '') + ') deja de aparecer en la lista y lo que escriba por ahí cae en el principal.\n' +
    (s && s.aviso ? '⚠️ ' + s.aviso + '\n' : '') + 'Se puede separar después. ¿Unir?')) return;
  const r = await call('wch_unir', { principal: prinId, otro: otroId }); if (!r || !r.ok) return;
  CHU.lista = (CHU.lista || []).filter(y => ![y.principal.id, y.otro.id].includes(otroId)); CHU.porConv = {}; CHU.t = 0;
  cierraModal(); toast(r.msg); Object.keys(CH_CACHE).forEach(k => delete CH_CACHE[k]); CH.conv = prinId; await chRecarga(true); chAbre(prinId); chUniBtn();
}
async function chUniNo(a, b) {
  if (!confirm('¿No son el mismo cliente? Esos dos chats ya no se van a sugerir para unir.')) return;
  const r = await call('wch_unir_descartar', { a, b }); if (!r || !r.ok) return;
  toast(r.msg); CHU.lista = (CHU.lista || []).filter(y => !([y.principal.id, y.otro.id].includes(a) && [y.principal.id, y.otro.id].includes(b)));
  Object.keys(CHU.porConv).forEach(k => { CHU.porConv[k].lista = CHU.porConv[k].lista.filter(y => !([y.principal.id, y.otro.id].includes(a) && [y.principal.id, y.otro.id].includes(b))); });
  chUniBtn(); chUniBanner(); if ($('chUniSL')) chUniSugPinta();
}
// todas las sugerencias
function chUniSugPinta() {
  const el = $('chUniSL'); if (!el) return;
  const l = CHU.lista || [];
  el.innerHTML = l.length ? l.map(s => '<div class="card" style="margin-bottom:8px">' +
      '<div style="font-size:13px"><b>' + esc(s.razon) + '</b>' + (s.detalle ? ' <span class="mut">· ' + esc(s.detalle) + '</span>' : '') + '</div>' +
      '<div style="margin-top:4px">⭐ ' + chUniTxt(s.principal) + ' <span class="mut" style="font-size:12px">' + chUniMsgs(s.principal) + '</span></div>' +
      '<div>➕ ' + chUniTxt(s.otro) + ' <span class="mut" style="font-size:12px">' + chUniMsgs(s.otro) + '</span></div>' +
      '<div class="mut" style="font-size:12px;margin-top:4px">' + esc(s.por_que) + (s.aviso ? ' ⚠️ ' + esc(s.aviso) : '') + '</div>' +
      '<div class="auto" style="margin-top:6px"><button class="p" onclick="chUniHacer(' + s.principal.id + ',' + s.otro.id + ')">🔗 Unir</button><button onclick="chUniNo(' + s.principal.id + ',' + s.otro.id + ')">No es el mismo</button>' +
      '<button onclick="cierraModal();chAbre(' + s.principal.id + ')">Ver chat</button></div></div>').join('')
    : '<div class="mut" style="font-size:13px">No hay chats que parezcan del mismo cliente. 🎉</div>';
}
async function chUniSugModal() {
  modal('<h3 style="margin-top:0">🔗 Chats que parecen del mismo cliente</h3>' +
    '<p class="mut" style="font-size:13px;margin-top:0">Los busca el sistema por <b>mismo teléfono</b>, porque <b>escribió su teléfono</b> en otro chat, o por <b>mismo nombre completo</b> (este último revísalo). ' +
    'Se une en el <b>WhatsApp con más plática</b> (⭐). Nada se une sin que le des «Unir».</p>' +
    '<div id="chUniSL" style="max-height:55vh;overflow:auto"><div class="mut">Buscando…</div></div>' +
    '<div class="acts"><button id="chUniR">↻ Buscar de nuevo</button><button onclick="cierraModal()">Cerrar</button></div>');
  $('chUniR').onclick = async () => { $('chUniSL').innerHTML = '<div class="mut">Buscando…</div>'; await chUniSugCarga(true); chUniSugPinta(); };
  chUniSugPinta(); await chUniSugCarga(false); chUniSugPinta();
}
// «Unir chats» desde un chat: muestra la plática de cada uno, marca los sugeridos y el principal es el WhatsApp con más plática
chUnirModal = async function () {
  const c = CH.chat && CH.chat.conv; if (!c) return;
  const uni = c.unidas || [];
  const pinta = async q => {
    const r = await call('wch_unir_cand', { conv_id: c.id, q: q || '' }, { quiet: true }); if (!r || !r.ok) return;
    CH.uniYo = r.yo_msgs; if ($('chUniYo')) $('chUniYo').textContent = r.yo_msgs;
    $('chUniL').innerHTML = r.lista.length ? r.lista.map(x => '<div class="card" style="margin-bottom:6px;display:flex;gap:8px;align-items:center"><div style="flex:1;min-width:0">' + (x.sugerido ? '💡 ' : '') + '<b>' + esc(x.nombre || chTel(x.telefono)) + '</b> <span class="tag">' + esc(x.canal) + '</span> <span class="tag acc">#' + x.id + '</span>' +
      '<div class="mut" style="font-size:12px">' + chTel(x.telefono) + ' · ' + esc(x.razon) + ' · ' + chUniMsgs(x) + (x.ultimo_texto ? ' · ' + esc(x.ultimo_texto) : '') + '</div></div><button class="p" onclick="chUnirCon(' + x.id + ')">🔗 Unir</button></div>').join('')
      : '<div class="mut" style="font-size:13px">' + (q ? 'Nada con esa búsqueda.' : 'No encontré otro chat con el mismo teléfono o nombre. Búscalo por nombre, teléfono o #número de chat.') + '</div>';
    CH.uniC = r.lista;
  };
  modal('<h3 style="margin-top:0">🔗 Unir chats de un mismo cliente</h3>' +
    '<p class="mut" style="font-size:13px;margin-top:0">Junta los mensajes, notas, etiquetas y pedidos en <b>un solo chat</b>: el de WhatsApp donde tiene <b>más plática</b> (este tiene <span id="chUniYo">…</span> mensajes). Lo que escriba después por el otro canal le llega a ese mismo chat, y le contestas desde ahí. 💡 = lo sugiere el sistema.</p>' +
    (uni.length ? '<div class="card" style="margin-bottom:8px"><b>Ya unidos a este chat</b>' + uni.map(x => '<div style="margin-top:6px;display:flex;gap:8px;align-items:center"><span style="flex:1">' + esc(x.nombre || '') + ' <span class="tag">' + esc(x.canal) + '</span> #' + x.id + '</span><button onclick="chDesunir(' + x.id + ')">✂️ Separar</button></div>').join('') + '</div>' : '') +
    '<input id="chUniQ" placeholder="Buscar por nombre, teléfono o #chat" style="margin-bottom:8px"><div id="chUniL" style="max-height:45vh;overflow:auto"><div class="mut">Buscando…</div></div>' +
    '<div class="acts"><button onclick="cierraModal();chUniSugModal()">💡 Todas las sugerencias</button><button onclick="cierraModal()">Cerrar</button></div>');
  let t; $('chUniQ').oninput = () => { clearTimeout(t); t = setTimeout(() => pinta($('chUniQ').value.trim()), 300); };
  pinta('');
};
chUnirCon = async function (otroId) {
  const c = CH.chat.conv, x = (CH.uniC || []).find(y => y.id === otroId); if (!x) return;
  const yo = { id: c.id, canal: c.canal, nombre: c.nombre, telefono: c.telefono, tipo: c.canal_tipo || 'whatsapp', con: !!c.canal_conectado, msgs: CH.uniYo || 0, ultimo_en: c.ultimo_en };
  const el = { id: x.id, canal: x.canal, nombre: x.nombre, telefono: x.telefono, tipo: x.canal_tipo, con: !!x.conectado, msgs: x.msgs || 0, ultimo_en: x.ultimo_en };
  const wa = z => z.tipo === 'whatsapp';
  if (!wa(yo) && !wa(el)) return toast('Uno de los dos chats tiene que ser de WhatsApp.', true);
  // WhatsApp → más plática → conectado a la web → el más reciente
  let prin;
  if (wa(yo) !== wa(el)) prin = wa(yo) ? yo : el;
  else if (yo.msgs !== el.msgs) prin = yo.msgs > el.msgs ? yo : el;
  else if (yo.con !== el.con) prin = yo.con ? yo : el;
  else prin = new Date(el.ultimo_en || 0) > new Date(yo.ultimo_en || 0) ? el : yo;
  const otro = prin === yo ? el : yo;
  if (!confirm('Se unen los dos chats en el de «' + (prin.canal || '') + '» (#' + prin.id + ', ' + chUniMsgs(prin) + ').\nEl de «' + (otro.canal || '') + '» (#' + otro.id + ', ' + chUniMsgs(otro) + ') deja de aparecer en la lista y lo que escriba por ahí cae en el principal.\n' +
    (!wa(otro) && otro.msgs > prin.msgs ? 'Queda en WhatsApp aunque el otro tenga más mensajes: solo por WhatsApp se le contesta desde aquí.\n' : '') +
    (wa(prin) && !prin.con ? '⚠️ Ese número de WhatsApp no está conectado a la web: desde aquí no le vas a poder contestar.\n' : '') + 'Se puede separar después. ¿Unir?')) return;
  const r = await call('wch_unir', { principal: prin.id, otro: otro.id }); if (!r || !r.ok) return;
  CHU.lista = (CHU.lista || []).filter(y => ![y.principal.id, y.otro.id].includes(otro.id)); CHU.porConv = {}; CHU.t = 0;
  cierraModal(); toast(r.msg); Object.keys(CH_CACHE).forEach(k => delete CH_CACHE[k]); CH.conv = prin.id; await chRecarga(true); chAbre(prin.id); chUniBtn();
};
