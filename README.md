# card-sigcon

Assistente para fechar um card do SIGCON a partir da branch do dev. Roda com o agente do Kiro.

O dev informa o link do card, a branch e a base. A ferramenta então:

1. confere a base e mostra os commits para o dev confirmar;
2. avalia a entrega **por critério de aceite** (atendido / parcial / não atendido / não encontrado / verificar no teste);
3. checa banco de dados em três camadas: sinais no código, julgamento do agente e confirmação do dev;
4. escreve o plano de teste;
5. com o "pode publicar" do dev, comenta o plano no card, cria ou conclui o card filho e, se pedido, muda a coluna;
6. propõe aprendizado, que o dev aceita ou descarta.

**Quem faz o quê.** Tudo o que é regra fixa fica no `card.ps1`: base do diff, camada 1 de banco, regras do card filho, etiquetas e coluna. O agente faz o que precisa de julgamento e nunca chama a API do GitLab diretamente.

## Instalação (uma vez por dev)

**Antes (uma vez por máquina):** Git, Kiro CLI com login feito e as variáveis de proxy (itens 1 e 2 abaixo, e o guia de instalação).

**Depois, são três passos:**
1. **Clone esta ferramenta ao lado do clone do SIGCON**, na mesma pasta-mãe. Por exemplo `C:/prodemge/sigcon/gggt` e `C:/prodemge/sigcon/card-sigcon`, ou `C:/Users/<você>/git/gggt` e `C:/Users/<você>/git/card-sigcon`. A ferramenta procura o SIGCON em `../gggt`. Se o seu clone estiver em outro lugar, informe `CARD_SIGCON_REPO` no `.env`, com barras normais e sem espaços.
2. **Copie `.env.exemplo` para `.env`** e preencha `GITLAB_TOKEN` (item 2 abaixo).
3. **Dê dois cliques em `card-ui.cmd`.**

Ao abrir, a página:
- **gera o agente do Kiro** (`.kiro/agents/card-sigcon.json`) a partir de `.kiro/agente-modelo.json`, com o caminho do SIGCON desta máquina. Ninguém edita o agente na mão. Se o caminho ou o modelo mudarem, ele é gerado de novo;
- **confere a instalação** e, se faltar algo (repositório, token, Kiro, login, proxy), mostra uma faixa no topo dizendo o que fazer.

No terminal, `card.cmd verificar` mostra a mesma lista. Quem usa só o Kiro pela linha de comando roda `card.cmd configurar` uma vez para gerar o agente.

### Detalhes

1. **Kiro CLI** instalado, com login feito:
   - forma de login: "Your Organization";
   - endereço: `https://prodemge002.awsapps.com/start/`;
   - região: `sa-east-1`;
   - comando: `kiro-cli login --use-device-flow`.

   O `kiro-cli` **não usa o proxy do Windows**. Crie no seu usuário as variáveis `HTTPS_PROXY` e `HTTP_PROXY` com o valor `http://proxy.prodemge.gov.br:8080`, e `NO_PROXY` com `localhost,127.0.0.1,::1,.local,.prodemge.gov.br,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,200.198.0.0/18`. Sem elas, o login e o chat travam sem mensagem de erro.
2. **Token do GitLab.** Em `git.prodemge.gov.br` → avatar → *Edit profile* → *Access tokens*, crie um token pessoal:
   - escopo `read_api` para testar (`coletar`, `simular` e `retro` só leem);
   - escopo `api` para publicar.

   O token é seu: o comentário e o card filho saem no seu nome. Guarde de um destes jeitos:
   - **`.env` (mais simples):** copie `.env.exemplo` para `.env`, nesta pasta, e preencha `GITLAB_TOKEN=`.
     - O `.env` está no `.gitignore`.
     - O agente do Kiro tem permissão negada para ler esse arquivo.
     - Não mande o `.env` para ninguém.
   - **Variável de ambiente do usuário:**
     - pelo Windows: "Editar as variáveis de ambiente para sua conta" → Novo → `GITLAB_TOKEN`;
     - ou num PowerShell: `[Environment]::SetEnvironmentVariable('GITLAB_TOKEN', '<cole aqui>', 'User')`.

     O script lê a variável mesmo em terminal aberto antes dela.

   Se o token estiver nos dois lugares, vale a variável de ambiente.
