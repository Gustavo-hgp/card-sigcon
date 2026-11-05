# #62 - [HM] A1.2.1 Dotação Orçamentária – Permitir a atualização dos dados de Identificação do Convenente/OSC Parceira – #62

areas: alteracao-instrumento
data: 2026-10-27
branch: ff5c3cde96 | base: bf5c71947b | commit: ff5c3cde96
banco: não 

## Avaliação por critério

| CA | situação | teste | critério |
|---|---|---|---|
| CA1 | verificar_no_teste | Cenário 1 | Durante todo o fluxo da Alteração de Dotação Orçamentária, os botões Atualizar Dados e Salvar da aba Identificação do Convenente/OSC Parceira permanecem habilit... |
| CA1.1 | atendido | Cenário 1 | Quando a consulta ao CAGEC for realizada com sucesso e os dados forem atualizados, exibir a mensagem de sucesso: Dados atualizados! |
| CA2 | verificar_no_teste |  | Ao salvar os dados atualizados na aba Identificação do Convenente/OSC Parceira, o sistema atualiza o status da aba para Alterado, exibindo o ícone de identifica... |

## Plano publicado

### Pré-condições
- Perfil: usuário interno do Concedente (órgão do instrumento) e, para o cenário externo, usuário do Convenente/OSC Parceira.
- Massa: um instrumento jurídico vigente, do órgão do usuário, com uma Alteração de "Dotação Orçamentária" em andamento (status em que a aba de identificação fica editável). Tenha também, para regressão, um convênio em celebração (sem alteração) e uma alteração de outro tipo (Alteração Simples ou Termo Aditivo).
- Caminho: Celebração de Instrumento > Pesquisar > Acessar Instrumento > aba "Alterações do Convênio/Parceria" > abrir a Alteração de "Dotação Orçamentária" > aba "Identificação do Convenente/OSC Parceira".
- Banco: nenhum script necessário para esta correção.

### Execução pelo dev

3 de 4 cenários executados pelo dev em 27/10/2026.

| Cenário | Executado | Observação |
|---|---|---|
| Cenário 1 — Atualizar os dados do Convenente/OSC Parceira na Dotação Orçamentária | sim | Evidência abaixo do cenário. |
| Cenário 2 — Não aplicável | não | Cenário não aplicável nesta entrega. |
| Cenário 3 — Regressão: abas de identificação (Concedente, Convenente, Interveniente) nos demais fluxos | sim | Evidência abaixo do cenário. |
| Cenário 4 — Regressão: indicadores de status das abas e nomes de aba | sim | Evidência abaixo do cenário. |

A atualização dos dados do Convenente/OSC Parceira na Alteração de Dotação Orçamentária foi validada no fluxo do usuário interno (Cenário 1), assim como a regressão das abas de identificação e dos indicadores de status (Cenários 3 e 4). O Cenário 2 não se aplica a esta entrega.

### Cenário 1 — Atualizar os dados do Convenente/OSC Parceira na Dotação Orçamentária (CA1, CA1.1)
1. Abra a Alteração de "Dotação Orçamentária" e vá para a aba "Identificação do Convenente/OSC Parceira".
2. Confira que a aba abre com o layout correto, sem campos sobrepostos ou desalinhados.
3. Confirme que os botões "Atualizar Dados" e "Salvar" aparecem e estão habilitados.
4. Clique em "Atualizar Dados" para buscar as informações vigentes no CAGEC.
5. Confira os dados retornados e clique em "Salvar".
**Esperado:** os dados são atualizados conforme o CAGEC; é exibida a mensagem "Sucesso: Dados atualizados!"; nenhuma mensagem de erro aparece, em especial **não** deve aparecer "Data vencimento mandato inválida!".

### Cenário 2 — Não aplicável
Cenário não aplicável nesta entrega.

### Cenário 3 — Regressão: abas de identificação (Concedente, Convenente, Interveniente) nos demais fluxos
1. Repita a abertura da aba "Identificação do Convenente/OSC Parceira" num convênio em celebração (sem alteração) e confira layout e campos.
2. Abra as abas "Identificação do Concedente" e "Identificação do Interveniente" na celebração e numa alteração de outro tipo (Alteração Simples ou Termo Aditivo).
3. No campo "Vencimento do Mandato" do representante legal, informe uma data válida (dd/mm/aaaa) e salve; depois deixe em branco e salve.
**Esperado:** as três abas abrem com o layout correto em todos os fluxos; o campo "Vencimento do Mandato" aceita data válida e não dispara "Data vencimento mandato inválida!"; os demais tipos de alteração e a celebração continuam salvando normalmente.

### Cenário 4 — Regressão: indicadores de status das abas e nomes de aba
1. Em uma alteração em andamento, percorra as abas e observe os indicadores de obrigatoriedade/preenchimento (cores laranja e amarela) e os nomes das abas ("Atuação em Rede", "Informações Gerais", "Informações de Repasse de Recursos", "Informações de Execução", "Endereços", "Outras Informações", "Cronograma de Execução", "Plano de Aplicação de Recursos").
2. Confira que os nomes das abas aparecem com os acentos corretos, sem caracteres quebrados.
3. Abra a aba "Outras Informações" e confirme que ela carrega o conteúdo (correção do include da aba).
**Esperado:** os indicadores de status aparecem nas abas conforme o preenchimento; os nomes das abas estão com acentuação correta; a aba "Outras Informações" carrega normalmente.

### Fora do escopo
- CA2 (status "Alterado" da aba) e os indicadores de status em massa não fizeram parte do retorno da Gerda; foram verificados aqui apenas como regressão visual, sem avaliação de implementação dedicada.
- Fluxo de consulta ao CAGEC em si (integração) não é testado isoladamente; valida-se pelo resultado da atualização em tela.
