-- Pedido do site só com pagamento online (Pix ou cartão pelo Mercado Pago).
-- Remove "Cartão na maquininha" das formas aceitas em criar_pedido.
do $mig$
declare d text; n text;
begin
  d := pg_get_functiondef('public.criar_pedido(jsonb)'::regprocedure);
  n := replace(d, $a$v_pag not in ('Pix', 'Cartão online', 'Cartão na maquininha')$a$, $b$v_pag not in ('Pix', 'Cartão online')$b$);
  if n = d then raise exception 'criar_pedido: regra de pagamento não encontrada'; end if;
  execute n;
end
$mig$;
