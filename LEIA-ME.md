# Divinus Gelatto: site de pedidos + painel

```
divinus-gelatto/
├── index.html           site do cliente (monta o açaí e finaliza o pedido)
├── painel.html          painel de controle (pedidos ao vivo, cardápio, entrega, configurações)
├── config.js            chaves do Supabase e do Analytics (vale para o site e o painel)
├── supabase/schema.sql  banco de dados: cole uma vez no Supabase
├── supabase/functions/pagamento/index.ts     cartão (link) e Pix (QR Code) pelo Mercado Pago
├── img/logo.jpg         logo (ícone da aba e prévia de link)
└── serve.ps1            servidor local só para testes no computador
```

**Sem o `config.js` preenchido:**
- o site abre em **modo prévia**: o pedido de teste mostra a confirmação, mas não é salvo;
- o painel abre em **modo demonstração**: pedidos de exemplo e o botão "Simular pedido".

---

## Como funciona

1. **Cardápio:** o cliente monta o açaí e toca em "Adicionar ao pedido". Ele cai direto no **carrinho** (`#finalizar`).
   **Carrinho:** mostra os itens e dois botões, **"+ Adicionar mais um açaí"** (volta ao cardápio já no passo de escolher o tamanho) e **"Finalizar pedido"** (desce para nome, WhatsApp, entrega e pagamento). O botão voltar do celular e o link "Voltar ao cardápio" também levam de volta sem perder nada. Quem volta ao cardápio com itens no carrinho vê a faixa fixa **Ver carrinho**.
2. O pedido vai direto para o banco. O banco **recalcula todos os preços** (ninguém consegue mudar o valor pelo navegador) e devolve o número do pedido, por exemplo `DG7K2QX`.
3. Na tela "Pedido recebido!", o cliente paga:
   - **Pix:** QR Code e "copia e cola" com o **valor exato** e o código do pedido como identificador. O dinheiro cai **direto na conta do dono**.
   - **Cartão de crédito:** botão "Pagar com cartão" abre o Mercado Pago com o valor exato. O dinheiro cai na conta Mercado Pago do dono.
   - **Maquininha:** paga na retirada, no trailer.
4. No painel, o pedido aparece **na hora** (com som) e fica como **"aguardando pagamento"**.
5. O dono confere no app do banco (ou do Mercado Pago) se o valor caiu e toca em **"Conferi: o valor caiu"**. O painel mostra valor, código e cliente para conferir.
   **O banco não deixa confirmar um pedido de Pix ou cartão sem esse passo.** Fica registrado quem conferiu e quando.
6. A tela do cliente **atualiza sozinha**: "Aguardando pagamento" → "Pagamento confirmado! Pedido em preparo" → "Pronto para retirar" ou "Saiu para entrega". Se ele fechar a tela, uma faixa roxa no topo do site continua mostrando o status.
7. O dono segue com **Pronto (ou Saiu para entrega) → Retirado (ou Entregue)**. O botão verde **WhatsApp** abre a conversa com a mensagem certa para cada etapa (inclusive a chave Pix, quando o QR não foi gerado).

> **Taxa a combinar:** quando o bairro não tem taxa definida, o QR e o link não são gerados, porque o valor final ainda não existe. O dono combina a taxa e manda o valor pelo WhatsApp.

---

> **Estado atual (14/10/2026):** o projeto Supabase da Divinus já existe (`bwefsaqlkntahljpgkpi`, organização "Divinus Gelatto"), o `schema.sql` foi aplicado, o cadastro público está desligado e o `config.js` já aponta para ele. **Falta só criar o login do painel** (passos 3 e 4 abaixo).

## 1. Criar o banco (Supabase, plano grátis)

1. Crie uma conta em supabase.com e um projeto novo (por exemplo `divinus`), região **South America (São Paulo)**.
2. Abra **SQL Editor**, cole todo o `supabase/schema.sql` e clique em **Run**. O cardápio já entra preenchido.
3. Em **Authentication > Users > Add user**, crie o login do painel (e-mail e senha) com **Auto Confirm User** marcado.
4. No **SQL Editor**, libere esse e-mail para o painel:
   ```sql
   insert into public.admins (email) values ('email-do-dono@exemplo.com');
   ```
   Repita para cada pessoa que pode usar o painel (por exemplo, o dono e a Ananda).