3. **Repositório do SIGCON.** Por padrão, `../gggt` (ao lado desta pasta, `config/config.json` → `repoPadrao`). Em outro lugar, defina `CARD_SIGCON_REPO` no `.env` e reabra o `card-ui.cmd`; o agente é gerado de novo com o caminho certo.

## Uso pela página (recomendado)

Dê dois cliques em **`card-ui.cmd`** (ou rode no terminal). O navegador abre `http://localhost:8765/`. A janela do terminal precisa ficar aberta enquanto você usa a página; Ctrl+C para.

1. **Novo card.** A janela vem com a branch atual do repositório já escolhida.
   - **Card:** ao clicar no campo aparecem os seus cards abertos (atribuídos a você nos projetos do SIGCON de `config.json` → `projetos`: Execução e PC e Alteração de Instrumento), com número, título e coluna. Dá para filtrar por número ou palavras do título, ou digitar o número ou o link de outro card. A prévia mostra o título e a coluna, lidos do GitLab. Escolhido o card, a página procura a branch com o número dele no nome; confira se é a sua, porque uma branch sem o número no nome não é achada.
   - **Branch:** digite um trecho do nome (`1099`, `painel evol`, `extrato`); a lista mostra data, autor e último commit de cada uma. O card também pode sair do nome da branch (`card_1099_...` → 1099).
   - **Base:** cada base conhecida aparece com quantos commits da branch estão fora dela. Base contaminada fica bloqueada, e a recomendada vem marcada:
     - para branch ainda não mergeada, a base de onde ela saiu;
     - para branch já mergeada (ou que recebeu merge de outro card), o último merge antes dos commits do topo que citam o card.

     "Outra" aceita qualquer branch ou commit.

   Clique em **Começar**. A página chama o agente do Kiro, que roda o `coletar` e pergunta se os commits são do card.
2. **Conversa.** As respostas do agente aparecem na aba **Conversa**. Cada resposta leva de 1 a 3 minutos.
   - **Perguntas em destaque.** Quando o agente espera você, as perguntas dele aparecem num painel acima da caixa, cada uma com as opções como botões (marque uma, ou várias quando ele avisar) e um campo para outra resposta ou complemento. **Enviar respostas** manda tudo junto, no formato "pergunta → resposta"; o que você escrever na caixa de baixo vai junto.
   - **Na própria mensagem.** As mesmas perguntas ficam no quadro "Perguntas para você", para não se perderem no histórico.
   - **Como funciona.** O agente termina o turno com um bloco invisível (`<!-- card-sigcon:perguntas [...] -->`, steering `fluxo-card-sigcon.md`). Se ele esquecer o bloco, a página mostra as frases com "?" do fim da mensagem, sem botões.
   - Sem pergunta pendente, a caixa mostra os atalhos de sempre.
3. **Abas.** Mostram o que o agente gravou, à medida que ele grava:
   - **Commits**;
   - **Critérios**;
   - **Avaliação**;
   - **Banco**;
   - **Plano**.

   A lista **Etapas**, na barra lateral, mostra o roteiro do card. Cada etapa tem uma linha de status embaixo e abre a aba dela ao clicar:

   | Etapa | Fica marcada quando | Linha de status |
   |---|---|---|
   | Commits | você respondeu ao agente sobre os commits | "12 commits" |
   | Avaliação | o agente gravou a avaliação por critério | "5 critérios · 1 pendente · 2 a testar" |
   | Banco | o agente gravou o banco | "com mudança de banco" / "sem mudança de banco" |
   | Plano de teste | o plano existe | "7 cenários" |
   | Seus testes (opcional) | você enviou os resultados ao Kiro | "3 de 7 feitos · 2 evidências" |
   | Simular | houve Simular sem erro e nada mudou depois | "aguardando a decisão do agente", "pronto para simular", "ok às 10:15", "desatualizado: simule de novo" |
   | Publicar | publicou depois de começar o card (publicação antiga do mesmo card não conta) | "publicado 29/10, 15:02" |

   - **Etapa marcada implica as anteriores.** Se o plano existe, Commits, Avaliação e Banco aparecem marcados.
   - **A etapa em destaque** é sempre o próximo passo de verdade.
   - **Seus testes** tem contorno tracejado: mostra o progresso, mas não fica em destaque nem segura o Simular.
