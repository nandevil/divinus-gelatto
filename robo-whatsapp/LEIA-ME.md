# Robô de resposta automática no WhatsApp (teste)

Responde sozinho a quem escreve: cardápio e preços (lidos do mesmo banco do site), horário, entrega, endereço, pagamento e o **link do site**. Sem IA e sem custo. Se o cliente pedir atendente, o robô avisa o dono e fica quieto naquela conversa.

> **Atenção:** usa a conexão do "WhatsApp Web" (biblioteca Baileys), que **não é a API oficial da Meta**. Isso vai contra as regras do WhatsApp e pode levar ao **bloqueio do número**. **Teste em um chip separado**, nunca no número principal do dono.

## O que precisa
- Um computador ligado 24 h (ou um servidor) com **Node.js 20 ou mais novo**.
- Um celular com o WhatsApp (ou WhatsApp Business) do **número de teste**.

## Instalar (uma vez)
1. Copie esta pasta `robo-whatsapp` **e o arquivo `config.js`** do site para uma pasta fora do OneDrive, por exemplo `C:\divinus-robo\`. Coloque o `config.js` dentro de `robo-whatsapp` ou ao lado dela.
2. No terminal, dentro de `robo-whatsapp`:
   ```
   npm install
   ```

## Rodar
```
npm start
```
Aparece um **QR Code**. No celular: WhatsApp > Aparelhos conectados > Conectar um aparelho. Quando aparecer "Robô conectado e respondendo", mande uma mensagem de outro número para testar.

Para receber o aviso de "quero atendente" no WhatsApp do dono (PowerShell):
```
$env:DONO_NUMERO = "5522999999999"; npm start
```

## Como o robô se comporta
- Digitar **1 a 6** ou palavras como "cardápio", "horário", "entrega", "endereço", "pix", "atendente", "pedir".
- Qualquer outra coisa: uma saudação com o menu e o link do site (no máximo uma vez a cada 6 h por pessoa).
- Se o **dono responder pelo celular**, o robô fica quieto naquela conversa por 2 horas (`PAUSA_MINUTOS`).
- Grupos e status são ignorados. Áudio e foto recebem um aviso de que só texto é lido.

## Ajustes (variáveis de ambiente)
| Variável | Para que serve |
|---|---|
| `DONO_NUMERO` | número do dono que recebe o aviso de atendente |
| `SITE_URL` | link do site (padrão: https://divinusgelatto.pages.dev) |
| `ENDERECO` | endereço do trailer |
| `PAUSA_MINUTOS` | quanto tempo o robô se cala após o dono responder (padrão 120) |

## Cuidados
- A pasta `sessao/` guarda o login do WhatsApp. **Não envie para o GitHub** (já está no `.gitignore`) e não compartilhe.
- Se o celular sair da conta ("Aparelhos conectados"), apague `sessao/` e leia o QR de novo.
- Se o computador desligar ou a internet cair, o robô para de responder.
- Taxa de entrega e endereço estão escritos no código (`bot.mjs`); se mudarem no site, ajuste lá também.
