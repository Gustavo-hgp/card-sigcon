# #36 - [HU] A5 Rescisão – Substituir o "Cancelamento" por "Rescisão" após o Instrumento Jurídico cadastrado – #36

areas: 
data: 2026-10-23
branch: feature/alteracao-instrumento/geral | base: feature/alteracao-instrumento/geral | commit: f5c5109291
banco: não 

## Avaliação por critério

| CA | situação | teste | critério |
|---|---|---|---|
| CA1 | atendido |  | No combobox "Tipo da Alteração" da seção "Cadastrar Alteração" da aba "Alterações do Convênio/Parceria" do Instrumento Jurídico, a opção "Cancelamento do Convên... |
| CA2 | atendido |  | A nova opção deverá ser habilitada para usuários internos do Concedente/Estado com o perfil "Analista Técnico". |
| CA3 | atendido |  | O Plano de Trabalho deverá continuar podendo ser cancelado, por meio do botão "Cancelar Plano", até a publicação do extrato do Instrumento Jurídico. |

## Plano publicado

### Retorno de homologação — CA3 (botão "Cancelar Plano")

Sobre o apontamento de que o botão "Cancelar Plano" não apareceu no Plano de Trabalho 005179/2026:

O comportamento está correto e não houve alteração de código neste item. A exibição do botão "Cancelar Plano" segue a regra já vigente: o botão só é apresentado para o perfil **Encaminhador**, e apenas enquanto o Plano de Trabalho ainda não foi cancelado nem teve o extrato do Instrumento Jurídico publicado.

No teste relatado, o Plano foi acessado com um usuário de perfil **Analista Técnico**, para o qual o botão não é exibido. Por isso o botão não apareceu.

**Como reproduzir corretamente:** acessar o Plano de Trabalho com um usuário de perfil **Encaminhador**, com o Plano ainda não cancelado e o extrato ainda não publicado. Nessa condição o botão "Cancelar Plano" é exibido e permite o cancelamento, conforme o critério.
