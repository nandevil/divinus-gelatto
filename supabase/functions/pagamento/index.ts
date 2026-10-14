// Divinus Gelatto — pagamentos pelo Mercado Pago (cartão e Pix).
//
// O site chama esta função depois de criar o pedido. Ela confere o pedido no banco,
// cria o pagamento no Mercado Pago com o valor EXATO do pedido e devolve o que o
// cliente precisa:
//   acao = "cartao" -> link do Checkout do Mercado Pago (só cartão de crédito/débito)
//   acao = "pix"    -> código "copia e cola" e QR Code do Pix, com o número do pedido
//
// O dinheiro cai na conta Mercado Pago do dono. A CONFIRMAÇÃO continua manual: o dono
// confere no app do Mercado Pago (identificador = código do pedido) e marca "pago" no painel.
//
// Segredos (Supabase > Edge Functions > Secrets):
//   MP_ACCESS_TOKEN   Access Token de PRODUÇÃO do Mercado Pago (APP_USR-...)
//   SITE_URL          endereço do site, ex.: https://divinusgelatto.com.br (opcional)
// SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY já existem automaticamente.
//
// Publicar com a verificação de JWT desligada (a própria função confere código + telefone):
//   supabase functions deploy pagamento --no-verify-jwt

import { createClient } from "jsr:@supabase/supabase-js@2";

