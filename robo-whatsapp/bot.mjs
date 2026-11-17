// Robô de resposta automática do Divinus Gelatto para WhatsApp.
// Só regras simples (sem IA, sem custo). Lê o cardápio do mesmo banco do site.
// AVISO: usa a conexão "WhatsApp Web" (Baileys), que NÃO é a API oficial da Meta.
// Pode levar ao bloqueio do número. Teste primeiro em um chip separado.
import * as baileys from '@whiskeysockets/baileys';
import qrcode from 'qrcode-terminal';
import pino from 'pino';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const lib = baileys.makeWASocket ? baileys : (baileys.default || baileys);
const makeWASocket = typeof lib.default === 'function' ? lib.default : (lib.makeWASocket || baileys.default);
const { useMultiFileAuthState, DisconnectReason, fetchLatestBaileysVersion } = lib.useMultiFileAuthState ? lib : (baileys.default || baileys);

const AQUI = path.dirname(fileURLToPath(import.meta.url));

// ---------- configuração ----------
// URL e chave pública do Supabase vêm do config.js do site (a chave publishable é pública).
function lerConfigSite() {
  const f = [path.join(AQUI, 'config.js'), path.join(AQUI, '..', 'config.js')].find((x) => fs.existsSync(x));
  const txt = f ? fs.readFileSync(f, 'utf8') : '';
  const pega = (k) => (txt.match(new RegExp(k + "\\s*:\\s*'([^']*)'")) || [])[1] || '';
  return { url: pega('SUPABASE_URL'), key: pega('SUPABASE_ANON_KEY') };
}
const site = lerConfigSite();
const SUPABASE_URL = process.env.SUPABASE_URL || site.url;
const SUPABASE_KEY = process.env.SUPABASE_KEY || site.key;
const SITE_URL = process.env.SITE_URL || 'https://divinusgelatto.pages.dev';
// Número do dono (55 + DDD + número, só dígitos) para receber o aviso "cliente quer atendente".
const DONO = (process.env.DONO_NUMERO || '').replace(/\D/g, '');
// Se o dono responder pelo celular, o robô fica quieto naquela conversa por este tempo.
const PAUSA_MIN = Number(process.env.PAUSA_MINUTOS || 120);
const ENDERECO = process.env.ENDERECO || 'Rua Professor Oscar Clark, 1377, em frente ao Mercado Esperança, Araruama/RJ';
const PASTA_SESSAO = process.env.PASTA_SESSAO || path.join(AQUI, 'sessao');

const log = pino({ level: process.env.LOG || 'warn' });

