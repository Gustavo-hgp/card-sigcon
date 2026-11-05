---
inclusion: manual
---

# Avaliação técnica (card-sigcon)

Use este roteiro, e não o fluxo de fechamento, quando a primeira mensagem disser **"Avaliação técnica"**. O card ainda não foi desenvolvido: não há branch do card nem diff. Você avalia o que a HU pede contra o código **de hoje** de uma branch de referência que o dev escolheu, e o Danilo (ou o dev que avalia) aprova.

Comando base (rode sempre da raiz desta pasta):

```
powershell -NoProfile -ExecutionPolicy Bypass -File ./card.ps1 <comando> ...
```

## Etapas

1. **Coletar.** Rode `./card.ps1 avaliar -Card "<link>" -Ref "<referência>"`. Se terminar com `ERRO:`, mostre a mensagem e pare. O script grava `out/<pasta>/contexto.md` (a pasta termina em `-avaliacao`).

2. **Ler.** Leia o `contexto.md` inteiro: HU, comentários, cards ligados, páginas da wiki listadas, escala de pontos, avaliações anteriores e aprendizado.
   - **Código: sempre no commit da referência** que está no contexto, nunca pelo arquivo da pasta do repositório (ela pode estar em outra branch). `<repo>` abaixo é o caminho do repositório do SIGCON desta máquina (está no seu prompt e na linha "Repositorio" do contexto); escreva-o exatamente assim, senão o comando é negado. Use:
     - `git -C <repo> show <commit>:<caminho do arquivo>` para ler um arquivo;
     - `git -C <repo> grep -n "<termo>" <commit> -- <pasta>` para procurar;
     - `git -C <repo> ls-tree -r --name-only <commit> -- <pasta>` para listar arquivos;
     - `git -C <repo> log --oneline -15 <commit> -- <caminho>` para ver quem mexeu por último.
   - **Saída curta sempre.** O Kiro para de ler a saída de um comando depois de um limite, e um `git grep` com milhares de linhas trava o turno. Comece com `-l` (só os arquivos) ou `-c` (contagem), limite com `-m 5` (no máximo 5 linhas por arquivo), restrinja a pasta (`-- JavaSource/br/gov/prodemge/sigcon/bo`) e evite palavras genéricas ("complementar", "lista"). Não encadeie comandos com `|` (`| head`, `| sed`): é negado; limite pelo próprio git.
   - **Wiki:** leia as páginas listadas e procure outras telas citadas na HU em `wiki/` (índice em `wiki/_indice.md`). HU reescrita ou decisão em comentário vale mais que a wiki.

3. **Escopo.** Resuma em poucas linhas o que a HU pede, liste os critérios de aceite e as dúvidas que encontrou (HU ambígua, conflito com a wiki, regra faltando). Pergunte ao dev: **"o escopo é esse?"** Não siga sem a confirmação. As perguntas vão no bloco `card-sigcon:perguntas` (formato em `fluxo-card-sigcon.md`, "Perguntas para o dev"), por exemplo `{"pergunta": "O escopo é esse?", "opcoes": ["Sim, pode seguir", "Quase: vou corrigir", "Não, vou explicar"]}`, mais uma pergunta para cada dúvida da HU.

4. **Impacto.** Para cada camada, diga se é **novo** ou **alteração**, o arquivo (na referência) e o que muda:
   - telas (`.xhtml`) e menu/permissões (`LoginBean`, `componenteMenu*.xhtml`, `faces-config.xml`);
   - beans, BOs, DAOs, entidades (`model`), enums;
   - relatórios (`.jrxml`/Jasper) e documentos por template (`$T{...}`);
   - **banco de dados**: tabelas e colunas novas, dados de domínio (`TX_...` que espelham enum), views, scripts necessários. Diga se precisa de script e o que ele faria; não escreva o SQL.
   Siga os padrões do domínio (steering `dominio-sigcon.md`): rodapé migrado, DO é espécie de AS, quatro enums parecidos na visita técnica, e assim por diante. Se não achou algo na referência, escreva "não encontrado na referência"; não invente.

5. **Riscos e dependências.**
   - Classes compartilhadas (lista no contexto): mexer nelas exige regressão em outros fluxos.
   - Cards ligados ou abertos que mexem nas mesmas telas/classes (`git log` na referência ajuda).
   - Conflito entre a HU e a regra da wiki, perfis e permissões, migração de dados existentes, integração externa (ProECM, assinatura, GRP/SIAFI, API do BB).
   - Se o módulo não está na referência escolhida (ex.: Visita Técnica não está no master), avise o dev logo.

6. **Estimativa.** Use a escala de pontos do contexto (etiquetas do quadro). Compare com as avaliações anteriores da tabela do contexto: cite 1 a 3 cards parecidos e os pontos deles. Sugira **um** valor e justifique em 2 a 3 linhas (o que pesa: telas novas, banco, classe compartilhada, regra complexa). Pergunte ao dev: **"aprova N pontos ou prefere outro valor?"** No bloco de perguntas, as opções são os valores da escala, com o sugerido primeiro: `{"pergunta": "Aprova 3 pontos?", "opcoes": ["Sim, 3 pontos", "2 pontos", "5 pontos", "Outro valor"]}`.

7. **Gravar.** Depois da resposta do dev sobre os pontos:
   - `out/<pasta>/avaliacao-tecnica.md` no formato abaixo;
   - `out/<pasta>/decisao-avaliacao.json`: `{"pontos": 3, "justificativa": "...", "confirmadoPeloDev": true}`. `confirmadoPeloDev` só é `true` depois que o dev aprovou ou escolheu o valor; use o valor que ele escolheu.

8. **Pare.** Diga que os arquivos estão prontos e que o dev usa **Simular** e **Publicar** na página. O Publicar grava a avaliação como **nota interna**, põe a etiqueta de pontos aprovada, conclui o card filho "Avaliação Técnica" e move o card (padrão: "2 - Pronto para Execução"). Não rode `publicar-avaliacao`.

Se o dev corrigir algo relevante (impacto que você não viu, estimativa muito fora), proponha aprendizado na área `avaliacao-tecnica`, como no fluxo normal (etapa 11 de `fluxo-card-sigcon.md`).

## Formato do `avaliacao-tecnica.md`

É uma **nota interna** (só a equipe vê): pode ter nome de classe, arquivo e tabela. Português correto, com acentos. Sem assinatura, rodapé ou menção à ferramenta ou a IA.

```
## Avaliação técnica

**Escopo:** <2 a 4 linhas do que a HU pede, como o dev confirmou>
**Código de referência:** <branch> (commit <10 caracteres>)

### Impacto
| Camada | Arquivo | Novo/alteração | O que muda |
|---|---|---|---|

### Banco de dados
<tabelas/colunas/dados de domínio; precisa de script? qual o objetivo dele. Ou "sem mudança de banco">

### Riscos e dependências
- ...

### Dúvidas para a PO
- ... (ou "nenhuma")

### Estimativa
**<N> pontos (<etiqueta>)** — <justificativa em 2 a 3 linhas, citando cards parecidos>
```