5. Em **Authentication > Sign In / Providers**, desligue **Allow new users to sign up**. Assim ninguém cria conta sozinho.
6. Em **Project Settings > API**, copie a **Project URL** e a chave **anon public** e cole no `config.js`.
   **Nunca** use a chave `service_role` no site.

Para conferir, abra o site: a faixa roxa de "prévia" some. Faça um pedido de teste e veja ele chegar no painel.

**Acesso escondido ao painel:** na tela do site, toque **3 vezes seguidas no logo** do cabeçalho (em até 3 segundos). O painel abre e pede o login normal. Dentro do painel, o botão "Ver site" volta para o cardápio.

## 2. O que preencher no painel (aba por aba)

| Aba | O quê |
|---|---|
| **Cardápio** | Preço dos cremes opcionais (com preço 0, o creme não aparece no site), fotos (link), produtos disponíveis/esgotados |
| **Entrega** | Bairros, distância em km, tempo, pedido mínimo. Taxa fixa opcional: sem ela, a taxa é calculada pela fórmula |
| **Financeiro** | Compras de insumos e embalagens (uma linha por item, agrupadas por nota), total por categoria e o resultado do mês (vendas recebidas menos compras). A planilha `financeiro/compras-2026-10.csv` tem as 3 primeiras notas |
| **Configurações** | **Chave Pix** (tipo, chave, nome e cidade como no banco); **links do iFood e do 99Food**; custo do motoboy, custo por km, acréscimo e teto da taxa; horário; WhatsApp; "Fechado agora"; aviso no topo do site |

**Botões do iFood e do 99Food:**
- **iFood:** já está ligado à loja real (ID `688cd4e2-0d70-45f7-a6c2-83bc451b5a56`).
- **99Food:** falta o link. A 99 só mostra esse link no **app 99Store** (celular): **Loja > Compartilhar loja > Copiar link**. Cole em Configurações > Link do 99Food.

No celular, o link abre direto no app; sem o app instalado, abre o site da plataforma. Botão sem link não aparece no site.

## 2b. Cartão de crédito (Mercado Pago)

Sem este passo, o cartão online continua funcionando "pelo WhatsApp": o site avisa que o link vai pelo WhatsApp, e o dono manda um link do app do Mercado Pago.

1. No Mercado Pago do dono: **Seu negócio > Configurações > Credenciais** (ou mercadopago.com.br/developers > Suas integrações > criar aplicação "Divinus site"). Copie o **Access Token de produção** (`APP_USR-...`).
2. No Supabase: **Edge Functions > Secrets** e crie:
   - `MP_ACCESS_TOKEN` = o token acima
   - `SITE_URL` = endereço do site publicado (ex.: `https://divinusgelatto.com.br`)
3. Em **Edge Functions > Deploy a new function > Via Editor**, use o nome `pagamento`, cole o `supabase/functions/pagamento/index.ts` e publique. Nos detalhes da função, **desligue "Enforce JWT verification"** (a função confere código + telefone do pedido).
4. Faça um pedido teste com cartão. O link abre com o valor exato, e o pagamento aparece no app do Mercado Pago com o código do pedido.

O token fica só no servidor do Supabase, nunca no site.

- O site pega as mudanças em até 2 minutos.
- Os **custos** (coluna Custo) nunca aparecem no site.

## 3. Usando o painel no dia a dia

- Deixe o painel aberto no celular ou no computador do trailer e toque em **🔔 Ativar som** uma vez. Pedido novo toca um alerta, aparece no topo da fila e o número aparece no título da aba.
- A bolinha verde **ao vivo** mostra que os pedidos estão chegando sozinhos. Mesmo sem ela, a lista se atualiza a cada minuto.
- **Em aberto** mostra a fila, do mais antigo para o mais novo. Use **Concluídos**, **Cancelados** e o período (hoje, 7 e 30 dias) para consultar.
- Os números do topo (pedidos, faturado, ticket médio) são de hoje e ignoram os cancelados.
- **Nota interna:** um campo em cada pedido que só aparece no painel (exemplo: "pagou Pix às 14h").
- **Pagamento:** filtro **Aguardando pagamento** mostra quem ainda não pagou. **Recebido hoje** soma só o que foi conferido (e maquininha de pedido já retirado).