4. **Testes do dev.** Na aba **Plano**, cada cenário tem:
   - **Feito por mim**;
   - uma caixa de **observação**;
   - **evidências** (fotos e vídeos): botão **Anexar foto ou vídeo**, arrastar o arquivo para o cenário ou colar um print com Ctrl+V na observação (Win+Shift+S recorta a tela). Aceita `.png`, `.jpg`, `.gif`, `.webp`, `.mp4`, `.webm` e `.mov`, até 50 MB por arquivo (`config.json` → `evidencias`). Clique na miniatura para ver grande; o × remove.

   As marcações ficam em `out/<card>/execucao-testes.json` e as evidências em `out/<card>/evidencias/cenario-<N>/`, salvas na hora. No Publicar, as evidências sobem para o GitLab e entram no comentário no fim de cada cenário; publicar de novo não reenvia o mesmo arquivo. A SEGOV lê o card: evite print com dado pessoal (CPF, conta, nome) sem necessidade. Arquivo enviado ao GitLab continua lá mesmo se sair do comentário.

   Quando terminar, clique em **Enviar resultados ao Kiro**. O agente então:
   - escreve a seção "Execução pelo dev" em `out/<card>/execucao.md`, com o resumo, a tabela por cenário e as observações reescritas em tom profissional;
   - ajusta a avaliação e a decisão se alguma observação indicar falha.

   O `card.ps1` coloca essa seção no comentário do card antes do primeiro cenário, e a página mostra a seção no mesmo lugar, marcada "vai no card".
5. **Publicar.** Quando o agente gravar a decisão, use a aba **Publicar**:
   - escolha as opções:
     - **Mover para:** a lista traz as colunas do quadro a que o card pertence, lidas do GitLab, com a coluna atual desabilitada. "Não mover" deixa o card onde está;
     - card filho (a atividade vem da coluna atual; dá para trocar ou não criar).
   - clique em **Simular**;
   - confira a saída e, em **Pré-visualizar comentário**, veja o texto renderizado como no GitLab (há também **Copiar markdown**);
   - **para mudar o texto**, clique em **Editar** no comentário (ou na nota interna) da pré-visualização, mude o markdown e **Salvar**. O texto ganha o selo "editado por você", e é ele que o Publicar grava. **Voltar ao texto gerado** desfaz;
   - só então clique em **Publicar no GitLab**.

   O Publicar fica bloqueado:
   - se não houve Simular sem erro com as mesmas opções;
   - se o plano ou a decisão mudaram depois do Simular;
   - se o agente gerou outro texto depois da sua edição. A pré-visualização avisa; salve de novo, ou volte ao texto gerado.

   A edição fica em `out/<card>/<texto>.editado.md`, ao lado do texto gerado, que continua igual.
6. **Aprendizado.** Na aba **Aprendizado**, marque as regras que o agente propôs e grave ou descarte.
   - Proposta com o selo **remover** tira uma regra que já está no arquivo da área; as outras acrescentam.
   - Proposta com problema (área sem arquivo, regra a remover que não está mais lá) aparece com o motivo em vermelho. Dá para descartar; o Gravar recusa e não grava nenhuma das marcadas.
   - **Pedir revisão ao Kiro:** o agente lê todas as regras e o código e propõe tirar as duplicadas, contraditórias ou obsoletas (com a regra nova no lugar, quando for o caso). Roda numa conversa à parte, apagada no fim, sem mexer no card aberto; o resultado aparece no próprio cartão e as propostas entram na lista acima. Use quando o script avisar que um arquivo passou do limite de linhas.

