<#
card-sigcon: fecha um card do SIGCON a partir da branch do dev.
O script cuida do que e regra fixa (base do diff, banco camada 1, card filho, etiquetas,
coluna); o agente do Kiro escreve a avaliacao por criterio e o plano de teste.

Uso (dentro desta pasta; card.cmd chama este script):
  card.cmd coletar   -Card <link> -Branch <branch> -Base <base> [-Repo <dir>] [-SemGitlab] [-SemFetch]
  card.cmd simular   -Card <link> [-Coluna <nome>] [-Mover] [-Atividade <nome>] [-SemFilho] [-NovoFilho]
  card.cmd publicar  -Card <link> [mesmas opcoes do simular]
  card.cmd retro     -Card <link>
  card.cmd propostas
  card.cmd aprender  [-Aceitar 1,3] [-Descartar 2]
  card.cmd limpar    [-Dias 60] [-SoListar]
  card.cmd wiki      [-Forcar]
  card.cmd verificar           (o que falta instalar ou configurar nesta máquina)
  card.cmd configurar          (gera o agente do Kiro com o caminho do repositório e verifica)
Avaliação técnica (antes do desenvolvimento; sem branch do card):
  card.cmd avaliar             -Card <link> -Ref <branch com o código atual> [-Repo <dir>] [-SemFetch]
  card.cmd simular-avaliacao   -Card <link> [-Pontos <n>] [-Coluna <nome>] [-SemFilho] [-NovoFilho]
  card.cmd publicar-avaliacao  -Card <link> [mesmas opcoes do simular-avaliacao]

Salvo em UTF-8 com BOM: sem o BOM o PowerShell 5.1 le o arquivo como ANSI e estraga os acentos.
#>
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet('coletar', 'simular', 'publicar', 'retro', 'propostas', 'aprender', 'limpar', 'wiki', 'avaliar', 'simular-avaliacao', 'publicar-avaliacao', 'verificar', 'configurar')]
    [string]$Comando,
    [string]$Ref,
    [int]$Pontos,
    [int]$Dias,
    [switch]$SoListar,
    [switch]$Forcar,
    [string]$Card,
    [string]$Branch,
    [string]$Base,
    [string]$Repo,
    [string]$Atividade,
    [switch]$Mover,
    [string]$Coluna,
    [switch]$SemFilho,
    [switch]$NovoFilho,
    [switch]$SemGitlab,
    [switch]$SemFetch,
    [string]$Aceitar,
    [string]$Descartar
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

$script:Raiz = $PSScriptRoot
foreach ($lib in @('Comum', 'Git', 'Gitlab', 'Banco', 'Card', 'Wiki', 'Coletar', 'Publicar', 'Avaliacao', 'Aprendizado', 'Limpeza', 'Instalacao')) {
    . (Join-Path $script:Raiz "lib\$lib.ps1")
}
Carregar-Env $script:Raiz
$script:Cfg = Ler-Config $script:Raiz

try {
    switch ($Comando) {
        'coletar' { Comando-Coletar -Card $Card -Branch $Branch -Base $Base -Repo $Repo -SemGitlab:$SemGitlab -SemFetch:$SemFetch }
        'simular' { Comando-Publicar -Card $Card -Mover:$Mover -Coluna $Coluna -Atividade $Atividade -SemFilho:$SemFilho -NovoFilho:$NovoFilho }
        'publicar' { Comando-Publicar -Card $Card -Executar -Mover:$Mover -Coluna $Coluna -Atividade $Atividade -SemFilho:$SemFilho -NovoFilho:$NovoFilho }
        'retro' { Comando-Retro -Card $Card }
        'propostas' { Comando-Propostas }
        'aprender' { Comando-Aprender -Aceitar $Aceitar -Descartar $Descartar }
        'limpar' { Comando-Limpar -Dias $Dias -SoListar:$SoListar }
        'wiki' { Comando-Wiki -Forcar:$Forcar }
        'verificar' { Comando-Verificar }
        'configurar' { Comando-Configurar }
        'avaliar' { Comando-ColetarAvaliacao -Card $Card -Ref $Ref -Repo $Repo -SemFetch:$SemFetch }
        'simular-avaliacao' { Comando-PublicarAvaliacao -Card $Card -Pontos $Pontos -Coluna $Coluna -SemFilho:$SemFilho -NovoFilho:$NovoFilho }
        'publicar-avaliacao' { Comando-PublicarAvaliacao -Card $Card -Executar -Pontos $Pontos -Coluna $Coluna -SemFilho:$SemFilho -NovoFilho:$NovoFilho }
    }
} catch {
    Write-Host ''
    Write-Host "ERRO: $($_.Exception.Message)"
    exit 1
}
