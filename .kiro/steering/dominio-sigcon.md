---
inclusion: always
---

# SIGCON — o que você precisa saber para avaliar um card

Você **não edita** o código do SIGCON. Você lê o diff de uma branch, a HU do card e escreve a avaliação por critério e o plano de teste. Responda sempre em português.

## Stack e onde as coisas ficam
- Java 8, WAR `sigconv2` (Tomcat 9), JSF 2.2 (Mojarra) + PrimeFaces, Hibernate/JPA sobre Oracle, JasperReports.
- `JavaSource/br/gov/prodemge/sigcon/`: `bean` (JSF, `@ViewScoped`) → `bo` (regra de negócio) → `dao` → `model` (entidades); `enums`, `vo`, `util`, `component`, `bundle/messages_pt_BR.properties`.
- Telas em `WebContent/pages/<Modulo>/*.xhtml`. Navegação (outcome → xhtml) em `WEB-INF/faces-config.xml`.
- Módulo de Execução / Prestação de Contas: telas em `pages/Monitoramento/` (sim, essa pasta), menu em `templates/componenteMenuRegistroExecucao.xhtml`, Jasper em `relatorios/registroExecucao/`.
- Alterações de instrumento: `pages/PropostaPlanoTrabalho/propostaPlanoTrabalho.xhtml` + `pages/AlteracaoDeConvenio/`.

## Limites da verificação (use no plano de teste)
- Não há testes automatizados. Compilar não prova que a tela funciona: expressão EL (`#{bean.x}`) só resolve em tempo de execução. Todo `#{...}` novo ou alterado no xhtml precisa de um passo de tela que o exercite.
- O teste é manual, no Tomcat local ou em homologação, contra o banco. O plano tem que dizer **perfil, órgão, status do registro, tela, botão, resultado esperado**.
- Assinatura e geração de documento são síncronas e lentas ("Processando..." longo) — não é bug por si só.

## Encoding (vale para os alertas do script)
- `.java` é Cp1252; `.xhtml` é UTF-8 sem BOM com CRLF. Acento quebrado (`Ã§`, `�`) num diff costuma ser arquivo regravado no encoding errado — isso é bug, mesmo que compile.
- Arquivo inteiro aparecendo como alterado no diff quase sempre é quebra de linha ou encoding trocados.

## Domínio — alterações de instrumento (convênio/parceria)
- `TipoAlteracaoEnum`: AS=1 Alteração Simples, DO=2 Dotação Orçamentária, TA=3 Termo Aditivo, RC=13 Rescisão (há outros). **DO é espécie de AS.**
- Status (`StatusConvenioEnum`): 24 cadastramento → 28 análise técnica → [31/32/33 Segov] → 34 assinatura concedente → [54 convenente → 63 interveniente] → 39 publicação → vigente.
- Documento assinado na alteração = `TipoDocumentoEnum.ALTERACAO_CONVENIO` (210); 183 = APOSTILAMENTO. Versões ficam no ProECM.
- Classes centrais são compartilhadas por todos os tipos de alteração **e pela celebração** (`PropostaPlanoTrabalhoBean`, `PropostaPlanoDeTrabalhoBO`, `AnaliseTecnicaAlteracaoBean`, `TimelineAlteracaoComponent`, `ComparadorConvenioUtil`, `StatusInstrumentoJuridicoBO`, `AssinaturaBO`). Mexeu nelas ⇒ regressão de outro tipo e da celebração no plano.
- Botões por tipo seguem o padrão "rodapé migrado" (`isRodape<Tipo>Migrado()`); status novo num tipo sem estender o rodapé e o dropdown de retorno ⇒ o tipo fica sem botão de saída.
- Perfis que mais aparecem nos testes (`PerfilEnum` / `TX_V2_PERFIL`): 1 Cadastrador, 3 Encaminhador, 9 Analista Técnico. Na rescisão, quem cria é o Analista Técnico interno do concedente; "Cancelar Plano" é só do Encaminhador; o "Salvar e Encaminhar" da rescisão exigia Cadastrador até o retorno do #37.
- Abas de identificação dos partícipes (Concedente, Convenente, Interveniente): a celebração usa as abas do redesign; a tela de alteração usa as cópias `abaIdentificacaoDo<Partícipe>Classico.xhtml` (existem na `alteracao-instrumento/geral` e no `homologacao`; no `master`, ainda não, em 2026-10-28). Mudança funcional nessas abas tem que ir nas duas versões, e o teste passa pelas duas telas.

## Domínio — Execução / Visita Técnica In Loco
- Solicitação: `SolicitacaoVisitaTecnica` (`TB_V2_MT_SOLICITACAO_VT`) 1:N `SolicitacaoVisitaTecnicaConvenio` (`TB_V2_MT_SOLICITA_CONVENIO_VT`). Órgão concedente = `convenio.orgaoConvenio.orgao`.
- **Quatro enums de status parecidos**: `StatusSolicitacaoVisitaTecnicaEnum` (solicitação), `StatusVisitaTecnicaEnum` (relatório de visita), `StatusRotaEnum` (rota), `SituacaoVisitaTecnicaEnum` (obra). Confira qual o código usa antes de escrever o teste.
- Na solicitação, a ordem do fluxo não é a ordem dos ids: 1 Cadastramento → 3 Assinada → 2 Solicitada → 6 Em Rota → 7 Em Elaboração / 8 Não executada → 9 Realizada.
- Uma solicitação pode ter vários instrumentos, mas o status é um só (na solicitação); rota, relatório e "Não executada" são por instrumento.
- Restrição por órgão nas pesquisas: `EXISTS UsuarioPerfil` com `perfilUsuario.orgao = órgão do convênio`. Permissões do menu ficam no `LoginBean` (`isPermissao...`).
- Mapas (rotas / convênios) são Leaflet com JSON montado nos BOs (`PlanejamentoRotasBO`, `ConvenioMapaBO`) + `resources/js/mapa-*.js`.

## Armadilhas que viram bug de homologação
- `@ViewScoped` com referências separadas ao mesmo `Convenio` → estado velho, erro falso de perfil, botão que não aparece. Teste: fazer a ação, voltar e reabrir a tela.
- Listas de versões/documentos: confira o `ORDER BY` antes de confiar em `get(0)` (várias consultas devolvem a versão mais antiga primeiro).
- Validador de status/perfil com lista negra deixa tipo novo passar por omissão; prefira testar um tipo que **não** deveria passar.
- `update=` ou `process=` apontando para um id que não existe na tela: o PrimeFaces lança exceção ao renderizar o botão, e a aba (accordion dinâmico) aparece **cortada logo antes dele**, sem erro visível. Diff que remove, renomeia ou move um componente com id: o plano abre cada aba que o referencia e confere que ela vai até o último botão.