// ---------- cardápio (cache de 5 min) ----------
let cache = { t: 0, d: null };
async function cardapio() {
  if (cache.d && Date.now() - cache.t < 5 * 60 * 1000) return cache.d;
  try {
    const r = await fetch(SUPABASE_URL + '/rest/v1/rpc/cardapio', {
      method: 'POST',
      headers: { apikey: SUPABASE_KEY, Authorization: 'Bearer ' + SUPABASE_KEY, 'Content-Type': 'application/json' },
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
  const p = new Intl.DateTimeFormat('pt-BR', { timeZone: 'America/Sao_Paulo', hour: '2-digit', minute: '2-digit', hour12: false }).format(new Date());
  return p; // "14:05"
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
  const inc = (d.complementos || []).filter((c) => c.grupo === 'incluso').length;
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
  `A entrega é feita pelo motoboy parceiro do iFood e da 99Food.\nTaxa: R$ 7,00 até 5 km do trailer. Acima disso, combinamos o valor por aqui.\nRetirada no trailer é grátis.\nPeça pelo site: ${SITE_URL}`;
const respEndereco = () => `Estamos na ${ENDERECO}.`;
const respPagamento = () =>
  `No site você paga com *Pix* ou *cartão de crédito* (o cartão tem um pequeno acréscimo da taxa). A confirmação é automática.\nPeça aqui: ${SITE_URL}`;
const respPedir = () => `Para pedir, monte seu açaí pelo site: ${SITE_URL}\nÉ rápido e você acompanha o pedido por lá.`;

const ultimaSaudacao = new Map(); // jid -> ms
const pausadoAte = new Map(); // jid -> ms

async function decidir(texto, jid, aviso) {
  const t = norm(texto).trim();
  if (!t) return null;
  if (/^1$|card[a-z]*pio|preco|valor|quanto|sabor|menu|tamanho/.test(t)) return respCardapio();
  if (/^2$|horario|abre|fecha|aberto|hora/.test(t)) return respHorario();
  if (/^3$|entrega|frete|taxa|motoboy|delivery/.test(t)) return respEntrega();
  if (/^4$|endereco|onde|local|chegar|rua/.test(t)) return respEndereco();
  if (/^5$|pagamento|pix|cartao|pagar|dinheiro/.test(t)) return respPagamento();
  if (/^6$|atendente|humano|pessoa|dono|falar com|ligar/.test(t)) {
    await aviso('Cliente pediu atendente: wa.me/' + jid.split('@')[0]);
    pausadoAte.set(jid, Date.now() + PAUSA_MIN * 60 * 1000);
    return 'Certo! Avisei o atendente, ele responde por aqui assim que puder. Enquanto isso, você já pode pedir pelo site: ' + SITE_URL;
  }
  if (/pedir|pedido|quero|comprar|link|site/.test(t)) return respPedir();
  // saudação / não entendi: no máximo uma vez a cada 6 h por conversa
  const ult = ultimaSaudacao.get(jid) || 0;
  if (Date.now() - ult < 6 * 60 * 60 * 1000) return null;
  ultimaSaudacao.set(jid, Date.now());
  return `Olá! Aqui é o *Divinus Gelatto* 🍇\nFaça seu pedido pelo site: ${SITE_URL}\n\n${MENU}`;
}

// ---------- conexão ----------
async function iniciar() {
  const { state, saveCreds } = await useMultiFileAuthState(PASTA_SESSAO);
  const { version } = await fetchLatestBaileysVersion();
  const sock = makeWASocket({ version, auth: state, logger: log, browser: ['Divinus Gelatto', 'Chrome', '1.0'], markOnlineOnConnect: false });

  const avisarDono = async (msg) => {
    if (!DONO) { console.log('[aviso ao dono, DONO_NUMERO não definido]', msg); return; }
    try { await sock.sendMessage(DONO + '@s.whatsapp.net', { text: msg }); } catch (e) { console.error('Falha ao avisar o dono:', e.message); }
  };

  sock.ev.on('creds.update', saveCreds);
  sock.ev.on('connection.update', ({ connection, lastDisconnect, qr }) => {
    if (qr) { console.log('\nLeia este QR Code no WhatsApp: Aparelhos conectados > Conectar um aparelho\n'); qrcode.generate(qr, { small: true }); }
    if (connection === 'open') console.log('Robô conectado e respondendo.');
    if (connection === 'close') {
      const code = lastDisconnect?.error?.output?.statusCode;
      if (code === DisconnectReason.loggedOut) {
        console.log('Sessão encerrada no celular. Apague a pasta "sessao" e rode de novo para ler outro QR.');
        process.exit(1);
      }
      console.log('Conexão caiu (' + code + '). Reconectando em 5 s...');
      setTimeout(iniciar, 5000);
    }
  });

  sock.ev.on('messages.upsert', async ({ messages, type }) => {
    if (type !== 'notify') return;
    for (const m of messages) {
      try {
        const jid = m.key.remoteJid;
        if (!jid || !m.message) continue;
        if (jid.endsWith('@g.us') || jid === 'status@broadcast' || jid.endsWith('@broadcast') || jid.endsWith('@newsletter')) continue;
        if (m.key.fromMe) { // o dono respondeu pelo celular: o robô dá espaço
          pausadoAte.set(jid, Date.now() + PAUSA_MIN * 60 * 1000);
          continue;
        }
        if ((pausadoAte.get(jid) || 0) > Date.now()) continue;
        const texto = m.message.conversation || m.message.extendedTextMessage?.text || m.message.buttonsResponseMessage?.selectedDisplayText || '';
        let resp;
        if (!texto) resp = `Oi! Por aqui só consigo ler texto. Para pedir, use o site: ${SITE_URL}`; // áudio, foto, etc.
        else resp = await decidir(texto, jid, avisarDono);
        if (!resp) continue;
        await sock.presenceSubscribe(jid);
        await sock.sendPresenceUpdate('composing', jid);
        await new Promise((r) => setTimeout(r, 1200 + Math.random() * 1800));
        await sock.sendMessage(jid, { text: resp }, { quoted: m });
        await sock.sendPresenceUpdate('paused', jid);
      } catch (e) {
        console.error('Erro ao responder:', e.message);
      }
    }
  });
}

if (!SUPABASE_URL || !SUPABASE_KEY) console.warn('Aviso: sem URL/chave do Supabase. O robô responderá sem preços (só o link do site).');
iniciar();
