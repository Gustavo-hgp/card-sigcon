---
inclusion: manual
---

# Fluxo do card-sigcon

Você ajuda o dev a fechar um card do SIGCON: confere a branch, avalia a entrega por critério de aceite, checa a parte de banco, escreve o plano de teste e, com o aval do dev, atualiza o card e o card filho no GitLab.

**Divisão de trabalho:** tudo o que é regra fixa está no `card.ps1` (base do diff, camada 1 de banco, card filho, etiquetas, coluna). Você faz o que precisa de julgamento. Nunca chame a API do GitLab por conta própria e nunca edite o repositório do SIGCON.

Comando base (rode sempre da raiz desta pasta):

```
powershell -NoProfile -ExecutionPolicy Bypass -File ./card.ps1 <comando> ...
```

**Avaliação técnica:** se a primeira mensagem diz "Avaliação técnica", o card ainda não foi desenvolvido. Siga `avaliacao-tecnica.md` em vez deste fluxo.

**Card que já teve avaliação técnica:** a avaliação aparece nos comentários do contexto como nota interna (marcada "avaliação técnica do card-sigcon"). Use-a como ponto de partida e, na avaliação por critério, aponte o que saiu diferente do previsto (telas a mais, banco que não estava previsto). Isso vira aprendizado na área `avaliacao-tecnica`.

## Quando a conversa vem da página

Se a primeira mensagem contém `(pagina do card-sigcon)`, o dev está usando a página local, e cada resposta dele chega como uma nova mensagem:
- Faça as etapas 1 a 9 normalmente, uma pergunta por vez, e seja direto: a página mostra os seus arquivos em abas (commits, critérios, avaliação, banco, plano).
- Depois de gravar o `decisao.json`, **pare**. Não rode `simular` nem `publicar`: diga ao dev que os arquivos estão prontos e que ele usa os botões **Simular** e **Publicar** da página.
- Ao final, proponha o aprendizado (etapa 11) normalmente; a página tem a aba Aprendizado para o dev aceitar ou descartar.
- Na aba Plano, o dev marca os cenários que executou e escreve observações. Quando ele mandar "Resultado dos meus testes do plano", siga a etapa **Execução pelo dev** abaixo.
- **Perguntas para o dev (vale também para a avaliação técnica).** Quando o turno terminar esperando resposta, termine a mensagem com o bloco abaixo. A página mostra cada pergunta em destaque, com as opções como botões e um campo para outra resposta; o bloco em si não aparece como texto.

  ```
  <!-- card-sigcon:perguntas
  [
    {"pergunta": "Esses 4 commits são do card?", "opcoes": ["Sim, os 4", "Só os 2 mais recentes", "Não, vou explicar"]},
    {"pergunta": "Quais critérios ficam fora desta entrega?", "opcoes": ["CA3", "CA5", "Nenhum"], "multipla": true}
  ]
  -->
  ```
  - De 1 a 4 perguntas, só as que você precisa agora. Pergunta curta e direta, uma coisa por pergunta.
  - De 2 a 5 opções por pergunta, escritas como a resposta pronta do dev ("Sim, os 4"), e não como "Opção A". Quando fizer sentido, inclua uma saída como "Não, vou explicar"; o dev sempre pode escrever outra coisa.
  - `"multipla": true` quando dá para marcar mais de uma.
  - JSON válido: aspas duplas, sem vírgula sobrando, sem `-->` dentro.
  - No texto da mensagem, dê o contexto que o dev precisa para responder (o que você achou, o que pesa na decisão). Não repita a pergunta em prosa: o bloco é que pergunta.
  - Turno que não espera resposta (por exemplo, "arquivos prontos, use Simular e Publicar") não leva o bloco.

## Execução pelo dev (resultados dos testes)

O dev marca, cenário por cenário, se executou e o que observou. Isso fica em `out/<pasta>/execucao-testes.json`:

```json
{ "cenarios": { "cenario-3": { "titulo": "Cenário 3 — ...", "feito": true, "observacao": "...", "atualizadoEm": "..." } } }
```

Quando ele enviar os resultados:

