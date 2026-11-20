-- Entrega por distância (motoboy próprio): R$ 8,00 até 5 km do trailer, R$ 10,00 acima, até 8 km.
-- O site manda a localização do endereço (lat/lng) e a distância de carro (km); o servidor confere:
-- usa o maior valor entre o km enviado e a distância em linha reta calculada aqui, e cobra pela regra.
-- Pode rodar mais de uma vez.

alter table public.config add column if not exists trailer_lat        double precision default -22.8650806;
alter table public.config add column if not exists trailer_lng        double precision default -42.3436897;
alter table public.config add column if not exists entrega_km_base    numeric(6,2)     default 5;
alter table public.config add column if not exists entrega_taxa_base  numeric(10,2)    default 8;
alter table public.config add column if not exists entrega_taxa_extra numeric(10,2)    default 10;
alter table public.config add column if not exists entrega_km_max     numeric(6,2)     default 8;

create or replace function public.km_entrega(p jsonb, c public.config) returns numeric
language plpgsql immutable set search_path = public as $$
declare
  v_lat double precision; v_lng double precision; v_kc numeric; v_reta double precision;
begin
  begin
    v_lat := nullif(p->>'lat', '')::double precision;
    v_lng := nullif(p->>'lng', '')::double precision;
    v_kc  := nullif(p->>'km', '')::numeric;
  exception when others then return null;
  end;
  if v_lat is null or v_lng is null or c.trailer_lat is null or c.trailer_lng is null then return null; end if;
  if v_lat not between -90 and 90 or v_lng not between -180 and 180 then return null; end if;
  v_reta := 2 * 6371 * asin(sqrt(
              power(sin(radians(v_lat - c.trailer_lat) / 2), 2)
            + cos(radians(c.trailer_lat)) * cos(radians(v_lat)) * power(sin(radians(v_lng - c.trailer_lng) / 2), 2)));
  return round(greatest(coalesce(v_kc, 0), v_reta::numeric), 2);
end $$;

-- A taxa agora é pela distância; a lista de bairros continua só para o cliente escolher o bairro.
update public.bairros set taxa_fixa = null;

do $fn$
declare d text; o text;
begin
  select pg_get_functiondef('public.criar_pedido(jsonb)'::regprocedure) into d;
  if position('km_entrega' in d) = 0 then
    o := d;
    d := regexp_replace(d, 'v_taxa(\s+)numeric := 0;', $r$v_taxa\1numeric := 0;
  v_km     numeric;$r$);
    d := regexp_replace(d,
      'select \* into b from bairros where lower\(bairro\) = lower\(v_bairro\) and atende limit 1;\s*v_achou := found;\s*if v_achou then v_taxa := public\.taxa_bairro\(b, c\); end if;',
      $r$v_km := public.km_entrega(p, c);
    if v_km is not null then
      v_achou := v_km <= coalesce(c.entrega_km_max, 8);
      v_taxa := case when not v_achou then null
                     when v_km <= coalesce(c.entrega_km_base, 5) then coalesce(c.entrega_taxa_base, 8)
                     else coalesce(c.entrega_taxa_extra, 10) end;
    else
      select * into b from bairros where lower(bairro) = lower(v_bairro) and atende limit 1;
      v_achou := found;
      if v_achou then v_taxa := public.taxa_bairro(b, c); end if;
    end if;$r$);
    if d = o or position('v_km     numeric' in d) = 0 or position('public.km_entrega(p, c)' in d) = 0 then
      raise exception 'criar_pedido: trechos não encontrados, nada foi alterado';
    end if;
    execute d;
  end if;

  select pg_get_functiondef('public.cardapio()'::regprocedure) into d;
  if position('frete_km' in d) = 0 then
    o := d;
    d := regexp_replace(d, $r$'inclusos',(\s*)c\.inclusos,$r$,
      $r$'inclusos',\1c.inclusos, 'frete_km', json_build_object('lat', c.trailer_lat, 'lng', c.trailer_lng, 'km_base', c.entrega_km_base, 'taxa_base', c.entrega_taxa_base, 'taxa_extra', c.entrega_taxa_extra, 'km_max', c.entrega_km_max),$r$);
    if d = o then raise exception 'cardapio: trecho não encontrado, nada foi alterado'; end if;
    execute d;
  end if;
end $fn$;

select (cardapio()::jsonb)->'frete_km' as regra,
       position('km_entrega' in pg_get_functiondef('public.criar_pedido(jsonb)'::regprocedure)) > 0 as pedido_ok,
       public.km_entrega('{"lat":-22.8678,"lng":-42.3375,"km":1}'::jsonb, (select c from public.config c where id = 1)) as teste_km;

-- 20/11/2026: o limite da entrega própria passou de 15 km para 8 km (R$ 10,00 de 5 a 8 km).
update public.config set entrega_km_max = 8 where id = 1;
