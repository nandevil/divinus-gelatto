// Robô de resposta automática do Divinus Gelatto para WhatsApp.
// Só regras simples (sem IA, sem custo). Lê o cardápio do mesmo banco do site.
// Roda num servidor grátis (Render): a sessão do WhatsApp fica guardada no Supabase
// (tabela robo_sessao), então o robô volta sozinho depois de reiniciar.
// AVISO: usa a conexão "WhatsApp Web" (Baileys), que NÃO é a API oficial da Meta.
// Existe risco de bloqueio do número. O robô só responde quem escreveu primeiro.
import * as baileys from '@whiskeysockets/baileys';
import QRCode from 'qrcode';
import pino from 'pino';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const lib = baileys.makeWASocket ? baileys : (baileys.default || baileys);
const makeWASocket = typeof lib.makeWASocket === 'function' ? lib.makeWASocket : lib.default;
const { DisconnectReason, fetchLatestBaileysVersion, initAuthCreds, BufferJSON, proto } = lib;

const AQUI = path.dirname(fileURLToPath(import.meta.url));

// ---------- configuração (variáveis de ambiente) ----------
function lerConfigSite() {
  const f = [path.join(AQUI, 'config.js'), path.join(AQUI, '..', 'config.js')].find((x) => fs.existsSync(x));
  const txt = f ? fs.readFileSync(f, 'utf8') : '';
  const pega = (k) => (txt.match(new RegExp(k + "\\s*:\\s*'([^']*)'")) || [])[1] || '';
  return { url: pega('SUPABASE_URL'), key: pega('SUPABASE_ANON_KEY') };
}
const site = lerConfigSite();
const SUPABASE_URL = process.env.SUPABASE_URL || site.url;
// Chave service_role (secreta): só no painel do servidor, nunca no código.
const SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY || '';
const PUBLIC_KEY = process.env.SUPABASE_KEY || site.key;
const SITE_URL = process.env.SITE_URL || 'https://divinusgelatto.pages.dev';
const DONO = (process.env.DONO_NUMERO || '').replace(/\D/g, '');
const PAUSA_MIN = Number(process.env.PAUSA_MINUTOS || 120);
const ENDERECO = process.env.ENDERECO || 'Rua Professor Oscar Clark, 1377, em frente ao Mercado Esperança, Araruama/RJ';
const QR_TOKEN = process.env.QR_TOKEN || '';
const PORTA = Number(process.env.PORT || 10000);

const log = pino({ level: process.env.LOG || 'warn' });

// ---------- sessão guardada no Supabase ----------
const REST = SUPABASE_URL + '/rest/v1/robo_sessao';
const H = { apikey: SERVICE_KEY, Authorization: 'Bearer ' + SERVICE_KEY, 'Content-Type': 'application/json' };

