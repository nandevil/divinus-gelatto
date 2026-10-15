# Divinus Gelatto: site de pedidos + painel de controle

Site de pedidos online do trailer **Divinus Gelatto** (açaí e gelados, Araruama/RJ), com painel do dono, pagamento por Pix e cartão (Mercado Pago) e confirmação automática.

- **Site:** https://divinusgelatto.pages.dev
- **Painel do dono:** https://divinusgelatto.pages.dev/painel
- **Hospedagem:** Cloudflare Pages (envio de .zip) · **Banco e funções:** Supabase · **Pagamento:** Mercado Pago

> Este repositório é **público**. Nunca coloque aqui chaves secretas (`service_role`, `MP_ACCESS_TOKEN`), senhas, e-mails de contas, dados de clientes, custos, margens ou contratos. O `config.js` leva apenas a chave pública (publishable). Documentos financeiros e de contrato ficam só no computador do dono (pasta `documentos/` local, fora do Git).

## Estrutura

```
divinus-gelatto/
├── index.html              site do cliente (monta o açaí, finaliza e acompanha o pedido)
├── painel.html             painel do dono (pedidos ao vivo, cardápio, entrega, clientes, financeiro, configurações)
├── config.js               URL do Supabase, chave pública e Google Analytics
├── _headers                cabeçalhos de segurança (CSP etc.) do Cloudflare Pages
├── img/                    fotos do site (trailer, produtos, complementos, cremes, caldas)
│   └── plataformas/        fotos quadradas para iFood e 99Food (não vão no site)
├── supabase/
│   ├── schema.sql          tabelas, regras (RLS) e funções do banco
│   ├── taxa-cartao.sql     acréscimo do cartão online
│   ├── so-online.sql       só Pix e cartão online
│   ├── automacao.sql       trigger de pagamento + limpeza automática de pedidos
│   ├── cliente.sql         cliente que volta (nome + código do pedido)
│   ├── caldas.sql          caldas grátis (até 2 por copo)
│   └── functions/
│       ├── pagamento/      gera Pix (QR Code) e link de cartão no Mercado Pago
│       └── mp-webhook/     recebe o aviso do Mercado Pago e marca o pedido como pago
├── documentos/             PDFs públicos de operação e explicação (os financeiros ficam fora do Git)
├── financeiro/             planilhas e notas lançadas
├── LEIA-ME.md              passo a passo de instalação e operação
└── serve.ps1               servidor local só para testes
```

## Como funciona (resumo)

1. O cliente monta o pedido no site e escolhe **Pix** ou **cartão** (o cartão leva um acréscimo igual à taxa).
2. O banco **recalcula todos os preços** no servidor; o navegador não decide valores.
3. O Mercado Pago avisa o `mp-webhook`, que confere o pagamento e marca o pedido como **pago** sozinho.
4. O painel toca um alerta, e o dono só **aceita**, marca **saiu para entrega/pronto** ou **cancela**.

## Instalação / atualização

1. **Banco:** rode `supabase/schema.sql` e depois, em ordem, `taxa-cartao.sql`, `so-online.sql`, `automacao.sql`, `cliente.sql` e `caldas.sql` no SQL Editor do Supabase.
2. **Funções:** publique `pagamento` e `mp-webhook` (JWT desligado) e crie os secrets `MP_ACCESS_TOKEN` e `SITE_URL`.
3. **Config:** preencha `config.js` com a URL e a chave **publishable** do Supabase.
4. **Site:** envie um `.zip` com `index.html`, `painel.html`, `config.js`, `_headers` e `img/` (sem `supabase/`, `financeiro/`, `documentos/` e `img/plataformas/`) em Cloudflare > Workers & Pages > divinusgelatto > Create deployment.

Detalhes e checklist em [LEIA-ME.md](LEIA-ME.md).

## Documentos

| Arquivo | Para quem | Conteúdo |
|---|---|---|
| `documentos/01-Responsabilidades-do-Dono.pdf` | dono | rotina semanal, mensal e anual (site, Mercado Pago, iFood, 99Food) |
| `documentos/02-Guia-do-Site-para-o-Dono.pdf` | dono | explicação simples do site e do painel |

## Segurança e privacidade (LGPD)

- Dados do cliente (nome, telefone, endereço) ficam no Supabase com acesso só para o dono (RLS); nada disso está neste repositório.
- O site mostra só o primeiro nome do cliente que volta; os dados completos exigem o código de um pedido anterior.
- Chaves secretas ficam só nos *secrets* do Supabase, nunca no código.

## Pendências conhecidas

- Plataformas: manter o cardápio igual ao do site (detalhes em documento interno, fora do Git).
- Pix real de teste e chave Pix do dono no painel.
- Ping diário para o Supabase Free não pausar por inatividade.
