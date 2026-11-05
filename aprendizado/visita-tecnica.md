# Aprendizado — Visita Técnica In Loco

- Toda troca de status da solicitação grava `USUARIO_ALTERACAO` junto; no plano, confira na auditoria se a troca ficou no nome de quem fez. _Por quê:_ a trigger `TR_V2_MT_SOLICITACAO_VT` grava a auditoria com `:new.USUARIO_ALTERACAO`; sem ele a troca fica no nome de quem mexeu antes. (visita técnica, 2026-10-14)
- Teste com uma solicitação de dois instrumentos: o status é da solicitação, mas rota, relatório e "Não executada" são por instrumento. _Por quê:_ pôr só um instrumento numa rota levava a solicitação inteira para Em Rota e escondia o outro do mapa. (#1100, 2026-10-08)