Como funciona por dentro:
- `ui/servidor.ps1` é um servidor PowerShell que só escuta em `localhost`. Toda chamada que grava exige um token gerado a cada execução e embutido na página, então outro site aberto no navegador não consegue disparar nada.
- Cada turno do Kiro roda em segundo plano (`ui/executar.ps1`) com `kiro-cli chat --agent card-sigcon --no-interactive --resume-id <sessão>`. A página guarda o id da sessão de cada card, porque o `--resume` simples retoma a conversa mais recente da pasta, que pode ser outra.
- Os logs de cada turno ficam em `out/<projeto>-<n>/ui/`; os da revisão do aprendizado, em `out/_aprendizado/ui/`.
- O agente só lê o repositório do SIGCON e esta pasta, nunca o `.env` (`.kiro/agents/card-sigcon.json` → `toolsSettings.read`). No modo da página o Kiro não pergunta: o que está fora da lista liberada é negado e aparece como "ação bloqueada" na conversa.
- Começar o mesmo card de novo move o contexto e os arquivos do agente para `out/<projeto>-<n>/anteriores/`.
- Porta ocupada: `card-ui.cmd -Porta 8766`.

**Créditos do Kiro.** A página mostra quanto o Kiro gastou:
- em cada resposta, na conversa (ex.: "1,2 créditos");
- no card, no topo da página (soma de todas as conversas dele);
- no mês, na barra lateral ("Consumo do Kiro");
- na última revisão do aprendizado, na aba Aprendizado.

Como funciona:
- Depois de cada turno, o `ui/executar.ps1` lê o consumo na sessão do Kiro (`%USERPROFILE%\.kiro\sessions\cli\<sessão>.json`). O Kiro grava esse valor alguns segundos depois de terminar, então o executor espera até 10 s.
- Cada turno vira uma linha em `out/ui-estado.creditos.jsonl`, que a limpeza não apaga.
- Na primeira vez, a página importa o consumo das conversas do card-sigcon que ainda existiam.
- Só conta o que passa pela página: conversa aberta direto no `kiro-cli` fica de fora.
- O saldo da licença no mês sai no `kiro-cli chat`, com o comando `/usage`.
- O consumo vem de um arquivo interno do Kiro. Se uma atualização mudar o formato, a página só deixa de mostrar o custo.

Um card costuma custar de 3 a 13 créditos; cada resposta, de 0,4 a 2,5.

## Uso com o Kiro

**CLI.** Abra o terminal nesta pasta e rode:

```
kiro-cli chat --agent card-sigcon
```

Depois passe ao agente:
- o link do card;
- a branch;
- a base de onde a branch saiu.

**IDE.** Abra esta pasta no Kiro e, no chat, chame `#fluxo-card-sigcon`, passando o link do card, a branch e a base.

O agente segue `.kiro/steering/fluxo-card-sigcon.md`:

1. coletar;
2. confirmar os commits;
3. confirmar os critérios;
4. avaliar;
5. banco (com as suas respostas);
6. plano;
7. simular;
8. publicar (só com o seu "pode publicar");
9. aprendizado.

Na primeira vez que o agente rodar `publicar`, o Kiro pede a sua permissão.

## Avaliação técnica (antes do desenvolvimento)

Para os cards da coluna "Avaliação Técnica": o agente estima impacto, riscos e pontos a partir da HU, da wiki e do código atual, e quem avalia aprova.

1. **Começar.** Na barra lateral, botão **Avaliação técnica** (ao lado de "Atualizar wiki"). Escolha o card e a **branch de referência**: a branch com o código atual do módulo. Há sugestões (`config.json` → `avaliacao.referencias`); a Visita Técnica, por exemplo, não está no master, só na geral-merge. Não há base nem branch do card.
2. **Conversa.** O agente roda `card.cmd avaliar`, lê a HU, os comentários, as páginas da wiki e o código **no commit da referência**, e pergunta se o escopo está certo.
3. **Impacto, riscos e estimativa.**
   - **Impacto:** telas, classes, tabelas e relatórios, cada um como novo ou alteração, com o arquivo.
   - **Riscos e dependências:** classes compartilhadas, cards ligados, conflito com a wiki.
   - **Estimativa:** o agente sugere os pontos na escala do quadro, comparando com as avaliações técnicas anteriores do projeto. Você aprova ou escolhe outro valor.
