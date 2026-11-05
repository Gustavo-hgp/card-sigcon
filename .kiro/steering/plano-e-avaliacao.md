---
inclusion: manual
---

# Avaliação por critério, plano de teste e decisao.json

## Avaliação por critério (`out/<pasta>/avaliacao.md`)

Uma linha por critério confirmado pelo dev:

| CA | Situação | Evidência | Falta | Teste |
|---|---|---|---|---|
| CA1 | atendido | `bo/PlanejamentoRotasBO.java:812` grava o status 8 | — | Cenário 2 |
| CA3 | nao_atendido | — | filtro por órgão na pesquisa | — |
| CA4 | verificar_no_teste | `pesquisaRotas.xhtml:140` novo botão | — | Cenário 5 |

Situações (use exatamente estes valores):
- `atendido`: há código no diff que implementa o critério. Aponte `arquivo:linha`.
- `parcial`: implementa parte; diga o que falta.
- `nao_atendido`: o critério pede algo que o diff não faz.
- `nao_encontrado`: você não achou evidência. Não chute: na dúvida é `nao_encontrado`, nunca `atendido`.
- `verificar_no_teste`: só dá para saber rodando (EL, layout do protótipo, botão por perfil, mensagem na tela). Aponte o cenário do plano que comprova.

Como decidir (para a avaliação não mudar de uma execução para outra):
- `atendido` exige uma linha **adicionada ou alterada** no diff. Se o comportamento vem de código que já existia e o diff só o liga (um botão novo que chama um método antigo), a evidência diz isso: "`ConvenenteBean.java:181` já existia; o diff liga o botão em `aba...xhtml:381`".
- O critério depende de EL, layout, perfil ou mensagem exibida? Então é `verificar_no_teste`, mesmo que o código pareça certo. Na dúvida entre `atendido` e `verificar_no_teste`, use `verificar_no_teste`.
- `arquivo:linha` é a linha no arquivo **da ponta da branch** (`git -C <repo> grep -n <trecho> <branch> -- <arquivo>`), não a linha do `diff.txt`.
- `atendido`, `parcial` e `verificar_no_teste` sempre têm cenário na coluna Teste. Se nenhum cenário cobre, crie o cenário ou mude a situação.

Depois da tabela, a seção **"Fora dos critérios"**: mudanças do diff que não correspondem a nenhum critério (escopo extra, efeito colateral, arquivo que parece engano). Cada uma vira item de regressão no plano ou pergunta ao dev.

**Card de retorno de homologação** (o card voltou com apontamentos, como no #36 e no #62): os critérios a avaliar são os apontamentos do retorno, cada um com um id próprio (R1, R2...) além dos CA que o dev confirmar. Antes de chamar um "botão não aparece" de bug, confira o perfil que o validador exige e pergunte ao dev com que login/perfil o homologador testou. Não afirme o perfil de um usuário sem essa confirmação. (No #36, o "Cancelar Plano" exige Encaminhador e o teste foi com um Analista Técnico.)

## Plano de teste (`out/<pasta>/plano.md`)

Vai como comentário no card, que o cliente (SEGOV) também lê. Escreva para quem vai testar na tela, sem jargão de código desnecessário, **em português correto, com acentos** (o arquivo é UTF-8; não imite os títulos sem acento do `contexto.md`, que é saída de script). Vale também para `avaliacao.md` e `banco.md`. Formato:

```
### Pré-condições
- Perfil: <perfil> no órgão <órgão>
- Massa: <registro em qual status>; como conseguir
- Banco: <script X rodado em HOMOLOG> (se houver)

### Cenário 1 — <título curto> (CA1)
1. <ação na tela>
2. ...
**Esperado:** <resultado observável>

### Cenário N — Regressão: <o que pode ter quebrado>
...

### Fora do escopo
- <o que não foi testado e por quê>
```

Depois que o dev envia os resultados dos testes, a seção `### Execução pelo dev` vai em `out/<pasta>/execucao.md`, e não no `plano.md` (ver `fluxo-card-sigcon.md`). O `card.ps1` a encaixa antes do primeiro cenário no comentário. Os títulos dos cenários seguem sempre o formato `### Cenário N — <título>`.

Numeração: a página guarda o que o dev marcou pelo número do cenário (`execucao-testes.json`).
- Enquanto esse arquivo não existe, pode renumerar à vontade; os números ficam em sequência.
- Depois que ele existe, não renumere. Se um cenário deixar de fazer sentido, apague-o inteiro e deixe o buraco na numeração (1, 3, 4). **Nunca deixe um cenário "Não aplicável" ou vazio**: ele vai para o card.

Escopo do plano (o dev já reclamou de teste pedido sem critério que o justificasse):
- Entra no plano: os critérios confirmados e a regressão **direta** do que o diff tocou para atendê-los.
- Não entra: teste de funcionalidade que o diff não mexeu, nem "por garantia".
- Classe compartilhada no diff: a regressão cobre o método ou trecho alterado e quem o chama, não a classe inteira. Junte as regressões do mesmo fluxo num cenário só.

Regras:
- Cada critério confirmado tem pelo menos um cenário, com o id no título.
- Para cada permissão ou perfil novo, um cenário positivo (perfil que vê) e um negativo (perfil que não vê).
- Cada alerta de classe compartilhada do contexto vira regressão, dentro do escopo acima.
- Cada `#{...}` novo nas telas precisa ser exercitado por algum passo: abrir a tela/aba, clicar no botão.
- Mudança de status: confira na tela seguinte do fluxo e no histórico/auditoria, se houver.
- O **Esperado** segue a regra documentada na wiki da tela (seção "Wiki" do contexto), quando ela existir e a HU não disser outra coisa. Pode citar a regra pelo nome da página ("regra 3 de Cadastrar Solicitação de Visita Técnica In Loco"), nunca pelo arquivo em `wiki/`.

## Texto público (plano.md, execucao.md, justificativaPendencias)

Isso vai como comentário do dev no card, e a SEGOV lê:
- Sem assinatura, rodapé ou menção à ferramenta ou a IA.
- **Sem nome de pessoa** (homologador, dev, PO), sem login, CPF ou senha. Para citar o retorno, diga "o apontamento de homologação de 26/10", não "o retorno da <nome da pessoa>".
- Sem a avaliação: nada de "não atendido", "parcial", "sem avaliação de implementação", "não validado nesta entrega". Pendência é conversa com o dev. Em "Fora do escopo", diga só o que não foi testado e por quê, em linguagem de teste.
- Sem nome de classe, método ou arquivo quando um nome de tela, aba ou botão diz o mesmo.

## decisao.json (`out/<pasta>/decisao.json`)

```json
{
  "criterios": [
    { "id": "CA1", "texto": "texto do critério", "situacao": "atendido", "evidencia": "bo/X.java:812", "falta": "", "teste": "Cenário 2" }
  ],
  "banco": {
    "haMudanca": true,
    "confirmadoPeloDev": true,
    "scripts": ["prompt/card_1099_resultado_instrumento_rota.sql"],
    "observacao": "INSERT do status 8 em TX_V2_STATUS_ROTA está no script do #1069"
  },
  "justificativaPendencias": ""
}
```

- `teste` preenchido = o critério aparece como coberto no comentário do card.
- `justificativaPendencias`: só se o dev decidir mover o card com critério `parcial`, `nao_atendido` ou `nao_encontrado`. O script recusa `-Mover` sem ela. **Esse texto vai no comentário público**: escreva com o dev.
- `banco.confirmadoPeloDev = true` só depois da resposta do dev; o script recusa publicar sem isso.
