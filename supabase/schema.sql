-- =====================================================================
-- Divinus Gelatto — banco de dados (Supabase)
-- Cole tudo no SQL Editor do Supabase e clique em Run. Pode rodar de novo
-- sem perder dados: tabelas e exemplos só são criados se não existirem.
--
-- Segurança:
--  * O site (chave anon) NÃO lê nem grava tabelas. Ele só chama duas funções:
--      cardapio()        -> cardápio público (sem custos)
--      criar_pedido(p)   -> grava o pedido recalculando todos os preços aqui
--      acompanhar_pedido(codigo, telefone) -> status do pedido para o cliente
--  * Pagamento por Pix / cartão online fica 'aguardando' até o dono conferir
--    que o valor caiu e marcar como pago no painel. Sem isso o pedido não avança.
--  * O painel só funciona para e-mails cadastrados na tabela admins.
-- =====================================================================

-- ---------- tabelas ----------
create table if not exists public.admins (
  email text primary key
);

create table if not exists public.config (
  id            int primary key default 1 check (id = 1),
  inclusos      int     not null default 3,
  abre          text    not null default '10:00',
  fecha         text    not null default '19:00',
  dias          text    not null default 'seg a sáb',
  fechado_agora boolean not null default false,
  aviso         text    not null default '',
  whatsapp      text    not null default '5522974035793',
  motoboy_fixo  numeric(10,2),
  custo_km      numeric(10,2),
  acrescimo_km  numeric(6,2),
  taxa_maxima   numeric(10,2),
  pix_tipo      text    not null default '',
  pix_chave     text    not null default '',
  pix_nome      text    not null default 'DIVINUS GELATTO',
  pix_cidade    text    not null default 'ARARUAMA',
  ifood_url     text    not null default '',
  app99_url     text    not null default ''
);

create table if not exists public.produtos (
  id         text primary key,
  nome       text not null,
  categoria  text not null,
  preco      numeric(10,2) not null default 0,
  disponivel boolean not null default true,
  online     boolean not null default false,
  foto       text not null default '',
  ordem      int  not null default 0,
  custo      numeric(10,2)
);

create table if not exists public.complementos (
  id         bigint generated always as identity primary key,
  nome       text not null,
  grupo      text not null default 'opcional' check (grupo in ('incluso','opcional')),
  preco      numeric(10,2) not null default 0,
  vale       text not null default 'Açaí no copo',
  disponivel boolean not null default true,
  ordem      int  not null default 0,
  custo      numeric(10,2)
);

create table if not exists public.bairros (
  id           bigint generated always as identity primary key,
  bairro       text not null unique,
  distancia_km numeric(6,2),
  taxa_fixa    numeric(10,2),
  minutos      int not null default 0,
  minimo       numeric(10,2) not null default 0,
  atende       boolean not null default true,
  ordem        int not null default 0
);

create table if not exists public.pedidos (
  id                 bigint generated always as identity primary key,
  codigo             text not null unique,
  criado_em          timestamptz not null default now(),
  atualizado_em      timestamptz not null default now(),
  status             text not null default 'novo'
                     check (status in ('novo','confirmado','pronto','concluido','cancelado')),
  nome               text not null,
  telefone           text not null,
  modo               text not null check (modo in ('retirada','entrega')),
  pagamento          text not null,
  cep                text,
  rua                text,
  numero             text,
  bairro             text,
  complemento        text,
  obs                text,
  itens              jsonb not null,
  subtotal           numeric(10,2) not null,
  taxa_entrega       numeric(10,2) not null default 0,
  total              numeric(10,2) not null,
  entrega_a_combinar boolean not null default false,
  origem             text,
  fora_horario       boolean not null default false,
  nota_interna       text not null default '',
  pagamento_status   text not null default 'aguardando'
                     check (pagamento_status in ('aguardando','pago','no_trailer')),
  pago_em            timestamptz,
  pago_conferido_por text,
  pix_copia_cola     text,
  link_pagamento     text
);
-- Para bancos criados antes destas colunas existirem:
alter table public.config  add column if not exists pix_tipo   text not null default '';
alter table public.config  add column if not exists pix_chave  text not null default '';
alter table public.config  add column if not exists pix_nome   text not null default 'DIVINUS GELATTO';
alter table public.config  add column if not exists pix_cidade text not null default 'ARARUAMA';
alter table public.config  add column if not exists ifood_url  text not null default '';
alter table public.config  add column if not exists app99_url  text not null default '';
alter table public.pedidos add column if not exists pagamento_status text not null default 'aguardando';
alter table public.pedidos add column if not exists pago_em timestamptz;
alter table public.pedidos add column if not exists pago_conferido_por text;
alter table public.pedidos add column if not exists pix_copia_cola text;
alter table public.pedidos add column if not exists link_pagamento text;
create index if not exists pedidos_criado_em_idx on public.pedidos (criado_em desc);
create index if not exists pedidos_telefone_idx  on public.pedidos (telefone, criado_em desc);

