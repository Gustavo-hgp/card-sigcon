# #1238 - [HM] Execução Financeira – Exibir subtransações de pagamentos em lote no Registro de Execução Financeira

areas: execucao-financeira, visita-tecnica
data: 2026-10-27
branch: feature/registro-execucao/card_1238_subtransacoes_registro_financeiro | base: 24c45e44c7~1 | commit: 1dd67aa5a1
banco: não 

## Avaliação por critério

| CA | situação | teste | critério |
|---|---|---|---|
| CA1 | atendido | Cenário 1 | Exibir todas as subtransações de pagamentos em lote na seção 3. Operações Bancárias da aba Movimentação Bancária para seleção |
| CA1.1 | atendido | Cenário 2 | Remover a duplicidade do símbolo R$ na seção 3. Operações Bancárias |
| CA2 | atendido | Cenário 3 | Exibir as subtransações selecionadas no campo Movimentação Bancária da aba Informações sobre a Despesa |
| CA3 | atendido | Cenário 6 | Replicar as alterações dos CA1 e CA2 no Consolidado e no PDF do Registro de Execução Financeira |
| CA4 | atendido | Cenários 4, 5, 7 | Manter a regra de uma movimentação por Registro encaminhado válida para as subtransações, na aba e no encaminhamento |

## Plano publicado

### Pré-condições
- Perfil: Cadastrador (usuário externo) no órgão convenente do instrumento.
- Massa: um convênio em execução com extrato bancário já **importado pela rotina automática** de importação, contendo pelo menos um **pagamento em lote** (lançamento com subtransações). As subtransações só são gravadas pela importação automática; o cadastro manual do extrato não as traz. Tenha também um lançamento comum (sem lote) e, se possível, um lançamento de poupança, para a regressão.
- Tela: Execução > Execução > Registros de Execução > Execução Financeira > Cadastrar.
- Banco: não há script para este card.

### Execução pelo dev

8 de 8 cenários executados pelo dev em 27/10/2026, todos com sucesso.

| Cenário | Executado | Observação |
|---|---|---|
| Cenário 1 — Subtransações do lote aparecem para seleção (CA1) | sim | Validado com um convênio em execução; evidência abaixo do cenário. |
| Cenário 2 — Símbolo "R$" sem duplicidade (CA1.1) | sim | Evidência abaixo do cenário. |
| Cenário 3 — Subtransação selecionada aparece na aba Informações sobre a Despesa (CA2) | sim | Evidência abaixo do cenário. |
| Cenário 4 — Lote e subtransação não entram juntos (CA4 — aba) | sim | A seleção passou a ser mutuamente exclusiva: ao marcar o lote, as subtransações ficam presas a ele, de modo que não é possível selecionar o lote e uma subtransação dele ao mesmo tempo. A própria tela impede a combinação, sem necessidade de mensagem de erro. |
| Cenário 5 — Bloqueio por vínculo já existente (CA4) | sim | Validado com um registro já encaminhado; duas evidências abaixo do cenário. |
| Cenário 6 — Consolidado e PDF (CA3) | sim | Subtransações vinculadas conferidas no Consolidado e no PDF; duas evidências abaixo do cenário. |
| Cenário 7 — Regressão: operação já vinculada não reentra (CA4) | sim | Operação bancária já vinculada deixa de ficar disponível para seleção, de modo que não há como reencaminhá-la. |
| Cenário 8 — Regressão: lançamento comum e poupança | sim | Fluxo normal confirmado; evidência abaixo do cenário. |

Todos os cenários foram executados sem falhas. A regra de lote×subtransação (CA4) foi confirmada na seleção da aba Movimentação Bancária (seleção mutuamente exclusiva, com as subtransações presas ao lote marcado) e no reaproveitamento de operações já encaminhadas, que deixam de ficar disponíveis para nova vinculação. As subtransações foram confirmadas na aba Informações sobre a Despesa (CA2) e no Consolidado e PDF (CA3).

