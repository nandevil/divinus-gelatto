-- Casquinhas e cascões (simples e recheados) voltam a ser vendidos só no trailer.
-- O Sundae continua à venda pelo site. Pode rodar mais de uma vez sem problema.
update produtos set online = false where id in ('P006','P007','P008','P009');
update produtos set online = true  where id = 'P010';
select id, nome, preco, online from produtos where categoria = 'Sorvete' order by id;