4. **Publicar.** Na aba Publicar, **Pontos do card** vem com o valor aprovado (dá para trocar), e **Mover o card para** vem com "2 - Pronto para Execução" (`avaliacao.colunaDestino`). O Simular mostra as ações; o Publicar:
   - grava a avaliação como **nota interna** (só a equipe vê; publicar de novo atualiza a mesma nota);
   - troca a etiqueta de pontos do card pela aprovada;
   - conclui o card filho "Avaliação Técnica" pela regra da DSG, já com os pontos aprovados;
   - move o card de coluna;
   - guarda a avaliação em `historico/<projeto>-<n>-avaliacao.md`.
5. **Depois.** Quando o card for desenvolvido e fechado pelo fluxo normal, o coletar traz a nota da avaliação nos comentários, e o agente aponta o que saiu diferente do previsto (vira aprendizado na área `avaliacao-tecnica`).

As etapas da barra lateral mudam neste modo: Card e referência, Escopo, Impacto e riscos, Estimativa, Simular, Publicar. As abas Commits, Banco e Plano somem, e o topo mostra o selo "Avaliação técnica". Os arquivos ficam em `out/<projeto>-<n>-avaliacao/`, separados do desenvolvimento do mesmo card.

Um primeiro turno real (coletar + escopo) custou 3,6 créditos.

## Wiki do sistema

A regra de negócio documentada do SIGCON fica na wiki do projeto `documentacao-sigcon` no GitLab (cerca de 1.100 páginas). O agente consulta uma cópia local em `wiki/`:
- **Uma página por arquivo**, com o título e o link da página original. O índice fica em `wiki/_indice.md`.
- **O coletar aponta as páginas do card** na seção "Wiki" do `contexto.md`. Vêm primeiro as que o próprio card cita por link, depois as cujo título o card cita e por último as que têm a maioria das palavras do título no card. O agente lê essas páginas e procura outras telas com grep.
- **O agente só lê.** Divergência entre HU, wiki e código vira pergunta para você e nota na avaliação. HU reescrita ou decisão em comentário vale mais que a wiki.
- **Atualização:**
  - sozinha, no coletar, quando a cópia tem mais de 24 horas (`config.json` → `wiki.horasValidade`);
  - na hora, pelo botão **Atualizar wiki** na barra lateral da página ou com `card.cmd wiki -Forcar`. Leva uns 10 segundos.
- **Acesso:** o token precisa enxergar o projeto `documentacao-sigcon`; o escopo `read_api` basta.

## Comandos do script (também funcionam sem o Kiro)

