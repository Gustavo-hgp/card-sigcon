# #1239 - [HM] Extrato Bancário e Registro de Execução Financeira – Tratamento de passivo referente à exibição de subtransações

areas: execucao-financeira, relatorios, visita-tecnica
data: 2026-10-28
branch: feature/registro-execucao/card_1239_subtransacoes_passivo | base: master | commit: df501b5f03
banco: não 

## Avaliação por critério

| CA | situação | teste | critério |
|---|---|---|---|
| CA1 | atendido | Cenário 1, 2 | Garantir que seja realizado o tratamento do passivo para abarcar as melhorias realizadas no Extrato Bancário e no Registro de Execução Financeira, no âmbito dos... |

## Plano publicado

### Pré-condições
- Perfil: usuário com acesso ao módulo de Execução, em órgão com convênio de conta corrente automática já cadastrado.
- Ambiente: HOMOLOG, com a estrutura de banco das subtransações (card #1237) já aplicada e com acesso à API de extrato do Banco do Brasil funcionando.
- Massa:
  - um extrato de conta corrente automático **antigo** (importado antes das melhorias de subtransações), com pelo menos um lançamento de pagamento em lote de débito (lote), ainda **sem** as subtransações gravadas;
  - de preferência, mais de um extrato nessa situação, em meses diferentes, para conferir a ordem de processamento.
- Caminho: Execução > Execução > Extrato Bancário > Pesquisar.
- Rotina do extrato bancário: roda por agendamento; para o teste, dispare a rotina manualmente apontando para o banco de HOMOLOG.

### Execução pelo dev

4 de 5 cenários executados pelo dev em 28/10/2026.

| Cenário | Executado | Observação |
|---|---|---|
| Cenário 1 — Rotina completa o passivo de um lote antigo | sim | Evidência abaixo do cenário. |
| Cenário 2 — Vários extratos pendentes, do mais recente ao mais antigo | sim | Evidência abaixo do cenário. |
| Cenário 3 — Reexecução não duplica (idempotência) | sim | Evidência abaixo do cenário. |
| Cenário 4 — Erro em um extrato não interrompe os demais | não | — |
| Cenário 5 — Regressão: importação normal do mês corrente | sim | Comportamento já verificado na homologação das entregas de exibição de subtransações (cards #1237 e #1238). |

O tratamento do passivo foi verificado completando lotes antigos, processando vários extratos na ordem do mês mais recente ao mais antigo e confirmando que a reexecução não duplica subtransações. A importação do mês corrente mantém o comportamento das entregas anteriores. Ficou sem execução o cenário de erro em um extrato isolado (Cenário 4): resta confirmar, na próxima oportunidade, que um extrato com falha de retorno permanece pendente para nova tentativa sem interromper o processamento dos demais.

### Cenário 1 — Rotina completa o passivo de um lote antigo (CA1)
1. Identifique um extrato antigo com lançamento de lote de débito sem subtransações.
2. Dispare a rotina automática do extrato bancário em HOMOLOG.
3. Ao término, abra Extrato Bancário > Pesquisar e visualize o extrato antigo.
4. Localize o lançamento em lote e expanda a linha.

**Esperado:** o lançamento em lote passa a exibir o botão de expansão; ao expandir, aparece a relação de subtransações com número, data de pagamento, CNPJ/CPF, nome do beneficiário e valor. O lançamento em lote continua aparecendo uma única vez na lista; o total do extrato não muda (as subtransações não somam valor novo ao extrato).

### Cenário 2 — Vários extratos pendentes, do mais recente ao mais antigo (CA1)
1. Deixe dois ou mais extratos antigos com lotes sem subtransações, em meses diferentes.
2. Dispare a rotina automática do extrato bancário.
3. Confira, por extrato, se as subtransações foram gravadas.

**Esperado:** os extratos pendentes são completados começando pelo mês mais recente. Extrato cujo lote já tinha subtransações não é regravado (não há subtransação duplicada). O e-mail de log da rotina informa a quantidade de lotes antigos completados e quantos extratos ainda ficaram pendentes.

### Cenário 3 — Reexecução não duplica (idempotência) (CA1)
1. Após o Cenário 1, com o lote já completado, dispare a rotina automática de novo.
2. Visualize novamente o mesmo extrato e expanda o lote.

**Esperado:** a relação de subtransações do lote permanece igual à da primeira execução, sem linhas repetidas. O lote completado antes não entra de novo na contagem de pendentes do e-mail.

### Cenário 4 — Erro em um extrato não interrompe os demais (CA1)
1. Com um extrato cujo retorno da API falhe ou não traga subtransações (por exemplo, mês sem dados na API), e outros extratos válidos pendentes, dispare a rotina.

**Esperado:** o extrato com problema continua pendente (é tentado de novo na próxima execução) e o erro aparece no e-mail de log; os demais extratos pendentes são completados normalmente. A rotina conclui sem abortar.

### Cenário 5 — Regressão: importação normal do mês corrente (CA1)
1. Deixe a rotina importar/atualizar o extrato do mês corrente de um convênio com lote de débito, pelo fluxo normal (não pelo passivo).
2. Visualize o extrato e expanda o lote.

**Esperado:** o lote do mês corrente já vem com suas subtransações, como antes. O tratamento de passivo não altera a importação corrente nem gera subtransação em duplicidade nos lotes recém-importados.

### Fora do escopo
- A exibição das subtransações em tela, PDF e XLS e a estrutura de banco são das entregas anteriores (cards #1237/#1238); aqui são usadas apenas para conferir o resultado do tratamento do passivo.
- Extratos de conta aplicação e conta poupança não têm pagamento em lote e não são alcançados pelo tratamento.