1. **Leia o JSON** (a mensagem dele traz um resumo, mas o arquivo é a fonte). A chave é o número do cenário. **A partir daqui, nunca renumere, renomeie ou reordene os cenários do `plano.md`**: as marcações da página dependem do número (regra de numeração em `plano-e-avaliacao.md`).
2. **Grave `out/<pasta>/execucao.md`** (arquivo novo; se já existir, reescreva inteiro) começando por `### Execução pelo dev`.
   - **Não edite o `plano.md` para isso.** O `card.ps1` coloca essa seção no comentário do card, antes do primeiro cenário, e a página mostra no mesmo lugar.
   - Só mexa no `plano.md` se uma observação mostrar que um passo de um cenário estava errado (por exemplo, o caminho de menu é outro). Nesse caso, corrija o passo sem renumerar o cenário.
   - Resumo: quantos cenários foram executados (ex.: "8 de 10 cenários executados pelo dev em <data>").
   - Tabela `| Cenário | Executado | Observação |`: uma linha por cenário, "sim" ou "não". Se o cenário tem evidência anexada (a mensagem do dev diz quantas), acrescente "evidência abaixo do cenário" na observação.
   - **Não escreva links nem nomes de arquivo de evidência.** Os prints e vídeos ficam em `out/<pasta>/evidencias/` e o `card.ps1` os coloca no fim de cada cenário, no comentário. Não leia nem descreva o conteúdo deles.
   - Uma ou duas frases suas: o que ficou sem teste e o que isso significa para a homologação, por exemplo "Cenário 7 depende do script de banco em HOMOLOG".
   - As observações vão para o card, que a SEGOV lê. Reescreva cada uma em português correto e tom profissional, **sem mudar o sentido**. Tire nome de pessoa, CPF, senha e dado de cliente. Se uma observação for só desabafo ou anotação pessoal, resuma o fato técnico.
3. **Ajuste a avaliação se precisar.** Se uma observação indicar falha, comportamento diferente do esperado ou critério não atendido:
   - atualize o `avaliacao.md` e a `situacao` do critério no `decisao.json` (`parcial` ou `nao_atendido`);
   - avise o dev na resposta, citando o cenário.

   Cenário executado sem problema confirma os critérios `verificar_no_teste` dele: pode passá-los para `atendido`, com a evidência "testado pelo dev (cenário N)". Cenário não executado mantém o critério como estava.
4. **Pare.** Diga o que mudou e lembre o dev de rodar o **Simular** de novo antes de publicar, porque o plano mudou.

## Etapas

1. **Entrada.** Peça ao dev o que faltar: link do card, branch em que trabalhou e a **base** de onde a branch saiu (master, geral-merge, alteracao-instrumento/geral ou um commit). Se ele não souber:
   - alteração de instrumento sai de `feature/alteracao-instrumento/geral`;
   - visita técnica sai de `feature/registro-execucao/geral-merge` (a `feature/registro-execucao/geral` está parada, não use);
   - extrato, execução financeira e correção de produção saem do `master`.

