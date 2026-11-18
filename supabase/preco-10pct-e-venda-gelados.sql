-- Reajuste de 10% em tudo (arredondado pra cima em múltiplos de R$ 0,50)
-- e liberação de sorvetes e milkshakes para pedido pelo site (retirada ou entrega).
-- Rode UMA vez só (rodar de novo aumenta outra vez).

update produtos
   set preco = ceil(preco::numeric * 1.10 * 2) / 2
 where preco > 0 and id not like 'EX%';

update complementos
   set preco = ceil(preco::numeric * 1.10 * 2) / 2
 where preco > 0;

update produtos
   set online = true
 where id not like 'EX%';

select id, nome, preco, online from produtos order by id;
select nome, grupo, preco from complementos where preco > 0 order by nome;
