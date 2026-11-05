# #37 - [HU] A5.1 Rescisão – Criar tela inicial de cadastro da Alteração "Rescisão do Convênio/Parceria" – #37

areas: alteracao-instrumento
data: 2026-10-23
branch: feature/alteracao-instrumento/geral | base: a23aa8e30c | commit: f5c5109291
banco: não 

## Avaliação por critério

| CA | situação | teste | critério |
|---|---|---|---|
| CA1 | atendido | Cenário 1 | Selecionar Rescisão e Criar Alteração direciona à tela inicial da Rescisão |
| CA2 | atendido | Cenário 1 | Alteração criada com status inicial Cadastramento da Alteração |
| CA3 | atendido | Cenário 1 | Seção Formalização da Rescisão |
| CA3.1 | atendido | Cenário 1 | Radio Tipo da Rescisão obrigatório |
| CA3.2 | atendido | Cenário 1 | Radio notificação prévia obrigatório, 30 dias convênio / 60 dias parceria |
| CA4 | atendido | Cenário 2 | Aba Auditoria |
| CA5 | verificar_no_teste | Cenário 2 | Aba Documentos Anexados - Histórico |
| CA6 | atendido | Cenário 2 | Aba Documentos Anexados |
| CA6.1 | atendido | Cenário 2 | Ocultar Incluir Documento no cadastramento |
| CA7 | atendido | Cenário 2 | Aba Justificativa da Alteração |
| CA8.1 | atendido | Cenário 3 | Botão Voltar retorna ao Instrumento Jurídico |
| CA8.2 | verificar_no_teste | Cenário 3 | Botão Salvar e Encaminhar para Análise Técnica |
| CA8.2.1 | verificar_no_teste | Cenário 4 | Mensagem de campo obrigatório ao encaminhar |
| CA8.2.2 | verificar_no_teste | Cenário 5 | Bloqueio ao encaminhar quando não houve notificação prévia |
| CA9 | verificar_no_teste | Cenário 3 | Status passa para Análise Técnica da Alteração ao encaminhar |
| CA9.1 | verificar_no_teste | Cenário 3 | Mensagem de sucesso após encaminhar |

## Plano publicado

### Pré-condições
- Perfil: Analista Técnico interno do concedente (órgão do instrumento). Para o cenário negativo, um perfil interno que não seja Analista Técnico (ex.: apenas Encaminhador).
- Massa: um instrumento jurídico vigente, do órgão do usuário, que permita cadastrar a alteração "Rescisão do Convênio/Parceria". Pode-se usar um convênio e uma parceria, para checar o prazo de notificação (30 e 60 dias).
- Caminho: Celebração de Instrumento > Pesquisar > Acessar Instrumento > aba "Alterações do Convênio/Parceria" > Cadastrar Alteração > selecionar "Rescisão do Convênio/Parceria" > Criar Alteração.
- Banco: nenhum script necessário para esta correção.

### Cenário 1 — Criar a Rescisão e conferir a tela inicial (CA1, CA2, CA3, CA3.1, CA3.2)
1. No instrumento, abra a aba "Alterações do Convênio/Parceria", seção "Cadastrar Alteração".
2. Selecione "Rescisão do Convênio/Parceria" e clique em "Criar Alteração".
3. Confira que a tela inicial da Rescisão abre.
4. Confira a seção "Formalização da Rescisão", com o radio "Tipo da Rescisão" (Mútuo Acordo / Rescisão Unilateral) e o radio "Houve notificação prévia às partes, com antecedência mínima de __ dias?" (Sim / Não).
5. Repita a criação num convênio e numa parceria para conferir a lacuna de dias.
**Esperado:** a alteração é criada com status "Cadastramento da Alteração"; os dois radios aparecem como obrigatórios; a pergunta mostra 30 dias para convênio e 60 dias para parceria.

