-- Sundae com os mesmos complementos e caldas do açaí no copo.
-- Nova coluna produtos.complementos_de: quando preenchida, o pedido confere complementos/caldas/adicionais
-- usando essa categoria em vez da categoria do produto. Pode rodar mais de uma vez.
alter table public.produtos add column if not exists complementos_de text not null default '';
update public.produtos set complementos_de = 'Açaí no copo' where id = 'P010';

do $fn$
declare d text; o text;
begin
  select pg_get_functiondef('public.criar_pedido(jsonb)'::regprocedure) into d;
  if position('v_cat' in d) > 0 then
    raise notice 'criar_pedido já atualizado';
    return;
  end if;
  o := d;
  d := replace(d, $a$  v_ext    text[];$a$, $a$  v_ext    text[];
  v_cat    text;$a$);
  d := replace(d, $a$    v_qtd := least($a$, $a$    v_cat := coalesce(nullif(prod.complementos_de, ''), prod.categoria);
    v_qtd := least($a$);
  d := replace(d, 'lower(prod.categoria)', 'lower(v_cat)');
  if d = o or position('v_cat    text' in d) = 0 or position('v_cat := coalesce' in d) = 0 or position('lower(prod.categoria)' in d) > 0 then
    raise exception 'criar_pedido: trechos não encontrados, nada foi alterado';
  end if;
  execute d;
end $fn$;

select id, nome, categoria, complementos_de, online from public.produtos where id = 'P010';
