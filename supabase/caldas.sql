-- Caldas grátis (até 2 por copo): novo grupo 'calda' em complementos + validação em criar_pedido e leitura em cardapio()
alter table public.complementos drop constraint if exists complementos_grupo_check;
alter table public.complementos add constraint complementos_grupo_check check (grupo in ('incluso','opcional','calda'));

insert into public.complementos (nome, grupo, preco, vale, disponivel, ordem)
select v.nome, 'calda', 0, 'Açaí no copo', true, v.ordem
from (values ('Calda de Morango',40),('Calda de Chocolate',41),('Calda de Banana caramelizada',42),('Calda de Leite condensado',43),
             ('Calda de Uva',44),('Calda de Caramelo',45),('Calda de Tutti-frutti',46),('Calda de Algodão doce',47)) as v(nome, ordem)
where not exists (select 1 from public.complementos c where c.nome = v.nome);

do $fn$
declare d text; o text;
begin
  select pg_get_functiondef('public.criar_pedido(jsonb)'::regprocedure) into d;
  o := d;
  d := replace(d, $a$  v_ext    text[];$a$, $a$  v_ext    text[];
  v_cal    text[];$a$);
  d := replace(d, $a$    v_lim := least(c.inclusos,$a$, $a$    v_cal := array(select left(jsonb_array_elements_text(coalesce(it->'caldas', '[]'::jsonb)), 60));
    if cardinality(v_cal) > 2 then raise exception 'Caldas acima do limite.'; end if;
    foreach n in array v_cal loop
      if not exists (select 1 from complementos x where x.nome = n and x.grupo = 'calda' and x.disponivel
                     and (x.vale = '' or lower(x.vale) = lower(prod.categoria))) then
        raise exception 'A calda "%" não está disponível. Atualize a página.', n;
      end if;
    end loop;

    v_lim := least(c.inclusos,$a$);
  d := replace(d, $a$'inclusos', to_jsonb(v_inc), 'extras', to_jsonb(v_ext),$a$, $a$'inclusos', to_jsonb(v_inc), 'caldas', to_jsonb(v_cal), 'extras', to_jsonb(v_ext),$a$);
  if d = o or position('v_cal :=' in d) = 0 or position($a$'caldas', to_jsonb(v_cal)$a$ in d) = 0 or position('v_cal    text' in d) = 0 then
    raise exception 'criar_pedido: trechos não encontrados, nada foi alterado';
  end if;
  execute d;

  select pg_get_functiondef('public.cardapio()'::regprocedure) into d;
  o := d;
  d := replace(d, $a$(x.grupo = 'incluso' or x.preco > 0)$a$, $a$(x.grupo in ('incluso','calda') or x.preco > 0)$a$);
  if d = o then raise exception 'cardapio: trecho não encontrado, nada foi alterado'; end if;
  execute d;
end $fn$;