async function lerSessao(id) {
  const r = await fetch(`${REST}?id=eq.${encodeURIComponent(id)}&select=dados`, { headers: H });
  if (!r.ok) throw new Error('Supabase leitura ' + r.status + ' ' + (await r.text()));
  const j = await r.json();
  return j[0] ? JSON.parse(j[0].dados, BufferJSON.reviver) : null;
}
async function lerVarias(ids) {
  if (!ids.length) return {};
  const lista = ids.map((i) => '"' + i.replace(/"/g, '\\"') + '"').join(',');
  const r = await fetch(`${REST}?id=in.(${encodeURIComponent(lista)})&select=id,dados`, { headers: H });
  if (!r.ok) throw new Error('Supabase leitura ' + r.status + ' ' + (await r.text()));
  const out = {};
  for (const l of await r.json()) out[l.id] = JSON.parse(l.dados, BufferJSON.reviver);
  return out;
}
async function gravar(linhas) {
  if (!linhas.length) return;
  const r = await fetch(REST, {
    method: 'POST',
    headers: { ...H, Prefer: 'resolution=merge-duplicates,return=minimal' },
    body: JSON.stringify(linhas.map(([id, v]) => ({ id, dados: JSON.stringify(v, BufferJSON.replacer), atualizado_em: new Date().toISOString() }))),
  });
  if (!r.ok) throw new Error('Supabase gravação ' + r.status + ' ' + (await r.text()));
}
async function apagar(ids) {
  if (!ids.length) return;
  const lista = ids.map((i) => '"' + i.replace(/"/g, '\\"') + '"').join(',');
  const r = await fetch(`${REST}?id=in.(${encodeURIComponent(lista)})`, { method: 'DELETE', headers: H });
  if (!r.ok) throw new Error('Supabase exclusão ' + r.status + ' ' + (await r.text()));
}
async function apagarTudo() {
  const r = await fetch(`${REST}?id=neq.__nada__`, { method: 'DELETE', headers: H });
  if (!r.ok) throw new Error('Supabase limpeza ' + r.status);
}

async function sessaoSupabase() {
  const creds = (await lerSessao('creds')) || initAuthCreds();
  return {
    state: {
      creds,
      keys: {
        get: async (type, ids) => {
          const achados = await lerVarias(ids.map((id) => `${type}-${id}`));
          const data = {};
          for (const id of ids) {
            let v = achados[`${type}-${id}`] ?? null;
            if (type === 'app-state-sync-key' && v) v = proto.Message.AppStateSyncKeyData.fromObject(v);
            data[id] = v;
          }
          return data;
        },
        set: async (data) => {
          const salvar = [];
          const remover = [];
          for (const cat in data) {
            for (const id in data[cat]) {
              const v = data[cat][id];
              if (v) salvar.push([`${cat}-${id}`, v]);
              else remover.push(`${cat}-${id}`);
            }
          }
          await gravar(salvar);
          await apagar(remover);
        },
      },
    },
    saveCreds: () => gravar([['creds', creds]]),
  };
}

// ---------- cardápio (cache de 5 min) ----------
let cache = { t: 0, d: null };
async function cardapio() {
  if (cache.d && Date.now() - cache.t < 5 * 60 * 1000) return cache.d;
  try {
    const k = PUBLIC_KEY || SERVICE_KEY;
    const r = await fetch(SUPABASE_URL + '/rest/v1/rpc/cardapio', {
      method: 'POST',
      headers: { apikey: k, Authorization: 'Bearer ' + k, 'Content-Type': 'application/json' },
      body: '{}',
    });
    if (!r.ok) throw new Error('HTTP ' + r.status);
    cache = { t: Date.now(), d: await r.json() };
  } catch (e) {
    console.error('Não consegui ler o cardápio:', e.message);
  }
  return cache.d;
}

const brl = (v) => 'R$ ' + Number(v).toFixed(2).replace('.', ',');
const norm = (s) => String(s || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');

function agoraBR() {
  return new Intl.DateTimeFormat('pt-BR', { timeZone: 'America/Sao_Paulo', hour: '2-digit', minute: '2-digit', hour12: false }).format(new Date());
}
function aberto(h) {
  if (!h || h.fechado) return false;
  const a = agoraBR();
  return a >= String(h.abre).slice(0, 5) && a < String(h.fecha).slice(0, 5);
}

// ---------- respostas ----------
const MENU = 'Digite:\n*1* Cardápio e preços\n*2* Horário\n*3* Entrega\n*4* Endereço\n*5* Pagamento\n*6* Falar com atendente';

async function respCardapio() {
  const d = await cardapio();
  if (!d) return `Veja o cardápio e faça seu pedido aqui: ${SITE_URL}`;
  const itens = (d.produtos || []).filter((p) => p.online && p.disponivel);
  const linhas = itens.map((p) => `• ${p.nome}: ${brl(p.preco)}`);
  return `*Nosso açaí:*\n${linhas.join('\n')}\n\nOs complementos inclusos e as caldas você escolhe na hora de montar.\nMonte e peça pelo site: ${SITE_URL}`;
}
async function respHorario() {
  const d = await cardapio();
  const h = d && d.horario;
  if (!h) return `Atendemos das 10h às 19h. Peça pelo site: ${SITE_URL}`;
  const faixa = `${String(h.abre).slice(0, 5)} às ${String(h.fecha).slice(0, 5)} (${h.dias})`;
  const situ = aberto(h) ? 'Estamos *abertos agora*.' : 'No momento estamos *fechados*.';
  return `${situ}\nHorário: ${faixa}.\nPedidos pelo site: ${SITE_URL}`;
}
const respEntrega = () =>
  `A entrega é feita pelo nosso motoboy.\nTaxa: R$ 8,00 até 5 km do trailer e R$ 10,00 acima de 5 km (até 15 km). No site a taxa é calculada pelo seu endereço. Mais longe que isso, combinamos por aqui.\nRetirada no trailer é grátis.\nVocê pode pedir pelo site: ${SITE_URL}\nOu pelo *iFood* ou pela *99Food*, é só procurar por Divinus Gelatto.`;
const respEndereco = () => `Estamos na ${ENDERECO}.`;
const respPagamento = () =>
  `No site você paga com *Pix* ou *cartão de crédito* (o cartão tem um pequeno acréscimo da taxa). A confirmação é automática.\nPeça aqui: ${SITE_URL}`;
const respPedir = () => `Para pedir, monte seu açaí pelo site: ${SITE_URL}\nÉ rápido e você acompanha o pedido por lá.`;

const ultimaSaudacao = new Map(); // conversa -> ms
const pausadoAte = new Map(); // conversa -> ms
const pausar = (ids) => ids.forEach((j) => j && pausadoAte.set(j, Date.now() + PAUSA_MIN * 60 * 1000));

async function chamarAtendente(ids, numero, aviso, motivo) {
  await aviso(`${motivo}: ${numero ? 'wa.me/' + numero : ids[0]}`);
  pausar(ids);
}

async function decidir(texto, ids, numero, aviso) {
  const t = norm(texto).trim();
  if (!t) return null;
  // quem oferece trabalho (ex.: "vi que vcs estão precisando de motoboy") não recebe resposta automática
  if (/(precis|procurand|vaga|emprego|curriculo|contrat)[a-z ]*(motoboy|entregador|funcionari|atendente|ajudante)|(motoboy|entregador)[a-z ]*(vaga|disponivel|para trabalhar)|quero trabalhar|trabalhar (pra|para|com) (vcs|voces|voce)/.test(t)) return null;
  if (/(mais|acima) de 5 ?km/.test(t)) {
    await chamarAtendente(ids, numero, aviso, 'Cliente quer entrega acima de 5 km');
    return 'Recebido! Para mais de 5 km a gente combina o valor da entrega por aqui. O atendente já foi avisado e responde em seguida. 🙂';
  }
  if (/^1$|card[a-z]*pio|preco|valor|quanto|sabor|menu|tamanho/.test(t)) return respCardapio();
  if (/^2$|horario|abre|fecha|aberto|hora/.test(t)) return respHorario();
  if (/^3$|entrega|frete|taxa|delivery/.test(t)) return respEntrega();
  if (/^4$|endereco|onde|local|chegar|rua/.test(t)) return respEndereco();
  if (/^5$|pagamento|pix|cartao|pagar|dinheiro/.test(t)) return respPagamento();
  if (/^6$|atendente|humano|pessoa|dono|falar com|ligar/.test(t)) {
    await chamarAtendente(ids, numero, aviso, 'Cliente pediu atendente');
    return 'Certo! Avisei o atendente, ele responde por aqui assim que puder. Enquanto isso, você já pode pedir pelo site: ' + SITE_URL;
  }
  if (/pedir|pedido|quero|comprar|link|site/.test(t)) return respPedir();
  // saudação / não entendi: no máximo uma vez a cada 6 h por conversa
  const ult = ultimaSaudacao.get(ids[0]) || 0;
  if (Date.now() - ult < 6 * 60 * 60 * 1000) return null;
  ultimaSaudacao.set(ids[0], Date.now());
  return `Olá! Aqui é o *Divinus Gelatto* 🍇\nFaça seu pedido pelo site: ${SITE_URL}\n\n${MENU}`;
}

// ---------- página de status / QR ----------
let status = 'iniciando';
let qrAtual = null;

http
  .createServer(async (req, res) => {
    const u = new URL(req.url, 'http://x');
    if (u.pathname === '/qr') {
      if (!QR_TOKEN || u.searchParams.get('k') !== QR_TOKEN) {
        res.writeHead(403).end('proibido');
        return;
      }
      let corpo = `<p>Status: <b>${status}</b></p>`;
      if (qrAtual) {
        const img = await QRCode.toDataURL(qrAtual, { width: 320, margin: 2 });
        corpo += `<p>No celular: WhatsApp Business &gt; ⋮ &gt; Aparelhos conectados &gt; Conectar um aparelho. Leia o código:</p><img src="${img}" alt="QR">`;
      } else if (status === 'conectado') {
        corpo += '<p>✅ Robô conectado e respondendo.</p>';
      } else {
        corpo += '<p>Aguardando o código... a página atualiza sozinha.</p>';
      }
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
      res.end(`<!doctype html><meta name="viewport" content="width=device-width"><meta http-equiv="refresh" content="15"><title>Robô Divinus</title><body style="font-family:sans-serif;text-align:center;padding:20px">${corpo}</body>`);
      return;
    }
    res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('ok ' + status);
  })
  .listen(PORTA, () => console.log('Servidor na porta', PORTA));

// ---------- conexão ----------
let sockAtual = null;

async function iniciar() {
  const { state, saveCreds } = await sessaoSupabase();
  const { version } = await fetchLatestBaileysVersion();
  const sock = makeWASocket({ version, auth: state, logger: log, browser: ['Divinus Gelatto', 'Chrome', '1.0'], markOnlineOnConnect: false });
  sockAtual = sock;

  const avisarDono = async (msg) => {
    if (!DONO) { console.log('[aviso ao dono, DONO_NUMERO não definido]', msg); return; }
    try { await sock.sendMessage(DONO + '@s.whatsapp.net', { text: msg }); } catch (e) { console.error('Falha ao avisar o dono:', e.message); }
  };

  sock.ev.on('creds.update', () => saveCreds().catch((e) => console.error('Falha ao salvar sessão:', e.message)));
  sock.ev.on('connection.update', async ({ connection, lastDisconnect, qr }) => {
    if (qr) { qrAtual = qr; status = 'aguardando leitura do QR'; console.log('QR novo disponível em /qr'); }
    if (connection === 'open') { qrAtual = null; status = 'conectado'; console.log('Robô conectado e respondendo.'); }
    if (connection === 'close') {
      if (sockAtual !== sock) return;
      const code = lastDisconnect?.error?.output?.statusCode;
      status = 'desconectado (' + code + ')';
      if (code === DisconnectReason.loggedOut) {
        console.log('Sessão encerrada no celular. Limpando e gerando QR novo.');
        try { await apagarTudo(); } catch (e) { console.error(e.message); }
      }
      const espera = code === DisconnectReason.restartRequired ? 500 : 5000;
      console.log('Conexão caiu (' + code + '). Reconectando...');
      setTimeout(() => iniciar().catch((e) => console.error('Erro ao reconectar:', e.message)), espera);
    }
  });

  sock.ev.on('messages.upsert', async ({ messages, type }) => {
    if (type !== 'notify') return;
    for (const m of messages) {
      try {
        const jid = m.key.remoteJid;
        if (!jid || !m.message) continue;
        if (jid.endsWith('@g.us') || jid.endsWith('@broadcast') || jid.endsWith('@newsletter')) continue;
        const ids = [jid, m.key.remoteJidAlt].filter(Boolean);
        if (m.key.fromMe) { pausar(ids); continue; } // o dono respondeu pelo celular: o robô dá espaço
        if (ids.some((j) => (pausadoAte.get(j) || 0) > Date.now())) continue;
        const pn = ids.find((j) => j.endsWith('@s.whatsapp.net'));
        const numero = pn ? pn.split('@')[0] : '';
        const texto = m.message.conversation || m.message.extendedTextMessage?.text || m.message.buttonsResponseMessage?.selectedDisplayText || '';
        let resp;
        if (!texto) resp = `Oi! Por aqui só consigo ler texto. Para pedir, use o site: ${SITE_URL}`; // áudio, foto, etc.
        else resp = await decidir(texto, ids, numero, avisarDono);
        if (!resp) continue;
        await sock.sendPresenceUpdate('composing', jid).catch(() => {});
        await new Promise((r) => setTimeout(r, 1200 + Math.random() * 1800));
        await sock.sendMessage(jid, { text: resp }, { quoted: m });
        await sock.sendPresenceUpdate('paused', jid).catch(() => {});
      } catch (e) {
        console.error('Erro ao responder:', e.message);
      }
    }
  });
}

if (!SUPABASE_URL || !SERVICE_KEY) {
  console.error('Faltam SUPABASE_URL e SUPABASE_SERVICE_KEY nas variáveis de ambiente.');
  status = 'faltam variáveis de ambiente';
} else {
  iniciar().catch((e) => { console.error('Erro ao iniciar:', e.message); status = 'erro: ' + e.message; });
}