create or replace function public.tocar_atualizado_em() returns trigger
language plpgsql as $$ begin new.atualizado_em := now(); return new; end $$;
drop trigger if exists pedidos_atualizado_em on public.pedidos;
create trigger pedidos_atualizado_em before update on public.pedidos
  for each row execute function public.tocar_atualizado_em();

-- Pix e cartão online só avançam depois que o dono conferir que o valor caiu.
create or replace function public.regras_pagamento() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.pagamento_status = 'pago' and old.pagamento_status is distinct from 'pago' then
    new.pago_em := now();
    new.pago_conferido_por := coalesce(auth.jwt() ->> 'email', '');
  elsif new.pagamento_status <> 'pago' and old.pagamento_status = 'pago' then
    new.pago_em := null; new.pago_conferido_por := null;
  end if;
  if new.status in ('confirmado','pronto','concluido') and new.pagamento in ('Pix','Cartão online')
     and new.pagamento_status <> 'pago' then
    raise exception 'Confira se o pagamento caiu na conta antes de confirmar o pedido.';
  end if;
  return new;
end $$;
drop trigger if exists pedidos_regras_pagamento on public.pedidos;
create trigger pedidos_regras_pagamento before update on public.pedidos
  for each row execute function public.regras_pagamento();

-- ---------- quem é admin ----------
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from admins where lower(email) = lower(coalesce(auth.jwt() ->> 'email', '')));
$$;
create or replace function public.sou_admin() returns boolean
language sql stable security definer set search_path = public as $$ select public.is_admin(); $$;

-- ---------- RLS: tabelas fechadas para o público, abertas só para admin ----------
alter table public.admins       enable row level security;
alter table public.config       enable row level security;
alter table public.produtos     enable row level security;
alter table public.complementos enable row level security;
alter table public.bairros      enable row level security;
alter table public.pedidos      enable row level security;

do $$
declare t text;
begin
  foreach t in array array['config','produtos','complementos','bairros','pedidos'] loop
    execute format('drop policy if exists admin_tudo on public.%I', t);
    execute format('create policy admin_tudo on public.%I for all to authenticated using (public.is_admin()) with check (public.is_admin())', t);
  end loop;
end $$;
-- pedidos não são apagados pelo painel (só cancelados)
revoke delete on public.pedidos from anon, authenticated;

-- ---------- taxa de entrega ----------
-- (motoboy fixo + km × custo por km) × (1 + acréscimo% × km), arredondada a R$ 0,50, com teto opcional.
create or replace function public.taxa_bairro(b public.bairros, c public.config) returns numeric
language sql immutable as $$
  select case
    when b.taxa_fixa is not null then b.taxa_fixa
    when b.distancia_km is null or (coalesce(c.motoboy_fixo,0) = 0 and coalesce(c.custo_km,0) = 0) then null
    else least(
      coalesce(nullif(c.taxa_maxima, 0), 1e9),
      round(((coalesce(c.motoboy_fixo,0) + b.distancia_km * coalesce(c.custo_km,0))
             * (1 + coalesce(c.acrescimo_km,0) / 100 * b.distancia_km)) * 2) / 2)
  end;
