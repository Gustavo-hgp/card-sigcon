# Aprendizado — geral

Regras aceitas pelos devs. Cada linha: regra, por quê, card de origem e data. Para mudar, proponha em `_propostas.md`.

- HU reescrita ou decisão registrada em comentário vale mais que a descrição original: leia os comentários antes de fechar a lista de critérios. _Por quê:_ a HU do #1099 foi reescrita em 08/10 e mudou o escopo. (#1099, 2026-10-08)
- Em laço que define um flag booleano sobre uma lista (ex.: `lancamentoEncaminhado`), confira se o flag não é sobrescrito a cada volta: o certo é acumular com OU ou dar `break` na primeira ocorrência, senão só o último item vale. _Por quê:_ no #1238 o encaminhamento guardava só o resultado da última operação do laço; o card corrigiu com `break` na primeira operação já encaminhada. (#1238, 2026-10-26)
