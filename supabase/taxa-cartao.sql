-- Taxa extra no cartão de crédito online (repassa o custo do Mercado Pago ao cliente).
-- Pix e cartão na maquininha NÃO pagam. O servidor recalcula; o navegador não decide valor.
-- Percentual editável no painel: Configurações > "Taxa extra no cartão online (%)".

alter table public.config  add column if not exists taxa_cartao_pct numeric(5,2) not null default 4.5
  check (taxa_cartao_pct >= 0 and taxa_cartao_pct <= 15);
alter table public.pedidos add column if not exists taxa_cartao numeric(10,2) not null default 0;

do $mig$
declare
  d text;
  n text;
begin
  -- criar_pedido: soma a taxa do cartão ao total
  d := pg_get_functiondef('public.criar_pedido(jsonb)'::regprocedure);
  n := replace(d, E'  v_pstat  text;', E'  v_pstat  text;\n  v_tcartao numeric := 0;');
  if n = d then raise exception 'criar_pedido: declare não encontrado'; end if; d := n;
  n := replace(d, E'  v_pstat := case when v_pag', E'  if v_pag = ''Cartão online'' and not v_comb and c.taxa_cartao_pct > 0 then\n    v_tcartao := round((v_sub + v_taxa) * c.taxa_cartao_pct / 100, 2);\n  end if;\n  v_pstat := case when v_pag');
  if n = d then raise exception 'criar_pedido: v_pstat não encontrado'; end if; d := n;
  n := replace(d, 'pagamento_status, pix_copia_cola)', 'pagamento_status, pix_copia_cola, taxa_cartao)');
  if n = d then raise exception 'criar_pedido: colunas não encontradas'; end if; d := n;
  n := replace(d, 'v_itens, v_sub, v_taxa, v_sub + v_taxa, v_comb,', 'v_itens, v_sub, v_taxa, v_sub + v_taxa + v_tcartao, v_comb,');
  if n = d then raise exception 'criar_pedido: total não encontrado'; end if; d := n;
  n := replace(d, 'v_pstat, v_pix);', 'v_pstat, v_pix, v_tcartao);');
  if n = d then raise exception 'criar_pedido: values não encontrado'; end if; d := n;
  execute d;

  -- cardapio: expõe o percentual para o site mostrar
  d := pg_get_functiondef('public.cardapio()'::regprocedure);
  n := regexp_replace(d, 'json_build_object\(', 'json_build_object(''taxa_cartao'', c.taxa_cartao_pct, ');
  if n = d then raise exception 'cardapio: json_build_object não encontrado'; end if;
  execute n;

  -- acompanhar_pedido: devolve a taxa do cartão do pedido
  d := pg_get_functiondef('public.acompanhar_pedido(text,text)'::regprocedure);
  n := regexp_replace(d, 'json_build_object\(', 'json_build_object(''taxa_cartao'', taxa_cartao, ');
  if n = d then raise exception 'acompanhar_pedido: json_build_object não encontrado'; end if;
  execute n;
end
$mig$;
