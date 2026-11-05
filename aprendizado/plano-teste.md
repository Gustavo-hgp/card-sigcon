# Aprendizado — plano de teste

- Mexeu em classe ou tela compartilhada da alteração de instrumento: o plano inclui a celebração (convênio sem alteração), não só os tipos de alteração. _Por quê:_ em 2026-10-14 a celebração travou em homologação por regressões da alteracao-instrumento/geral, que só tinha sido testada nos fluxos de alteração. (homolog, 2026-10-14)
- Aba de accordion dinâmico: abra a aba com pelo menos um registro. Expressão EL quebrada só estoura quando a aba renderiza com dados. _Por quê:_ `alteracaoSimple` inexistente na aba Interveniente dava PropertyNotFoundException só com interveniente cadastrado. (homolog, 2026-10-14)
- Tela `@ViewScoped` que muda status: faça a ação, saia, volte e reabra o registro; confira botões e abas de novo. _Por quê:_ referências separadas ao mesmo convênio deixam estado velho (erro falso de perfil, botão que não aparece). (alteração, 2026-09)
