# #1237 - [HM] Extrato Bancário – Exibir subtransações de pagamentos em lote no Extrato Bancário da Conta Corrente

areas: execucao-financeira, relatorios, visita-tecnica
data: 2026-10-23
branch: feature/registro-execucao/card_1237_subtransacoes_extrato | base: master | commit: 42f20f6b0b
banco: sim prompt/card_1237_subtransacoes_extrato.sql

## Avaliação por critério

| CA | situação | teste | critério |
|---|---|---|---|
| CA1 | atendido | Cenário 1 | Exibir todas as subtransações de pagamentos em lote na tela de visualização do Extrato Bancário Conta Corrente |
| CA2 | atendido | Cenário 2 | Replicar as subtransações no PDF do Extrato Bancário Conta Corrente (pesquisa e visualização) |
| CA3 | atendido | Cenário 3 | Replicar as subtransações no XLS do Extrato Bancário Conta Corrente (pesquisa e visualização) |
| CA4 | atendido | Cenário 4 | Replicar as subtransações no XLS Consolidado do Extrato Bancário Conta Corrente |
| CA5 | atendido | Cenário 5 | Garantir que o cadastro manual de Extrato Bancário de Conta Corrente funcione com subtransações de pagamentos em lote |

## Plano publicado

### Pré-condições
- Perfil: usuário com acesso ao módulo de Execução / Prestação de Contas, no órgão do convênio.
- Massa: um convênio de conta corrente com extrato bancário importado pela rotina automática que contenha ao menos um lançamento de **pagamento em lote** (lançamento com quantidade de sublançamentos maior que zero) com subtransações retornadas pela API do Banco do Brasil. O exemplo da história tem um lote de R$ 51.670,54 com duas subtransações.
- Banco: script `card_1237_subtransacoes_extrato.sql` executado no banco de homologação (confirmado pelo desenvolvedor).
- Ponto de atenção: as subtransações passam a existir na tabela de lançamentos sem extrato próprio. As views externas de BI sobre essa tabela precisam ser avaliadas pela DBA para não somar o lote em dobro; essa avaliação ainda será feita.

### Execução pelo dev

7 de 7 cenários executados pelo desenvolvedor em 23/10/2026. Todos sem divergência em relação ao esperado.

| Cenário | Executado | Observação |
|---|---|---|
| Cenário 1 — Subtransações na tela de visualização | sim | Evidência abaixo do cenário. |
| Cenário 2 — Subtransações no PDF | sim | PDF conferido nas duas origens: ação "Download PDF" da tela de pesquisa e botão "Download PDF" da tela de visualização. Evidências abaixo do cenário. |
| Cenário 3 — Subtransações no XLS | sim | XLS conferido nas duas origens: ação "Download XLS" da tela de pesquisa e botão "Download XLS" da tela de visualização. Evidências abaixo do cenário. |
| Cenário 4 — Subtransações no XLS Consolidado | sim | Evidência abaixo do cenário. |
| Cenário 5 — Cadastro manual de extrato (regressão) | sim | Cadastro manual conferido em dois extratos de um mesmo convênio de conta corrente (competências 04/2025 e 03/2024), salvos e exibidos normalmente. Evidências abaixo do cenário. |
| Cenário 6 — Regressão de relatórios (classe compartilhada) | sim | — |
| Cenário 7 — Regressão da importação automática de extrato | sim | — |

Todos os cenários planejados foram executados, incluindo as regressões de relatórios e da importação automática. Não houve pendência de teste.

### Cenário 1 — Subtransações na tela de visualização (CA1)
1. Acesse Execução > Execução > Extrato Bancário > Pesquisar.
2. Pesquise o extrato do convênio e do período que tem o pagamento em lote.
3. Na coluna Ações, clique em Visualizar.
4. Localize o lançamento do pagamento em lote na lista e clique no ícone de expansão (seta) no início da linha.
**Esperado:** a linha expande e mostra a tabela "Relação de Subtransações do Lançamento", com a contagem no título, e uma linha por subtransação com número, data do pagamento, CNPJ/CPF, nome do beneficiário e valor. Os valores e a soma das subtransações devem corresponder ao lote. Lançamentos que não são lote não exibem o ícone de expansão. A paginação e a troca de página da lista continuam funcionando normalmente.

### Cenário 2 — Subtransações no PDF (CA2)
1. Repita a pesquisa do Cenário 1.
2. Baixe o PDF pela ação "Download PDF" da tela de pesquisa.
3. Abra o extrato e baixe o PDF também pelo botão "Download PDF" da tela de visualização.
**Esperado:** nos dois PDFs, abaixo do lançamento do lote aparecem as subtransações. Em cada subtransação, a coluna Data traz a data do pagamento, o Histórico traz "Subtransação N - situação", e as colunas Agência Origem, Lote e Documento ficam em branco (são do lote, não da subtransação). Beneficiário e valor são os da subtransação.

### Cenário 3 — Subtransações no XLS (CA3)
1. Na tela de pesquisa, use a ação "Download XLS".
2. Na tela de visualização, use o botão "Download XLS".
**Esperado:** nos dois arquivos, cada lote vem seguido das suas subtransações, com o mesmo preenchimento de colunas descrito no Cenário 2 (data do pagamento, histórico "Subtransação…", beneficiário e valor; agência, lote e documento em branco na subtransação).

### Cenário 4 — Subtransações no XLS Consolidado (CA4)
1. Na tela de pesquisa de Extratos Bancários, selecione mais de um extrato de conta corrente do mesmo tipo, sendo pelo menos um com pagamento em lote.
2. Use a ação "XLS Consolidado".
**Esperado:** o arquivo consolidado traz, para cada extrato, os lançamentos seguidos das suas subtransações, com a coluna de número do instrumento preenchida e o mesmo tratamento das subtransações do Cenário 3.

### Cenário 5 — Cadastro manual de extrato (CA5 / regressão)
1. Acesse Execução > Execução > Extrato Bancário > Cadastrar.
2. Cadastre manualmente um extrato de conta corrente com lançamentos, salvando normalmente.
3. Pesquise e visualize o extrato cadastrado.
**Esperado:** o cadastro manual salva e exibe os lançamentos como antes. Os lançamentos do cadastro manual não exibem ícone de expansão (não há subtransações buscadas no cadastro manual). Nenhum erro ao salvar mesmo após a alteração que deixou a vinculação ao extrato opcional.

### Cenário 6 — Regressão de relatórios (classe compartilhada)
1. Gere ao menos um relatório do módulo de Execução que **não** seja o extrato bancário (por exemplo, um relatório de registro de execução).
**Esperado:** o relatório é gerado normalmente, sem erro, pois a classe que monta os parâmetros do relatório é compartilhada e foi alterada.

### Cenário 7 — Regressão da importação automática de extrato
1. Dispare (ou aguarde) a rotina automática de importação de extrato bancário para um convênio de conta corrente.
2. Confira os lançamentos importados na tela de visualização do extrato.
**Esperado:** a importação conclui normalmente; os lançamentos de conta corrente são gravados como antes e, para os lotes, as subtransações aparecem na expansão. Extratos de conta aplicação e poupança seguem inalterados. Eventual falha na busca de subtransações não interrompe a importação.

### Fora do escopo
- Reprocessamento de lotes importados antes deste card (que ainda não têm subtransações gravadas) depende de chamada à API do Banco do Brasil e não foi exercitado neste plano.
- Ajuste das views externas de BI sobre a tabela de lançamentos (ponto de atenção para a DBA).