### Cenário 1 — Subtransações do lote aparecem para seleção (CA1)
1. Abra o cadastro de um Registro de Execução Financeira do convênio.
2. Vá à aba "Movimentação Bancária", seção "3. Operações Bancárias de (Mês)/(Ano)".
3. Localize o pagamento em lote e as subtransações abaixo dele.
4. Marque o lote e observe as subtransações; depois desmarque o lote.
5. Em outro lote, marque todas as subtransações, uma a uma.
**Esperado:** o lote aparece com "(lote com N subtransações abaixo)" e, logo abaixo, cada subtransação como "Subtransação N - <beneficiário>", indentada. Ao marcar o lote, as subtransações dele ficam marcadas e travadas (não podem ser desmarcadas individualmente); ao desmarcar o lote, as subtransações são liberadas. Ao marcar todas as subtransações de um lote, o próprio lote passa a aparecer marcado.

### Cenário 2 — Símbolo "R$" sem duplicidade (CA1.1)
1. Ainda na seção "3. Operações Bancárias", observe a coluna "Valor" de qualquer linha (lote, subtransação e lançamento comum).
**Esperado:** o valor aparece com um único "R$" (ex.: "R$ 1.234,56"), sem "R$ R$".

### Cenário 3 — Subtransação selecionada aparece na aba Informações sobre a Despesa (CA2)
1. Na aba "Movimentação Bancária", selecione uma ou mais subtransações de um lote e confirme.
2. Vá à aba "Informações sobre a Despesa", seção "1. Informações sobre a Despesa".
3. Abra o campo "Movimentação Bancária*".
**Esperado:** as subtransações selecionadas aparecem na lista do campo para detalhamento, identificáveis (data, valor e histórico); é possível selecionar uma delas e detalhar a despesa.

### Cenário 4 — Lote e subtransação não entram juntos (CA4 — aba)
1. Na aba "Movimentação Bancária", marque um lote de pagamentos.
2. Tente marcar, isoladamente, uma única subtransação desse mesmo lote (deixando o lote marcado), e vice-versa.
**Esperado:** a seleção é mutuamente exclusiva. Com o lote marcado, as subtransações dele ficam travadas (presas ao lote), e não é possível montar a combinação "lote inteiro + uma subtransação avulsa dele". Por isso a vinculação não chega a ser recusada por mensagem — a própria tela não deixa selecionar os dois ao mesmo tempo.

### Cenário 5 — Bloqueio por vínculo já existente (CA4)
1. Em um registro, vincule e **encaminhe** (status encaminhado ao OEEP/Concedente) um registro com o **lote** inteiro.
2. Em outro registro do mesmo convênio/período, abra a aba "Movimentação Bancária".
**Esperado:** as subtransações desse lote aparecem indisponíveis, com a situação em vermelho "Indisponível: o lote inteiro já foi vinculado".
3. Refaça o teste no sentido inverso: encaminhe um registro com uma **subtransação** e verifique que o **lote** correspondente fica indisponível com "Indisponível: há subtransação do lote vinculada".

### Cenário 6 — Consolidado e PDF (CA3)
1. Em um registro com subtransações vinculadas, vá à aba/visão "Consolidado".
2. Gere o PDF do Registro de Execução Financeira.
**Esperado:** as subtransações vinculadas aparecem na listagem de operações bancárias, tanto no Consolidado quanto no PDF, com data, histórico, número da operação e valor próprios, e compõem o valor total corretamente.
   Observação: subtransações do mesmo lote aparecem com o mesmo histórico, diferenciadas pelo valor. Isso é o comportamento atual (sem o rótulo "Subtransação N" dessa tela); confirme se atende.

### Cenário 7 — Regressão: operação já vinculada não reentra (CA4)
1. Vincule e encaminhe um registro com uma operação bancária (lote, subtransação ou lançamento comum).
2. Em outro registro do mesmo convênio/período, abra a aba "Movimentação Bancária" com várias operações, entre elas a já encaminhada.
**Esperado:** a operação já vinculada a registro encaminhado aparece indisponível para seleção (não é possível marcá-la), de modo que não há como reencaminhá-la. O bloqueio independe da posição dela na lista. (Antes, no laço de verificação, só a última operação era considerada.)

### Cenário 8 — Regressão: lançamento comum e poupança
1. Selecione e vincule um lançamento comum (sem subtransações) e, se houver, um de poupança.
2. Confirme e verifique a aba Informações sobre a Despesa, o Consolidado e o PDF.
**Esperado:** fluxo normal, sem bloqueio indevido e sem alteração na exibição desses lançamentos.

### Fora do escopo
- Importação automática do extrato (gravação das subtransações) — entregue no #1237.
- Replicação do rótulo "Subtransação N — beneficiário" no Consolidado/PDF — só se a PO solicitar.
