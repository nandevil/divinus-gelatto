// Divinus Gelatto — confirmação automática de pagamento (Mercado Pago).
//
// O Mercado Pago avisa esta função quando um pagamento muda de estado (a função
// "pagamento" informa este endereço em cada Pix e em cada link de cartão).
// Não confiamos no aviso: buscamos o pagamento no Mercado Pago com o nosso token e
// só marcamos o pedido como PAGO se o pagamento estiver aprovado, a referência for
// o código de um pedido e o valor cobrir o total do pedido.
//
// Publicar com a verificação de JWT desligada (o Mercado Pago não envia JWT):
//   supabase functions deploy mp-webhook --no-verify-jwt

import { createClient } from "jsr:@supabase/supabase-js@2";

const OK = () => new Response("ok", { status: 200 });

Deno.serve(async (req) => {
  const token = Deno.env.get("MP_ACCESS_TOKEN");
  if (!token) return new Response("sem token", { status: 503 });

  const url = new URL(req.url);
  let id = url.searchParams.get("data.id") || url.searchParams.get("id") || "";
  let tipo = url.searchParams.get("type") || url.searchParams.get("topic") || "";
  if (req.method === "POST") {
    try {
      const corpo = await req.json();
      id = id || String(corpo?.data?.id || corpo?.id || "");
      tipo = corpo?.type || corpo?.topic || tipo;
    } catch { /* corpo vazio */ }
  }
  if (tipo && tipo !== "payment") return OK();
  if (!/^\d{5,20}$/.test(id)) return OK();

  const r = await fetch(`https://api.mercadopago.com/v1/payments/${id}`, {
    headers: { "Authorization": `Bearer ${token}` },
  });
  if (r.status >= 500) return new Response("erro no Mercado Pago", { status: 502 }); // o MP tenta de novo
  if (!r.ok) return OK();
  const pg = await r.json();
  if (pg.status !== "approved") return OK();

  const codigo = String(pg.external_reference || "").toUpperCase();
  if (!/^DG[A-Z0-9]{5}$/.test(codigo)) return OK();

  const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: p } = await sb.from("pedidos")
    .select("id, total, status, pagamento_status, nota_interna").eq("codigo", codigo).maybeSingle();
  if (!p || p.pagamento_status === "pago") return OK();

  const pago = Math.round(Number(pg.transaction_amount) * 100) / 100;
  const total = Math.round(Number(p.total) * 100) / 100;
  const aviso = (txt: string) => (p.nota_interna ? p.nota_interna + "\n" : "") + txt;

  if (pago + 0.005 < total) {
    console.error("Valor pago menor que o pedido", codigo, pago, total);
    await sb.from("pedidos").update({ nota_interna: aviso(`ATENÇÃO: o Mercado Pago aprovou R$ ${pago.toFixed(2)}, menor que o total R$ ${total.toFixed(2)}. Confira antes de aceitar.`) }).eq("id", p.id);
    return OK();
  }

  const campos: Record<string, unknown> = {
    pagamento_status: "pago",
    pago_conferido_por: "Mercado Pago (automático)",
    mp_id: String(pg.id),
  };
  if (p.status === "cancelado") campos.nota_interna = aviso("ATENÇÃO: pagamento aprovado depois do pedido cancelado. Estorne no Mercado Pago.");
  const { error } = await sb.from("pedidos").update(campos).eq("id", p.id);
  if (error) { console.error("Falha ao marcar como pago", codigo, error.message); return new Response("erro", { status: 500 }); }
  return OK();
});