2. **Coletar.** Rode `./card.ps1 coletar -Card "<link>" -Branch "<branch>" -Base "<base>"`.
   - Se terminar com `ERRO:`, mostre a mensagem e pare. Branch contaminada não se contorna: o dev precisa corrigir a base ou recriar a branch.
   - Se avisar **"Nenhum commit entre a base e a branch"** e a branch for uma geral, o card já foi mergeado nela (aconteceu no #36 e no #62). Ache os commits do card (`git -C <repo> log --oneline --grep "<número do card>" <branch>`, e confirme com o dev), e rode o coletar de novo com `-Branch <sha do último commit do card>` e `-Base <sha do primeiro commit do card>~1`. Se houver merge de outro card no meio, trate como na regra abaixo.
   - Mostre ao dev a lista de commits e os alertas e pergunte: **"esses são os commits do card?"**. Não siga sem o sim. Commits de outro card (merge de outra branch) mudam a avaliação: pergunte o que é do card.
   - Se o dev disser que só os commits mais recentes são do card, **rode o coletar de novo** com `-Base <commit mais antigo do card>~1` (o commit logo antes do primeiro do card). Assim o `diff.txt` e a checagem de banco ficam só com o card; não tente separar os commits com git na mão. Se os commits do card estiverem intercalados com os de outro card, avise o dev e avalie a branch inteira, separando o que é de cada card em "Fora dos critérios".

3. **Ler.** Leia `out/<pasta>/contexto.md` inteiro e o `diff.txt` (em partes, se for grande). Leia os arquivos de exemplo do histórico listados no contexto. Respeite o aprendizado que veio no contexto. Para entender um trecho, você pode ler o arquivo completo no repositório do SIGCON ou rodar `git -C <repo> show/log/grep`.
   - **Saída curta sempre.** O Kiro para de ler a saída de um comando depois de um limite, e um `git grep` com milhares de linhas trava o turno. Use `-l` ou `-c` primeiro, `-m 5` para limitar linhas por arquivo, restrinja a pasta e evite palavras genéricas.
   - **Wiki do sistema.** Leia as páginas listadas na seção "Wiki" do contexto: são a regra de negócio documentada das telas do card. Se a HU citar outra tela, procure a página dela em `wiki/` (índice em `wiki/_indice.md`, ou grep pelo nome da tela). A cópia em `wiki/` é só leitura: nunca grave nela.
   - A wiki pode estar desatualizada. HU reescrita ou decisão registrada em comentário vale mais que ela.
   - Divergência entre HU, wiki e código não se decide sozinho: aponte na avaliação, citando a página e a regra, e pergunte ao dev.

4. **Critérios de aceite.** Mostre a lista extraída pelo script, ou extraia você mesmo da descrição. Considere os comentários: HU reescrita ou decisão posterior muda critério. Peça ao dev para **confirmar a lista** antes de avaliar.

5. **Avaliação por critério.** Siga `plano-e-avaliacao.md` e grave `out/<pasta>/avaliacao.md`.

6. **Banco (camada 2).** Para cada item da seção de banco do contexto, decida: objeto novo, alteração de objeto existente ou falso positivo. Atenção a valor novo de enum que espelha tabela de domínio (status, tipo de auditoria, tipo de documento): precisa de INSERT mesmo sem `.sql` no diff. Grave `out/<pasta>/banco.md` e **pergunte ao dev, item a item**: tem script? onde está? já rodou em HOMOLOG?
   - O SQL vai para o card como **nota interna** (só membros do projeto veem), montada pelo `card.ps1` no Publicar. Por isso, em `decisao.json` → `banco.scripts`, ponha só **caminhos de arquivo** relativos à raiz do repositório do SIGCON (ex.: `prompt/card_1237_subtransacoes_extrato.sql`), nunca uma descrição.
   - Se o dev passar o SQL na conversa (não há arquivo no repositório), grave-o **exatamente como ele passou** em `out/<pasta>/banco.sql`. Não escreva SQL por conta própria nesse arquivo: o que estiver lá vai para o card como o script a rodar.
   - O que você quiser dizer sobre o banco (onde rodou, risco, dependência) vai em `banco.observacao`; esse texto abre a nota interna.

7. **Plano de teste.** Siga `plano-e-avaliacao.md` e grave `out/<pasta>/plano.md`. Esse é o texto que vai como comentário no card: escreva com acentos e não coloque nele a avaliação nem "não atendido".

8. **Revisão do dev.** Mostre a avaliação, o banco e o plano. Ajuste o que o dev pedir. Cada correção do dev é candidata a aprendizado (etapa 11).

9. **Decisão.** Grave `out/<pasta>/decisao.json` no formato de `plano-e-avaliacao.md`. `banco.confirmadoPeloDev` só fica `true` depois que o dev respondeu sobre banco.

10. **Publicar.** Antes do simular, releia o `plano.md` (e o `execucao.md`, se existir) e corrija o que falhar:
    - está com acentos;
    - nenhum nome de pessoa, login ou palavra da avaliação ("não atendido", "parcial", "não validado");
    - nenhum cenário "Não aplicável" ou vazio;
    - todo critério `atendido`, `parcial` ou `verificar_no_teste` do `decisao.json` aponta um cenário que existe no plano.
    - Rode `./card.ps1 simular -Card "<link>"` e mostre as ações ao dev. Acrescente `-Mover` só se o dev pedir para mudar o card de coluna.
    - O script já decide o card filho pela coluna atual. Se a coluna não tiver atividade conhecida, pergunte ao dev qual é (`-Atividade "<nome>"`) ou se não há filho (`-SemFilho`).
    - Com o "pode publicar" explícito do dev, rode `./card.ps1 publicar` com as mesmas opções.

11. **Aprendizado.** Se o dev corrigiu algo, se a checagem de banco errou ou se você aprendeu uma regra que valeria para outros cards, escreva a proposta em `aprendizado/_propostas.md`:

    ```
    ## area: <banco|plano-teste|geral|visita-tecnica|alteracao-instrumento|relatorios|execucao-financeira> | card: #<n> | data: <aaaa-mm-dd>
    Regra: <o que fazer, em uma frase acionável>
    Por que: <o que aconteceu neste card>
    Evidencia: <arquivo:linha, comentário, correção do dev>
    ```

    - Rode `./card.ps1 propostas` e pergunte ao dev quais aceitar.
    - Rode `./card.ps1 aprender -Aceitar <números> -Descartar <números>`.
    - Nunca escreva direto nos arquivos de área. Padrão de banco que a camada 1 deixou passar vira também sugestão de regex para `config/config.json` (seção `banco`), que o dev aplica.

## Retro (card voltou de homologação ou do QA)

Rode `./card.ps1 retro -Card "<link>"` e leia `out/<pasta>/retro.md`. Para cada problema relatado, responda:
- O plano tinha um teste que pegaria isso?
- A avaliação marcou o critério como atendido?

Proponha a regra que teria evitado o retorno (etapa 11). Esse é o aprendizado mais valioso: priorize.

## Revisão do aprendizado (quando o dev pedir ou o script avisar que um arquivo passou do limite)

A página pede a revisão com uma mensagem que começa por `card-sigcon revisao-aprendizado`. Essa conversa é só da revisão: não há card, e ninguém responde depois. Não faça perguntas; grave as propostas e termine. A página mostra tudo o que você escrever, então escreva tudo em português, inclusive o que narrar enquanto trabalha.

1. Leia todos os arquivos de `aprendizado/` (menos o `_propostas.md`, que só serve para não repetir proposta pendente).
2. Procure:
   - regras **duplicadas** (dizem a mesma coisa, mesmo com palavras diferentes);
   - regras **contraditórias** (uma manda o contrário da outra);
   - regras **obsoletas**: a classe, tela, enum ou fluxo citado não existe mais ou mudou. Confirme no repositório do SIGCON (`git -C <repo> grep`, `ls-files`, `log`, com o caminho do repositório que está no seu prompt) antes de chamar de obsoleta.
   - regras que estão na **área errada**.
3. Para cada achado, escreva em `aprendizado/_propostas.md`:
   - **remover:** o cabeçalho leva `tipo: remover`. Em `Regra:` copie o texto da regra **exatamente como está na linha do arquivo**, sem o `- ` do começo e sem o trecho a partir de `_Por quê:_`. O script só remove se esse texto casar com uma linha só.
   - **adicionar:** proposta normal, sem `tipo`. Use `card: revisão` quando a regra não vier de um card.
   - Juntar duplicadas = um `remover` para cada antiga e um `adicionar` com a regra unificada. Mudar de área ou reescrever = `remover` na área antiga e `adicionar` na nova.

   ```
   ## tipo: remover | area: <área> | data: <aaaa-mm-dd>
   Regra: <texto exato da regra, como está no arquivo>
   Por que: <duplicada de "...", contradiz "...", obsoleta porque ...>
   Evidencia: <arquivo:linha no SIGCON, commit, a outra regra>
   ```
4. Termine com um resumo curto: quantas propostas de cada tipo e o motivo de cada uma. Se não achou nada, diga isso e não grave nada.

Nunca edite os arquivos de área: quem remove ou acrescenta é o `card.ps1 aprender`, depois que o dev marca as propostas na aba Aprendizado.

## Regras duras
- **Nunca assine o que vai para o card.** Nada de rodapé, crédito ou menção à ferramenta ou a IA ("gerado com/por", "card-sigcon", "Kiro", "revisado pelo dev", nome de modelo) em `plano.md`, `execucao.md` ou qualquer texto que vá para o GitLab. O comentário é do dev.
- Nunca leia, exiba ou copie o arquivo `.env` nem o valor de `GITLAB_TOKEN`. Se o script disser que o token não está definido, mande o dev seguir o README.
- Não @mencione ninguém no texto do card, e não escreva nome de pessoa nele (homologador, dev, PO): cite o apontamento pela data.
- Não publique sem o "pode publicar" do dev.
- Não invente evidência: se não achou no diff, a situação do critério é `nao_encontrado`.