## 4. Publicar (grátis)

Suba a pasta inteira (`index.html`, `painel.html`, `config.js`, `img/`) no **Cloudflare Pages** ou no **Netlify Drop**.
- Site: `https://seusite/`
- Painel: `https://seusite/painel.html` (não aparece no Google e só entra quem está na tabela `admins`)

Depois de publicar, troque `og:image` (e o `image` do bloco `ld+json`) no `index.html` pelo endereço completo, por exemplo `https://seusite/img/logo.jpg`.

## 5. Fotos do topo (trailer + 3 produtos)

Salve na pasta `img/` com estes nomes exatos:

| Arquivo | Onde aparece | Dica |
|---|---|---|
| `trailer.jpg` | Foto principal, grande, logo abaixo do cabeçalho | Deitada, com pelo menos 1600 px de largura |
| `produto1.jpg`, `produto2.jpg`, `produto3.jpg` | Fileira de 3 fotos embaixo da principal | Quadradas ou deitadas, com pelo menos 800 px. O produto no centro da foto |

- As fotos são cortadas pelo centro para caber no espaço.
- Tocar em qualquer foto amplia a imagem.
- Foto que não existir: na prévia aparece o espaço tracejado; no site publicado o espaço some e as outras se ajustam.
- Para usar link em vez de arquivo, ou para trocar a descrição (lida por leitores de tela e pelo Google), edite `FOTO_TRAILER` e `FOTOS_PRODUTOS` no começo do `index.html`.

## 6. Medição (Google Analytics 4)

Cole o ID `G-...` no `config.js`. Eventos enviados:

| Evento | Quando |
|---|---|
| `ver_cardapio` | O cliente rolou até "Monte seu açaí" |
| `escolher_tamanho` | Escolheu um tamanho |
| `ver_carrinho` | Abriu a tela de finalizar |
| `adicionar_item` | Adicionou ao pedido (com valor) |
| `enviar_pedido` | Pedido registrado (valor, modo, pagamento, origem) |
| `copiar_pix` / `abrir_pagamento_cartao` | Cliente foi pagar |
| `pagamento_confirmado` | A tela do cliente viu o pagamento ser confirmado |
| `clique_app` | Clicou em "Pedir no iFood" ou "Pedir no 99Food" |
| `erro_pedido` | O pedido não foi registrado |
| `clique_whatsapp` | Clicou em algum WhatsApp |
| `erro_cardapio` | O banco não respondeu |

Marque `enviar_pedido` como **evento principal (conversão)**.

## 7. Links por origem (UTM)

A origem aparece em cada pedido no painel e no Analytics:

```
https://SEUSITE/?utm_source=instagram&utm_campaign=bio
https://SEUSITE/?utm_source=google&utm_campaign=perfil
https://SEUSITE/?utm_source=whatsapp&utm_campaign=status
https://SEUSITE/?utm_source=qrcode&utm_campaign=trailer
```

## 8. Segurança

- O site só consegue **ler o cardápio** e **criar pedido**, pelas funções `cardapio()` e `criar_pedido()`. As tabelas ficam fechadas para quem não está logado.
- O banco confere tudo: item existe e está à venda, limite de complementos, adicional com preço, pedido mínimo, maquininha só na retirada. Ele também trava excesso de pedidos (5 por telefone a cada 10 minutos).
- O painel exige login, e o e-mail precisa estar na tabela `admins`.
- **Pagamento só é confirmado à mão:** Pix e cartão online não avançam sem o dono marcar "o valor caiu". Nada é confirmado automaticamente.
- A chave Pix fica no banco e só é mostrada ao cliente **depois** que ele faz um pedido, dentro do QR Code daquele pedido. Ela não aparece solta no site.
- O cliente só acompanha o pedido com **código + telefone**, e só por 3 dias.
- O token do Mercado Pago fica só no servidor do Supabase. Nenhuma senha ou dado de cartão passa pelo site.

## 9. Checklist antes de divulgar