$$;

-- ---------- Pix: código "copia e cola" no padrão do Banco Central ----------
create or replace function public.pix_crc16(t text) returns text
language plpgsql immutable as $$
declare b bytea := convert_to(t, 'UTF8'); crc int := 65535; i int; j int;
begin
  for i in 0 .. length(b) - 1 loop
    crc := crc # (get_byte(b, i) << 8);
    for j in 1 .. 8 loop
      if (crc & 32768) <> 0 then crc := ((crc << 1) # 4129) & 65535; else crc := (crc << 1) & 65535; end if;
    end loop;
  end loop;
  return upper(lpad(to_hex(crc), 4, '0'));
end $$;

create or replace function public.pix_campo(id text, v text) returns text
language sql immutable as $$ select id || lpad(length(v)::text, 2, '0') || v $$;

create or replace function public.pix_ascii(t text, tam int) returns text
language sql immutable as $$
  select left(btrim(regexp_replace(translate(upper(coalesce(t, '')),
    'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ', 'AAAAAEEEEIIIIOOOOOUUUUCN'), '[^A-Z0-9 ]', '', 'g')), tam)
$$;

create or replace function public.pix_brcode(chave text, nome text, cidade text, valor numeric, txid text) returns text
language plpgsql immutable as $$
declare corpo text;
begin
  corpo := public.pix_campo('00', '01')
        || public.pix_campo('26', public.pix_campo('00', 'br.gov.bcb.pix') || public.pix_campo('01', chave))
        || public.pix_campo('52', '0000')
        || public.pix_campo('53', '986')
        || case when valor > 0 then public.pix_campo('54', to_char(valor, 'FM9999990.00')) else '' end
        || public.pix_campo('58', 'BR')
        || public.pix_campo('59', coalesce(nullif(public.pix_ascii(nome, 25), ''), 'DIVINUS GELATTO'))
        || public.pix_campo('60', coalesce(nullif(public.pix_ascii(cidade, 15), ''), 'ARARUAMA'))
        || public.pix_campo('62', public.pix_campo('05', coalesce(nullif(regexp_replace(upper(txid), '[^A-Z0-9]', '', 'g'), ''), '***')))
        || '6304';
  return corpo || public.pix_crc16(corpo);
end $$;

-- ---------- cardápio público (o site lê isto) ----------
create or replace function public.cardapio() returns json
language sql stable security definer set search_path = public as $$
  select json_build_object(
    'inclusos', c.inclusos,
    'whatsapp', c.whatsapp,
    'aviso',    c.aviso,
    'pix',      c.pix_chave <> '',
    'apps',     json_build_object('ifood', c.ifood_url, 'app99', c.app99_url),
    'horario',  json_build_object('abre', c.abre, 'fecha', c.fecha, 'dias', c.dias, 'fechado', c.fechado_agora),
    'produtos', coalesce((
      select json_agg(json_build_object('id', p.id, 'nome', p.nome, 'categoria', p.categoria, 'preco', p.preco,
                                        'disponivel', p.disponivel, 'online', p.online, 'foto', p.foto)
                      order by p.ordem, p.nome)
      from produtos p where p.nome !~* '^\s*ex\s*:'), '[]'::json),
    'complementos', coalesce((
      select json_agg(json_build_object('nome', x.nome, 'grupo', x.grupo, 'preco', x.preco, 'vale', x.vale, 'disponivel', x.disponivel)
                      order by x.ordem, x.id)
      from complementos x
      where x.disponivel and x.nome !~* '^\s*ex\s*:' and (x.grupo = 'incluso' or x.preco > 0)), '[]'::json),
    'entrega', coalesce((
      select json_agg(json_build_object('bairro', b.bairro, 'taxa', public.taxa_bairro(b, c), 'minutos', b.minutos, 'minimo', b.minimo)
                      order by b.ordem, b.bairro)
      from bairros b where b.atende and b.bairro !~* '^\s*ex\s*:'), '[]'::json)
  )
  from config c where c.id = 1;
$$;

-- ---------- criar pedido (o site chama isto) ----------
-- Todos os preços são recalculados aqui; o que o navegador manda de valor é ignorado.
create or replace function public.criar_pedido(p jsonb) returns json
language plpgsql security definer set search_path = public as $$
declare
  c        config;
  prod     produtos;
  b        bairros;
  it       jsonb;
  n        text;
  v_inc    text[];
  v_ext    text[];
  v_lim    int;
  v_qtd    int;
  v_preco  numeric;
  v_unit   numeric;
  v_sub    numeric := 0;
  v_taxa   numeric := 0;
  v_itens  jsonb := '[]'::jsonb;
  v_achou  boolean := false;
  v_comb   boolean := false;
  v_fora   boolean;
  v_agora  time;
  v_codigo text;
  v_pstat  text;
  v_pix    text;
  v_nome   text := left(btrim(coalesce(p->>'nome', '')), 80);
  v_tel    text := regexp_replace(coalesce(p->>'telefone', ''), '\D', '', 'g');
  v_modo   text := coalesce(p->>'modo', '');
  v_pag    text := coalesce(p->>'pagamento', '');
  v_bairro text := left(btrim(coalesce(p->>'bairro', '')), 80);
begin
  select * into c from config where id = 1;

  if length(v_nome) < 2 then raise exception 'Informe seu nome.'; end if;
  if length(v_tel) < 10 or length(v_tel) > 13 then raise exception 'Informe um telefone com DDD.'; end if;
  if v_modo not in ('retirada', 'entrega') then raise exception 'Escolha retirada ou entrega.'; end if;
  if v_pag not in ('Pix', 'Cartão online', 'Cartão na maquininha') then raise exception 'Escolha a forma de pagamento.'; end if;
  if v_modo = 'entrega' and v_pag = 'Cartão na maquininha' then raise exception 'Cartão na maquininha só na retirada.'; end if;
  if jsonb_typeof(p->'itens') is distinct from 'array' or jsonb_array_length(p->'itens') = 0 then
    raise exception 'Seu pedido está vazio.';
  end if;
  if jsonb_array_length(p->'itens') > 30 then raise exception 'Pedido grande demais para o site. Chame a gente no WhatsApp.'; end if;

  -- proteção contra abuso
  if (select count(*) from pedidos where telefone = v_tel and criado_em > now() - interval '10 minutes') >= 5 then
    raise exception 'Muitos pedidos seguidos. Chame a gente no WhatsApp.';
  end if;
  if (select count(*) from pedidos where criado_em > now() - interval '1 minute') >= 30 then
    raise exception 'Muitos pedidos agora. Tente de novo em um minuto.';
  end if;

  for it in select * from jsonb_array_elements(p->'itens') loop
    select * into prod from produtos where id = it->>'id';
    if not found or not prod.online or not prod.disponivel or prod.preco <= 0 then
      raise exception 'Um item do pedido não está mais disponível. Atualize a página.';
    end if;

    v_qtd := least(greatest(coalesce(nullif(regexp_replace(coalesce(it->>'qtd', '1'), '\D', '', 'g'), '')::int, 1), 1), 20);
    v_inc := array(select left(jsonb_array_elements_text(coalesce(it->'inclusos', '[]'::jsonb)), 60));
    v_ext := array(select left(jsonb_array_elements_text(coalesce(it->'extras',   '[]'::jsonb)), 60));

    v_lim := least(c.inclusos, (select count(*)::int from complementos x
             where x.grupo = 'incluso' and x.disponivel and (x.vale = '' or lower(x.vale) = lower(prod.categoria))));
    if cardinality(v_inc) > v_lim then raise exception 'Complementos acima do limite.'; end if;

    foreach n in array v_inc loop
      if not exists (select 1 from complementos x where x.nome = n and x.grupo = 'incluso' and x.disponivel
                     and (x.vale = '' or lower(x.vale) = lower(prod.categoria))) then
        raise exception 'O complemento "%" não está disponível. Atualize a página.', n;
      end if;
    end loop;

    v_unit := prod.preco;
    foreach n in array v_ext loop
      select x.preco into v_preco from complementos x
       where x.nome = n and x.grupo = 'opcional' and x.disponivel and x.preco > 0
         and (x.vale = '' or lower(x.vale) = lower(prod.categoria))
       limit 1;
      if not found then raise exception 'O adicional "%" não está disponível. Atualize a página.', n; end if;
      v_unit := v_unit + v_preco;
    end loop;

    v_sub := v_sub + v_unit * v_qtd;
    v_itens := v_itens || jsonb_build_object('id', prod.id, 'nome', prod.nome, 'qtd', v_qtd,
                 'inclusos', to_jsonb(v_inc), 'extras', to_jsonb(v_ext), 'unit', v_unit, 'total', v_unit * v_qtd);
  end loop;

  if v_modo = 'entrega' then
    if btrim(coalesce(p->>'rua', '')) = '' or btrim(coalesce(p->>'numero', '')) = '' or v_bairro = '' then
      raise exception 'Informe rua, número e bairro.';
    end if;
    select * into b from bairros where lower(bairro) = lower(v_bairro) and atende limit 1;
    v_achou := found;
    if v_achou then v_taxa := public.taxa_bairro(b, c); end if;
    if not v_achou or v_taxa is null then
      v_comb := true; v_taxa := 0;
    elsif b.minimo > v_sub then
      raise exception 'Pedido mínimo para %: R$ %', b.bairro, replace(to_char(b.minimo, 'FM9990.00'), '.', ',');
    end if;
  end if;

  v_agora := (now() at time zone 'America/Sao_Paulo')::time;
  v_fora := c.fechado_agora or v_agora < c.abre::time or v_agora >= c.fecha::time
            or coalesce((p->>'fora_horario')::boolean, false);

  loop
    v_codigo := 'DG' || upper(substr(md5(random()::text || clock_timestamp()::text), 1, 5));
    exit when not exists (select 1 from pedidos where codigo = v_codigo);
  end loop;

  v_pstat := case when v_pag = 'Cartão na maquininha' then 'no_trailer' else 'aguardando' end;
  -- Pix com valor exato e o código do pedido como identificador. Com taxa a combinar,
  -- o valor final ainda não existe: o dono manda pelo WhatsApp.
  if v_pag = 'Pix' and c.pix_chave <> '' and not v_comb then
    v_pix := public.pix_brcode(c.pix_chave, c.pix_nome, c.pix_cidade, v_sub + v_taxa, v_codigo);
  end if;

  insert into pedidos (codigo, nome, telefone, modo, pagamento, cep, rua, numero, bairro, complemento, obs,
                       itens, subtotal, taxa_entrega, total, entrega_a_combinar, origem, fora_horario,
                       pagamento_status, pix_copia_cola)
  values (v_codigo, v_nome, v_tel, v_modo, v_pag,
          case when v_modo = 'entrega' then left(p->>'cep', 9) end,
          case when v_modo = 'entrega' then left(btrim(p->>'rua'), 120) end,
          case when v_modo = 'entrega' then left(btrim(p->>'numero'), 20) end,
          case when v_modo = 'entrega' then v_bairro end,
          case when v_modo = 'entrega' then left(btrim(coalesce(p->>'complemento', '')), 160) end,
          left(btrim(coalesce(p->>'obs', '')), 300),
          v_itens, v_sub, v_taxa, v_sub + v_taxa, v_comb,
          left(nullif(btrim(coalesce(p->>'origem', '')), ''), 80), v_fora,
          v_pstat, v_pix);

  return public.acompanhar_pedido(v_codigo, v_tel);
end;
$$;

-- ---------- acompanhar pedido (o cliente vê o status) ----------
-- Precisa do código E do telefone: ninguém consegue espiar pedido dos outros.
create or replace function public.acompanhar_pedido(p_codigo text, p_telefone text) returns json
language sql stable security definer set search_path = public as $$
  select json_build_object(
    'codigo', codigo, 'status', status, 'modo', modo, 'pagamento', pagamento,
    'pagamento_status', pagamento_status, 'subtotal', subtotal, 'taxa', taxa_entrega, 'total', total,
    'a_combinar', entrega_a_combinar, 'fora_horario', fora_horario, 'criado_em', criado_em,
    'pix_copia_cola', case when pagamento_status = 'aguardando' then pix_copia_cola end,
    'link_pagamento', case when pagamento_status = 'aguardando' then link_pagamento end)
  from pedidos
  where codigo = upper(btrim(coalesce(p_codigo, '')))
    and telefone = regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g')
    and criado_em > now() - interval '3 days';
$$;

-- só estas funções ficam abertas ao público
revoke execute on function public.criar_pedido(jsonb) from public;
revoke execute on function public.cardapio() from public;
revoke execute on function public.acompanhar_pedido(text, text) from public;
grant  execute on function public.criar_pedido(jsonb) to anon, authenticated;
grant  execute on function public.cardapio() to anon, authenticated;
grant  execute on function public.acompanhar_pedido(text, text) to anon, authenticated;

-- pedidos novos chegam ao painel na hora (Realtime respeita o RLS: só admin recebe)
do $$
begin
  alter publication supabase_realtime add table public.pedidos;
exception when duplicate_object then null; when undefined_object then null;
end $$;

-- ---------- dados iniciais (só entram se as tabelas estiverem vazias) ----------
insert into public.config (id, ifood_url) values (1, 'https://www.ifood.com.br/delivery/araruama-rj/divinus-gelatto-pc-bandeira/688cd4e2-0d70-45f7-a6c2-83bc451b5a56') on conflict (id) do nothing;
update public.config set ifood_url = 'https://www.ifood.com.br/delivery/araruama-rj/divinus-gelatto-pc-bandeira/688cd4e2-0d70-45f7-a6c2-83bc451b5a56' where id = 1 and ifood_url = '';

insert into public.produtos (id, nome, categoria, preco, online, ordem)
select * from (values
  ('P001','Açaí no copo 400 ml','Açaí no copo',15,true,1),
  ('P002','Açaí no copo 500 ml','Açaí no copo',17,true,2),
  ('P003','Açaí no copo 700 ml','Açaí no copo',22,true,3),
  ('P004','Açaí no copo 1 L','Açaí no copo',28,true,4),
  ('P005','Açaí na garrafa 500 ml','Açaí na garrafa',15,true,5),
  ('P006','Casquinha (baunilha, açaí ou mista)','Sorvete',3.5,false,10),
  ('P007','Cascão (baunilha, açaí ou mista)','Sorvete',6,false,11),
  ('P008','Casquinha recheada','Sorvete',6,false,12),
  ('P009','Cascão recheado','Sorvete',8,false,13),
  ('P010','Sundae','Sorvete',7,false,14),
  ('P011','Milkshake 400 ml','Milkshake',14,false,20),
  ('P012','Milkshake 500 ml','Milkshake',15,false,21),
  ('P013','Milkshake 700 ml','Milkshake',18,false,22),
  ('P014','Milkshake com polpa 400 ml','Milkshake com polpa',12,false,30),
  ('P015','Milkshake com polpa 500 ml','Milkshake com polpa',13,false,31),
  ('P016','Milkshake com polpa 700 ml','Milkshake com polpa',16,false,32)
) v where not exists (select 1 from public.produtos);

-- Cremes opcionais entram com preço 0: só aparecem no site depois que o preço for preenchido no painel.
insert into public.complementos (nome, grupo, preco, vale, ordem)
select * from (values
  ('Ovomaltine granulado','incluso',0,'Açaí no copo',1),
  ('Farofa de amendoim','incluso',0,'Açaí no copo',2),
  ('Delicado','incluso',0,'Açaí no copo',3),
  ('M&M','incluso',0,'Açaí no copo',4),
  ('Jujuba','incluso',0,'Açaí no copo',5),
  ('Amendoim granulado','incluso',0,'Açaí no copo',6),
  ('Granola','incluso',0,'Açaí no copo',7),
  ('Leite em pó','incluso',0,'Açaí no copo',8),
  ('Ovomaltine','opcional',0,'Açaí no copo',20),
  ('Paçoquinha','opcional',0,'Açaí no copo',21),
  ('Prestígio','opcional',0,'Açaí no copo',22),
  ('Galak com Negresco','opcional',0,'Açaí no copo',23),
  ('Ninho','opcional',0,'Açaí no copo',24),
  ('KitKat','opcional',0,'Açaí no copo',25),
  ('Nutella','opcional',0,'Açaí no copo',26),
  ('Ovomaltine (garrafa)','opcional',1.5,'Açaí na garrafa',30)
) v(nome, grupo, preco, vale, ordem) where not exists (select 1 from public.complementos);

insert into public.bairros (bairro, minutos, ordem)
select * from (values ('Parque Mataruna',15,1), ('Centro',25,2)) v(bairro, minutos, ordem)
where not exists (select 1 from public.bairros);

-- ---------- financeiro: compras de insumos e embalagens ----------
create table if not exists public.despesas (
  id bigint generated always as identity primary key,
  data date not null default ((now() at time zone 'America/Sao_Paulo')::date),
  fornecedor text not null default '',
  cnpj text not null default '',
  documento text not null default '',
  descricao text not null,
  quantidade numeric(12,3) not null default 1,
  unidade text not null default '',
  valor_unitario numeric(10,2),
  valor_total numeric(10,2) not null,
  categoria text not null default 'Insumo' check (categoria in ('Insumo','Utensílio/Embalagem','Desconto','Entrega/Motoboy','Outros')),
  forma_pagamento text not null default '',
  obs text not null default '',
  criado_em timestamptz not null default now()
);
create index if not exists despesas_data_idx on public.despesas (data desc);
alter table public.despesas enable row level security;
drop policy if exists admin_tudo on public.despesas;
create policy admin_tudo on public.despesas for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- =====================================================================
-- ÚLTIMO PASSO (troque pelo e-mail que vai entrar no painel e rode):
--   insert into public.admins (email) values ('seu-email@exemplo.com');
-- =====================================================================

-- =====================================================================
-- ATUALIZAÇÕES POSTERIORES (já aplicadas no banco ao vivo; rode em banco novo)
-- =====================================================================
alter table public.pedidos add column if not exists mp_id text;
alter table public.config  add column if not exists mp_ativo boolean not null default false;

create table if not exists public.vendas_plataforma (
  id bigint generated always as identity primary key,
  plataforma text not null,            -- 'iFood' ou '99Food'
  periodo_inicio date not null,
  periodo_fim date not null,
  pedidos int not null default 0,
  bruto numeric(10,2) not null default 0,
  comissao numeric(10,2) not null default 0,
  taxa_pagamento numeric(10,2) not null default 0,
  logistica numeric(10,2) not null default 0,
  mensalidade numeric(10,2) not null default 0,
  promocoes numeric(10,2) not null default 0,
  anuncios numeric(10,2) not null default 0,
  estornos numeric(10,2) not null default 0,
  antecipacao numeric(10,2) not null default 0,
  ajustes numeric(10,2) not null default 0,
  repasse_recebido numeric(10,2),
  repasse_data date,
  obs text,
  criado_em timestamptz not null default now()
);
alter table public.vendas_plataforma enable row level security;
drop policy if exists admin_all on public.vendas_plataforma;
create policy admin_all on public.vendas_plataforma for all to authenticated using (public.is_admin()) with check (public.is_admin());
-- cardapio() também devolve 'mp' (config.mp_ativo) — a versão atual está no banco ao vivo.
-- Conferir os nomes exatos das colunas de vendas_plataforma no banco antes de reaproveitar.

-- Taxa extra no cartão online: aplicada pelo script supabase/taxa-cartao.sql
-- (config.taxa_cartao_pct, pedidos.taxa_cartao; criar_pedido/cardapio/acompanhar_pedido atualizados).
