-- Sessão do robô do WhatsApp (Baileys) rodando no Render. Só o service role acessa.
create table if not exists public.robo_sessao (
  id            text primary key,
  dados         text not null,
  atualizado_em timestamptz not null default now()
);
alter table public.robo_sessao enable row level security; -- sem policies: ninguém além do service role
