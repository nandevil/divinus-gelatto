-- Reconhecimento de cliente que volta (opção A: só o primeiro nome aparece até confirmar com o código de um pedido anterior)
create or replace function public.reconhecer_cliente(p_telefone text) returns json
language sql stable security definer set search_path = public as $$
  select json_build_object('existe', true, 'nome', split_part(btrim(nome), ' ', 1))
  from pedidos
  where length(regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g')) >= 10
    and telefone = regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g')
  order by criado_em desc limit 1;
$$;

create or replace function public.dados_cliente(p_telefone text, p_codigo text) returns json
language sql stable security definer set search_path = public as $$
  select json_build_object('nome', nome, 'modo', modo, 'cep', cep, 'rua', rua, 'numero', numero,
                           'bairro', bairro, 'complemento', complemento)
  from pedidos p
  where length(regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g')) >= 10
    and p.telefone = regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g')
    and exists (select 1 from pedidos x
                where x.telefone = p.telefone and x.codigo = upper(btrim(coalesce(p_codigo, ''))))
  order by (p.rua is not null) desc, p.criado_em desc limit 1;
$$;

revoke execute on function public.reconhecer_cliente(text) from public;
revoke execute on function public.dados_cliente(text, text) from public;
grant execute on function public.reconhecer_cliente(text) to anon, authenticated;
grant execute on function public.dados_cliente(text, text) to anon, authenticated;