| Comando | O que faz |
|---|---|
| `card.cmd coletar -Card <link> -Branch <branch> -Base <base>` | Gera `out/<projeto>-<n>/contexto.md`, `contexto.json` e `diff.txt`. Para se a branch estiver contaminada (contém o `fce77c7aaf` e a base não). Opções: `-SemGitlab` (só git), `-SemFetch`, `-Repo <dir>`. |
| `card.cmd simular -Card <link>` | Mostra as ações que o `publicar` faria. Não grava nada. |
| `card.cmd publicar -Card <link>` | Grava no GitLab. Opções: `-Coluna "<nome>"` (qualquer coluna do quadro do card), `-Mover` (atalho antigo para "Processo Merge / Publicação"), `-Atividade "<nome>"`, `-SemFilho`, `-NovoFilho`. |
| `card.cmd retro -Card <link>` | Junta os comentários feitos depois do plano (retorno de homologação, QA) em `out/.../retro.md` para o agente achar o que o plano deixou passar. |
| `card.cmd propostas` | Lista as propostas de aprendizado pendentes. |
| `card.cmd aprender -Aceitar 1,3 -Descartar 2` | Aplica as aceitas em `aprendizado/<area>.md` (acrescenta a regra, ou tira a linha nas de `tipo: remover`) e apaga as descartadas. Se uma aceita não confere, nada é gravado. |
| `card.cmd limpar [-Dias 60] [-SoListar]` | Apaga o que não é usado há N dias (veja "Armazenamento"). `-SoListar` só mostra o que sairia. |
| `card.cmd verificar` | Diz o que falta nesta máquina: repositório do SIGCON, git, token, proxy, Kiro, login do Kiro e agente gerado. |
| `card.cmd configurar` | Gera o agente do Kiro com o caminho do SIGCON desta máquina e verifica. A página faz isso sozinha ao abrir. |
| `card.cmd wiki [-Forcar]` | Baixa a wiki do sistema para `wiki/` se a cópia tiver mais de 24 horas; com `-Forcar`, baixa na hora. |
| `card.cmd avaliar -Card <link> -Ref <branch>` | Avaliação técnica: gera `out/<projeto>-<n>-avaliacao/contexto.md` com HU, comentários, wiki, escala de pontos e avaliações anteriores do projeto. |
| `card.cmd simular-avaliacao -Card <link>` | Mostra o que o `publicar-avaliacao` faria. Opções: `-Pontos <n>`, `-Coluna "<nome>"`, `-SemFilho`, `-NovoFilho`. |
| `card.cmd publicar-avaliacao -Card <link>` | Grava a avaliação como nota interna, troca a etiqueta de pontos, conclui o filho "Avaliação Técnica" e move o card. Mesmas opções. |

`<link>` aceita a URL do card, `#1237` ou `1237` (projeto padrão: Execução e Prestação de Contas).

## Regras aplicadas pelo `publicar`

**Comentário do plano.** Vai no card pai, com a lista de critérios cobertos. A avaliação **não** vai no comentário, porque o card é visível para a SEGOV. Rodar de novo atualiza o mesmo comentário em vez de criar outro.

**Card filho** (regra da DSG, a mesma em todos os quadros):
- A atividade vem da coluna atual (`config.json` → `quadro.atividadePorColuna`):
  - "4 - Em Execução" e "Em Ajustes" → Desenvolvimento;
  - "Homologação - Correções" → Retornos de Homologação.
- O filho é criado com:
  - título `#<título do pai> – <Atividade>`;
  - só a etiqueta de pontos do pai e `feito`;
  - o milestone do pai;
  - você como responsável;
  - ligação `relates_to` ao pai;
  - e já fechado.
- Se já existe um filho dessa atividade aberto, o script só põe `feito` e fecha. Se já existe fechado, não faz nada.

**Etiqueta "Mudança em Banco de Dados".** Vai no pai quando o `decisao.json` diz que há mudança de banco confirmada pelo dev.

**SQL do banco (nota interna).** Com mudança de banco, o SQL vai no card como **nota interna**, que só membros do projeto veem (quem é só convidado, não). A nota abre com a observação de banco do `decisao.json` e traz cada script de `banco.scripts`:
- o arquivo é lido da branch (o que vai para produção). Se não estiver commitado, vai a versão da pasta do repositório, com aviso;
- o SQL que você passou ao agente na conversa, sem arquivo, fica em `out/<card>/banco.sql` e também entra;
- publicar de novo atualiza a mesma nota.

**Evidências.** As fotos e vídeos dos cenários sobem antes do comentário (API de uploads do projeto) e entram no fim de cada cenário. `out/<card>/evidencias-gitlab.json` guarda o que já foi enviado.

**Mudar de coluna.** Só com `-Coluna` (a lista "Mover para" da página) ou `-Mover`:
- `-Coluna "<nome>"`: o script lê o quadro do card no GitLab (o quadro cujas colunas contêm a etiqueta de coluna atual do card) e recusa nome que não seja coluna dele. Tira as etiquetas de coluna antigas e põe a nova, porque no GitLab coluna é etiqueta;
- `-Mover`: leva para "Processo Merge / Publicação", só se o card estiver numa das colunas de `quadro.moverSomenteDe` ("4 - Em Execução", "Em Ajustes" ou "Homologação - Correções");
- nos dois casos, recusa se houver critério pendente sem `justificativaPendencias`.