// Só o site da Divinus (e testes locais) pode chamar esta função pelo navegador.
function origensPermitidas(): string[] {
  const site = (Deno.env.get("SITE_URL") || "").replace(/\/+$/, "");
  return [site, "http://localhost:8095", "http://127.0.0.1:8095"].filter(Boolean);
}
let CORS: Record<string, string> = {};
function definirCors(req: Request) {
  const origem = req.headers.get("origin") || "";
  CORS = {
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
  if (origem && origensPermitidas().includes(origem)) CORS["Access-Control-Allow-Origin"] = origem;
}

function resposta(corpo: unknown, status = 200) {
  return new Response(JSON.stringify(corpo), { status, headers: { ...CORS, "Content-Type": "application/json" } });
}

Deno.serve(async (req) => {
  definirCors(req);
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return resposta({ erro: "Método não permitido." }, 405);

  const token = Deno.env.get("MP_ACCESS_TOKEN");
  if (!token) return resposta({ erro: "Pagamento pelo Mercado Pago ainda não configurado." }, 503);

  let acao = "", codigo = "", telefone = "";
  try {
    const bruto = await req.text();
    if (bruto.length > 2000) return resposta({ erro: "Pedido inválido." }, 400);
    const corpo = JSON.parse(bruto);
    acao = String(corpo.acao || "cartao").trim();
    codigo = String(corpo.codigo || "").trim().toUpperCase();
    telefone = String(corpo.telefone || "").replace(/\D/g, "");
  } catch {
    return resposta({ erro: "Pedido inválido." }, 400);
  }
  if (acao !== "cartao" && acao !== "pix") return resposta({ erro: "Ação inválida." }, 400);
  if (!/^DG[A-Z0-9]{5}$/.test(codigo) || telefone.length < 10) return resposta({ erro: "Pedido inválido." }, 400);

  const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: p, error } = await sb.from("pedidos")
    .select("id, codigo, telefone, nome, total, status, pagamento, pagamento_status, entrega_a_combinar, link_pagamento, pix_copia_cola, mp_id, criado_em")
    .eq("codigo", codigo).eq("telefone", telefone).maybeSingle();

  if (error || !p) return resposta({ erro: "Pedido não encontrado." }, 404);
  if (p.status === "cancelado") return resposta({ erro: "Este pedido foi cancelado." }, 400);
  if (p.pagamento_status !== "aguardando") return resposta({ erro: "Este pedido já foi pago." }, 400);
  if (p.entrega_a_combinar) return resposta({ erro: "A taxa de entrega ainda vai ser combinada. Mandamos o valor pelo WhatsApp." }, 400);
  if (Date.now() - new Date(p.criado_em).getTime() > 24 * 60 * 60 * 1000) return resposta({ erro: "Pedido antigo. Faça um novo pedido." }, 400);
  const valor = Math.round(Number(p.total) * 100) / 100;
  if (!(valor > 0)) return resposta({ erro: "Valor inválido." }, 400);

  const cabecalhos = (chave: string) => ({
    "Authorization": `Bearer ${token}`,
    "Content-Type": "application/json",
    "X-Idempotency-Key": chave,
  });

  // ---------------- Cartão: link do Checkout ----------------
  if (acao === "cartao") {
    if (p.pagamento !== "Cartão online") return resposta({ erro: "Este pedido não é com cartão online." }, 400);
    if (p.link_pagamento) return resposta({ url: p.link_pagamento });

    const site = (Deno.env.get("SITE_URL") || "").replace(/\/+$/, "");
    const preferencia: Record<string, unknown> = {
      items: [{ id: p.codigo, title: `Pedido ${p.codigo} - Divinus Gelatto`, quantity: 1, unit_price: valor, currency_id: "BRL" }],
      external_reference: p.codigo,
      statement_descriptor: "DIVINUS GELATTO",
      // Só cartão: o Pix já é pago pelo QR Code, e boleto não serve para pedido de açaí.
      payment_methods: {
        excluded_payment_types: [{ id: "ticket" }, { id: "atm" }, { id: "bank_transfer" }],
        installments: 1,
      },
      expires: true,
      expiration_date_to: new Date(Date.now() + 2 * 60 * 60 * 1000).toISOString().replace("Z", "+00:00"),
    };
    if (site) {
      const volta = `${site}/?pedido=${p.codigo}`;
      preferencia.back_urls = { success: volta, pending: volta, failure: volta };
    }
    const mp = await fetch("https://api.mercadopago.com/checkout/preferences", {
      method: "POST", headers: cabecalhos(`divinus-cartao-${p.codigo}`), body: JSON.stringify(preferencia),
    });
    if (!mp.ok) {
      console.error("Mercado Pago recusou o cartão:", mp.status, await mp.text());
      return resposta({ erro: "Não conseguimos gerar o link agora. Mandamos pelo WhatsApp." }, 502);
    }
    const dados = await mp.json();
    const url = dados.init_point as string;
    await sb.from("pedidos").update({ link_pagamento: url }).eq("id", p.id);
    return resposta({ url });
  }

  // ---------------- Pix: código copia e cola + QR Code ----------------
  if (p.pagamento !== "Pix") return resposta({ erro: "Este pedido não é com Pix." }, 400);
  if (p.mp_id && p.pix_copia_cola) return resposta({ qr_code: p.pix_copia_cola, mp_id: p.mp_id });

  const primeiroNome = String(p.nome || "Cliente").trim().split(/\s+/)[0].slice(0, 40) || "Cliente";
  const pagamento = {
    transaction_amount: valor,
    description: `Pedido ${p.codigo} - Divinus Gelatto`,
    payment_method_id: "pix",
    external_reference: p.codigo,
    date_of_expiration: new Date(Date.now() + 30 * 60 * 1000).toISOString().replace("Z", "+00:00"),
    // O site não pede e-mail do cliente. Endereço de domínio reservado (example.com) nunca recebe mensagem.
    payer: { email: `${p.codigo.toLowerCase()}@example.com`, first_name: primeiroNome },
  };
  const mp = await fetch("https://api.mercadopago.com/v1/payments", {
    method: "POST", headers: cabecalhos(`divinus-pix-${p.codigo}`), body: JSON.stringify(pagamento),
  });
  if (!mp.ok) {
    console.error("Mercado Pago recusou o Pix:", mp.status, await mp.text());
    return resposta({ erro: "Não conseguimos gerar o Pix agora. Mandamos pelo WhatsApp." }, 502);
  }
  const d = await mp.json();
  const qr = d?.point_of_interaction?.transaction_data?.qr_code as string | undefined;
  if (!qr) {
    console.error("Mercado Pago não devolveu o QR Code:", JSON.stringify(d).slice(0, 300));
    return resposta({ erro: "Não conseguimos gerar o Pix agora. Mandamos pelo WhatsApp." }, 502);
  }
  await sb.from("pedidos").update({ pix_copia_cola: qr, mp_id: String(d.id) }).eq("id", p.id);
  return resposta({ qr_code: qr, mp_id: String(d.id) });
});
