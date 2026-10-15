-- Automação do pedido: o dono só aceita, marca "saiu/pronto" ou cancela.

-- 1) A confirmação automática do Mercado Pago identifica quem marcou como pago.
create or replace function public.regras_pagamento() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.pagamento_status = 'pago' and old.pagamento_status is distinct from 'pago' then
    new.pago_em := now();
    new.pago_conferido_por := coalesce(nullif(new.pago_conferido_por, ''), auth.jwt() ->> 'email', '');
  elsif new.pagamento_status <> 'pago' and old.pagamento_status = 'pago' then
    new.pago_em := null; new.pago_conferido_por := null;
  end if;
  if new.status in ('confirmado','pronto','concluido') and new.pagamento in ('Pix','Cartão online')
     and new.pagamento_status <> 'pago' then
    raise exception 'O pagamento ainda não foi confirmado.';
  end if;
  return new;
end $$;

-- 2) Limpeza automática (a cada 10 minutos):
--    - Pix gerado pelo Mercado Pago que expirou (30 min) e não foi pago -> cancela
--    - link de cartão que expirou (2 h) e não foi pago -> cancela
--    - pedido "pronto" há mais de 3 h -> concluído
create or replace function public.limpeza_pedidos() returns void
language sql security definer set search_path = public as $$
  update public.pedidos set status = 'cancelado',
         nota_interna = trim(both E'\n' from coalesce(nota_interna,'') || E'\nCancelado automaticamente: pagamento não confirmado a tempo.')
   where status = 'novo' and pagamento_status = 'aguardando' and not entrega_a_combinar
     and ((pagamento = 'Pix' and mp_id is not null and criado_em < now() - interval '40 minutes')
       or (pagamento = 'Cartão online' and criado_em < now() - interval '130 minutes'));
  update public.pedidos set status = 'concluido'
   where status = 'pronto' and atualizado_em < now() - interval '3 hours';
$$;
revoke execute on function public.limpeza_pedidos() from public, anon, authenticated;

create extension if not exists pg_cron;
select cron.unschedule('limpeza-pedidos') where exists (select 1 from cron.job where jobname = 'limpeza-pedidos');
select cron.schedule('limpeza-pedidos', '*/10 * * * *', 'select public.limpeza_pedidos()');