## Pastas

| Pasta | Conteúdo | Versionada? |
|---|---|---|
| `config/config.json` | Colunas, atividades, padrões de banco, áreas, classes compartilhadas e os textos com acento | sim |
| `.kiro/` | Modelo do agente (`agente-modelo.json`) e steering (domínio, fluxo, plano/avaliação, avaliação técnica) | sim; o agente gerado (`.kiro/agents/card-sigcon.json`) não, porque é de cada máquina |
| `ui/` | Página local (`servidor.ps1`, `executar.ps1`, `index.html`, `app.js`, `app.css`) | sim |
| `ui/public/` | Imagens servidas em `/public/...`: o logo original, `logo-simbolo.png` (recorte do símbolo, fundo transparente, usado no cabeçalho) e `favicon.png` | sim |
| `aprendizado/` | Regras aceitas por área e propostas pendentes | sim, compartilhada pelos devs por MR |
| `historico/` | Plano e avaliação de cada card publicado; viram exemplo para cards da mesma área | sim |
| `out/` | Trabalho de cada execução | não (`.gitignore`) |
| `wiki/` | Cópia local da wiki do sistema, só leitura para o agente | não (`.gitignore`): cada dev baixa a sua |

## Armazenamento

Cada card ocupa de 0,5 a 1 MB:
- **`out/<card>`:** o `diff.txt` é o maior arquivo, de 150 a 200 KB num card médio. Evidências somam o tamanho delas (vídeo pode passar de 10 MB).
- **Conversa do Kiro:** cerca de 250 KB, em `%USERPROFILE%\.kiro\sessions`.

A instalação do Kiro (cerca de 650 MB) não cresce com o uso. A cópia da wiki ocupa cerca de 8 MB e é substituída a cada atualização, sem crescer.

**Limpeza automática:** ao abrir a página (`card-ui.cmd`), e também com `card.cmd limpar`, sai o que está sem uso há mais de 60 dias:
- a pasta `out/<card>` cujo arquivo mais recente tem mais de 60 dias, exceto o card aberto na página;
- nos cards que ficam, as cópias antigas em `anteriores/` e os logs de turno antigos;
- as conversas do Kiro abertas na pasta da ferramenta e paradas há mais de 60 dias, exceto a do card aberto.

**Nunca apaga:** `historico/` e `aprendizado/`, que são do time e vão para o git.

**Configuração:** em `config/config.json` → `limpeza`:
- `dias`: o prazo;
- `aoAbrirPagina`: `false` desliga a limpeza automática.

## Cuidados

- **Encoding.** Os `.ps1` ficam em UTF-8 **com BOM**: sem o BOM, o PowerShell 5.1 lê o arquivo como ANSI e estraga os acentos das mensagens. Ao editar, use um editor que mantenha o BOM (VS Code mostra "UTF-8 with BOM" na barra de status). Os `.md`, `.json`, `.html`, `.js` e `.css` ficam em UTF-8 sem BOM. O `.gitattributes` (`* -text`) impede o git de converter qualquer coisa.
- **Mudar o agente.** Edite `.kiro/agente-modelo.json` (com `{{REPO}}` onde vai o caminho do SIGCON), não `.kiro/agents/card-sigcon.json`, que é gerado. Na próxima abertura da página, ou com `card.cmd configurar`, ele é gerado de novo.
- **Antivírus.** O antivírus da Prodemge bloqueia um `.ps1` que tenha texto montando comandos de git (exemplo dentro de uma string). Exemplos de comando ficam nos `.md` do steering.
- **Formato do título do filho.** Confira no primeiro uso. O formato vem da regra combinada em out/2026 e está em `config.json` → `textos.tituloFilho`. O `simular` mostra o título antes de gravar.
- **Etiquetas.** As etiquetas da config estão sem acento. O script acha a etiqueta real no projeto comparando sem acento.
- **Variáveis para teste.** `CARD_SIGCON_GITLAB_URL` aponta o script para outro GitLab (por exemplo, um GitLab falso local).