- [ ] `schema.sql` rodado, login criado, e-mail na tabela `admins`, cadastro público desligado
- [ ] `config.js` preenchido e a faixa roxa de prévia sumiu
- [ ] Preços dos cremes e bairros preenchidos no painel
- [ ] Chave Pix preenchida em Configurações e um **Pix de verdade de R$ 0,50** pago pelo QR caindo na conta certa (crie um produto de teste de R$ 0,50 e depois apague)
- [ ] Cartão: função `pagamento` publicada, secret `MP_ACCESS_TOKEN` criado, toggle "Usar o Mercado Pago" ligado no painel, Pix e cartão com o valor certo
- [ ] Pedido teste de retirada e outro de entrega chegando no painel, com som, e a tela do cliente mudando sozinha depois de "Conferi: o valor caiu"
- [ ] Links do iFood e do 99Food colados em Configurações
- [ ] `GA_ID` preenchido e evento `enviar_pedido` visto em Tempo real no GA4
- [ ] `og:image` com endereço completo (teste colando o link no WhatsApp)
- [ ] Link do site no Perfil da Empresa no Google e na bio do Instagram (com UTM)

## Publicação (Cloudflare Pages)
- Endereço: https://divinusgelatto.pages.dev
- Para atualizar: Cloudflare > Workers & Pages > divinusgelatto > Create deployment > enviar um .zip com `index.html`, `painel.html`, `config.js` e `img/` (nunca `financeiro/` nem `supabase/`).
- Supabase: secrets `MP_ACCESS_TOKEN` e `SITE_URL` já criados; função `pagamento` sem verificação de JWT.
- Taxa extra do cartão online: Painel > Configurações (hoje 4,98%, igual à taxa à vista do Mercado Pago).

## Automação do pagamento (Mercado Pago)
- Só existe pagamento online: **Pix** e **cartão de crédito** (a maquininha foi removida; o banco recusa outras formas).
- Função `mp-webhook` (Supabase, sem verificação de JWT): o Mercado Pago avisa quando o pagamento é aprovado; a função confere o pagamento na API do MP (usa `MP_ACCESS_TOKEN`), compara o valor e marca o pedido como **pago** sozinha.
- O dono só faz: **Aceitar pedido** → **Saiu para entrega / Pronto** → ou **Cancelar**. O botão "Conferi: o valor caiu (manual)" só é plano B.
- Pedido cancelado que já estava pago ganha a nota "Estorne no Mercado Pago".
- `supabase/automacao.sql`: trigger que impede confirmar pedido online sem pagamento + `limpeza_pedidos()` rodando a cada 10 min (pg_cron) para apagar pedidos abandonados e não pagos. Pedidos pagos nunca são apagados.
- Ordem dos SQLs aplicados depois do `schema.sql`: `taxa-cartao.sql`, `so-online.sql`, `automacao.sql`, `cliente.sql`.

## Clientes
- `supabase/cliente.sql`: o site reconhece telefone que já pediu e mostra só o primeiro nome; nome/endereço completos só aparecem com o **código de um pedido anterior** do mesmo telefone.
- Painel > aba **Clientes**: histórico por telefone (pedidos, total gasto, último pedido, endereço) e exportação CSV. Os dados dos pedidos ficam guardados no banco por tempo indeterminado e não afetam o Financeiro.

## Cardápio de delivery (estado em 15/10/2026)
- **Só açaí vai por delivery** (copo 400/500/700 ml e 1 L; garrafa 500 ml). Sorvetes e milkshakes: só no trailer (`online=false`).
- **Entrega:** taxa fixa de R$ 7,00 até 5 km; o cliente confirma "moro a até 5 km" no pedido. Acima disso, combinar pelo WhatsApp.
- **Complementos do copo:** 9 grátis (até 3), **8 caldas grátis (até 2, grupo `calda`)** e 7 cremes pagos de R$ 2,50. Fotos em `img/complementos/`, `img/cremes/` e `img/caldas/`.
- **Caldas:** `supabase/caldas.sql` (grupo `calda` + validação em `criar_pedido` + leitura em `cardapio()`). No painel, em Complementos, o campo Grupo aceita `calda`.
- **Cliente que volta:** `supabase/cliente.sql` (nome + código de pedido anterior) e aba Clientes no painel.
- Ordem dos SQLs depois do `schema.sql`: `taxa-cartao`, `so-online`, `automacao`, `cliente`, `caldas`.

