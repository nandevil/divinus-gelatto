-- Sundae: categoria própria, R$ 9,00, 1 complemento (amendoim ou confete) e até 2 caldas (as mesmas do açaí).
-- Só mexe em dados (produtos e complementos). Pode rodar mais de uma vez.
update public.produtos set categoria = 'Sundae', preco = 9 where id = 'P010';

insert into public.complementos (nome, grupo, preco, vale, disponivel, ordem)
select v.nome, 'incluso', 0, 'Sundae', true, v.ordem
from (values ('Amendoim', 60), ('Confete', 61)) as v(nome, ordem)
where not exists (select 1 from public.complementos c where c.nome = v.nome and c.vale = 'Sundae');

insert into public.complementos (nome, grupo, preco, vale, disponivel, ordem)
select a.nome, 'calda', 0, 'Sundae', a.disponivel, a.ordem + 30
from public.complementos a
where a.grupo = 'calda' and a.vale = 'Açaí no copo'
  and not exists (select 1 from public.complementos c where c.nome = a.nome and c.grupo = 'calda' and c.vale = 'Sundae');

select id, nome, categoria, preco, online from public.produtos where id = 'P010';
select nome, grupo, vale from public.complementos where vale = 'Sundae' order by ordem;