### Cenário 2 — Abas da Rescisão, com destaque para "Documentos Anexados - Histórico" (CA4, CA5, CA6, CA6.1, CA7)
1. Na tela da Rescisão em "Cadastramento da Alteração", abra, uma a uma, as abas Auditoria, Documentos Anexados - Histórico, Documentos Anexados e Justificativa da Alteração.
2. Na aba "Documentos Anexados - Histórico", confirme que ela agora é exibida (antes da correção não aparecia na rescisão) e que lista o histórico.
3. Na aba "Documentos Anexados", confirme que o botão "Incluir Documento" está oculto enquanto o status é "Cadastramento da Alteração".
**Esperado:** as quatro abas aparecem e abrem sem erro; a aba "Documentos Anexados - Histórico" está presente; o botão "Incluir Documento" não aparece no cadastramento.

### Cenário 3 — Encaminhar para Análise Técnica com o Analista Técnico (CA8.1, CA8.2, CA9, CA9.1)
1. Logado como Analista Técnico interno do órgão, abra a Rescisão em "Cadastramento da Alteração".
2. Confira que o rodapé mostra os botões "Voltar" e "Salvar e Encaminhar para Análise Técnica".
3. Preencha "Tipo da Rescisão" e marque "Sim" em "Houve notificação prévia...".
4. Clique em "Salvar e Encaminhar para Análise Técnica".
5. Reabra o instrumento e confira o status e a linha do tempo da alteração.
**Esperado:** o botão "Salvar e Encaminhar para Análise Técnica" aparece para o Analista Técnico; ao clicar, a alteração é salva e o status passa para "Análise Técnica da Alteração"; é exibida a mensagem "Sucesso: Operação realizada com sucesso."; o botão "Voltar" retorna à tela do instrumento.

### Cenário 4 — Campos obrigatórios ao encaminhar (CA8.2.1)
1. Na Rescisão em cadastramento, deixe "Tipo da Rescisão" e/ou a notificação prévia sem preencher.
2. Clique em "Salvar e Encaminhar para Análise Técnica".
**Esperado:** o sistema não encaminha e exibe "Campo obrigatório não informado. \"(nome do campo)\" é de preenchimento obrigatório.", indicando o campo que faltou.

### Cenário 5 — Bloqueio sem notificação prévia (CA8.2.2)
1. Na Rescisão em cadastramento, preencha "Tipo da Rescisão" e marque "Não" em "Houve notificação prévia...".
2. Clique em "Salvar e Encaminhar para Análise Técnica".
**Esperado:** o sistema impede o prosseguimento e exibe "Erro: O processo somente poderá ser encaminhado para Análise Técnica após a realização da notificação prévia às partes, observando o prazo mínimo exigido."; o status continua "Cadastramento da Alteração".

### Cenário 6 — Regressão de tela/classe compartilhada (celebração e demais alterações)
1. Como perfil que não é Analista Técnico (ex.: só Encaminhador), abra uma Rescisão em cadastramento e confira que o botão "Salvar e Encaminhar para Análise Técnica" **não** aparece para esse perfil.
2. Abra um fluxo de celebração (convênio sem alteração) e confira que o cadastro/encaminhamento continua funcionando como antes, sem botão extra indevido.
3. Abra uma alteração de outro tipo (ex.: Alteração Simples ou Termo Aditivo) em cadastramento e confira que o botão de encaminhar continua aparecendo para quem já tinha permissão e que a aba "Documentos Anexados - Histórico" continua correta.
**Esperado:** o novo ramo de permissão só habilita o botão na Rescisão em cadastramento para o Analista Técnico; celebração e os demais tipos de alteração seguem sem alteração de comportamento; a aba "Documentos Anexados - Histórico" aparece corretamente em todos os fluxos.

### Fora do escopo
- Tipo de alteração "Rescisão" (enum/status) e seu script de banco: tratados nos cards #36 e #38.
- Etapa de "Análise Técnica da Alteração" propriamente dita: card #38.
