# card-sigcon - o que muda de uma maquina para outra.
# O agente do Kiro (.kiro/agents/card-sigcon.json) e gerado a partir de .kiro/agente-modelo.json
# com o caminho do repositorio do SIGCON desta maquina (config repoPadrao / .env), e a
# verificacao diz o que falta instalar ou configurar. A pagina faz os dois ao abrir;
# na linha de comando: card.cmd configurar e card.cmd verificar.
# Salvo em UTF-8 com BOM (ver lib/Comum.ps1).

function Arquivo-Agente { return Join-Path $script:Raiz '.kiro\agents\card-sigcon.json' }
function Carimbo-Agente { return Join-Path $script:Raiz '.kiro\agents\card-sigcon.carimbo' }

# kiro-cli instalado depois de abrir o terminal ainda nao esta no PATH do processo.
function Achar-Kiro {
    $k = Get-Command kiro-cli -ErrorAction SilentlyContinue
    if (-not $k) {
        $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
        $k = Get-Command kiro-cli -ErrorAction SilentlyContinue
    }
    if ($k) { return $k.Source }
    return $null
}

# Roda um programa e devolve a saida, ou $null se passar do tempo.
function Saida-ComTempo([string]$Programa, [string]$Argumentos, [int]$Milissegundos) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Programa
    $psi.Arguments = $Argumentos
    $psi.WorkingDirectory = $script:Raiz
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $saida = $p.StandardOutput.ReadToEndAsync()
    $erro = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit($Milissegundos)) {
        try { $p.Kill() } catch { }
        return $null
    }
    return ($saida.Result + "`n" + $erro.Result)
}

# Pasta .kiro (modelo do agente e instrucoes) incompleta: copia ou zip que deixou de fora
# a pasta que comeca com ponto. Devolve os arquivos que faltam (caminho relativo).
$script:ComoFaltaKiro = 'A pasta .kiro do card-sigcon não veio junto (alguns zips e cópias deixam de fora a pasta que começa com ponto). Copie de novo a pasta card-sigcon inteira, inclusive a .kiro, e rode card.cmd configurar.'
function Faltando-DoAgente {
    $modelo = Join-Path $script:Raiz '.kiro\agente-modelo.json'
    if (-not (Test-Path -LiteralPath $modelo)) { return ,@('.kiro/agente-modelo.json') }
    $faltam = @()
    try { $recursos = @((Ler-Texto $modelo | ConvertFrom-Json).resources) } catch { return ,@('.kiro/agente-modelo.json (JSON inválido)') }
    foreach ($r in $recursos) {
        $rel = ([string]$r) -replace '^file://', ''
        if ($rel -and -not (Test-Path -LiteralPath (Join-Path $script:Raiz $rel))) { $faltam += $rel }
    }
    return ,$faltam
}

# Gera o agente se o modelo ou o caminho do repositorio mudaram (ou com -Forcar).
function Gerar-Agente([switch]$Forcar) {
    $modelo = Join-Path $script:Raiz '.kiro\agente-modelo.json'
    $faltam = Faltando-DoAgente
    if ($faltam.Count) { throw ('faltam ' + ($faltam -join ', ') + '. ' + $script:ComoFaltaKiro) }
    $repo = [string]$script:Cfg.repoPadrao
    $texto = Ler-Texto $modelo
    $chave = Hash-Texto ($texto + '|' + $repo)
    $arq = Arquivo-Agente
    $carimbo = Carimbo-Agente
    if (-not $Forcar -and (Test-Path -LiteralPath $arq) -and (Test-Path -LiteralPath $carimbo) -and (Ler-Texto $carimbo).Trim() -eq $chave) {
        return [pscustomobject]@{ Gerou = $false; Repo = $repo; Aviso = '' }
    }
    # no JSON a barra invertida do regex vai dobrada
    $regex = [regex]::Escape($repo) -replace '\\', '\\'
    Gravar-Texto $arq ($texto.Replace('{{REPO_REGEX}}', $regex).Replace('{{REPO}}', $repo))
    $aviso = ''
    $kiro = Achar-Kiro
    if (-not $kiro) {
        $aviso = 'kiro-cli não encontrado: o agente ficou no formato antigo. Depois de instalar o Kiro, rode card.cmd configurar.'
    } else {
        # formato universal (v2 + v3): o Kiro gera as permissoes a partir das listas do modelo
        $s = Saida-ComTempo $kiro ('agent upgrade --no-backup "' + (Join-Path $script:Raiz '.kiro\agents') + '"') 60000
        if ($null -eq $s -or $s -match '(?i)\berror\b') { $aviso = "o Kiro não conseguiu converter o agente: $s" }
    }
    Gravar-Texto $carimbo $chave
    return [pscustomobject]@{ Gerou = $true; Repo = $repo; Aviso = $aviso }
}

function Item-Verificacao([bool]$Ok, [string]$Nome, [string]$Detalhe, [string]$Como) {
    return [pscustomobject]@{ Ok = $Ok; Nome = $Nome; Detalhe = $Detalhe; Como = $Como }
}

function Verificar-Instalacao {
    $itens = @()
    $repo = [string]$script:Cfg.repoPadrao
    $temRepo = $repo -and (Test-Path -LiteralPath (Join-Path $repo '.git'))
    $itens += Item-Verificacao $temRepo 'Repositório do SIGCON' $repo 'Ponha o clone do gggt ao lado desta pasta (../gggt) ou informe CARD_SIGCON_REPO no .env; depois reabra o card-ui.cmd.'
    if ($repo -match '\s') { $itens += Item-Verificacao $false 'Caminho do repositório' "o caminho '$repo' tem espaço" 'Use um caminho sem espaços: os comandos de git do agente não casam com a lista liberada.' }
    $itens += Item-Verificacao ([bool](Get-Command git -ErrorAction SilentlyContinue)) 'Git' 'git no PATH' 'Instale o Git for Windows.'
    $token = $env:GITLAB_TOKEN; if (-not $token) { $token = [Environment]::GetEnvironmentVariable('GITLAB_TOKEN', 'User') }
    $itens += Item-Verificacao ([bool]$token) 'Token do GitLab' 'GITLAB_TOKEN' 'Copie o .env.exemplo para .env e preencha GITLAB_TOKEN (guia, Passo 5).'
    $proxy = [Environment]::GetEnvironmentVariable('HTTPS_PROXY', 'Process'); if (-not $proxy) { $proxy = [Environment]::GetEnvironmentVariable('HTTPS_PROXY', 'User') }
    $itens += Item-Verificacao ([bool]$proxy) 'Proxy para o Kiro' 'HTTPS_PROXY' 'Crie HTTPS_PROXY, HTTP_PROXY e NO_PROXY (guia, Passo 2) e abra um terminal novo.'
    $kiro = Achar-Kiro
    $itens += Item-Verificacao ([bool]$kiro) 'Kiro CLI' 'kiro-cli no PATH' 'Instale o Kiro CLI (guia, Passo 3).'
    if ($kiro) {
        $w = Saida-ComTempo $kiro 'whoami' 20000
        $logado = $w -and $w -match '(?i)logged in with' -and $w -notmatch '(?i)not logged in'
        $itens += Item-Verificacao ([bool]$logado) 'Login no Kiro' 'kiro-cli whoami' 'Faça o login do Kiro num terminal (guia, Passo 4).'
    }
    $faltam = Faltando-DoAgente
    if ($faltam.Count) {
        $itens += Item-Verificacao $false 'Instruções do agente' ('faltam ' + ($faltam -join ', ')) $script:ComoFaltaKiro
    } else {
        $itens += Item-Verificacao $true 'Instruções do agente' '.kiro/agente-modelo.json e .kiro/steering' ''
    }
    $agente = (Test-Path -LiteralPath (Arquivo-Agente)) -and (Test-Path -LiteralPath (Carimbo-Agente))
    $como = 'Rode card.cmd configurar (a página faz isso sozinha ao abrir).'
    if ($faltam.Count) { $como = 'Primeiro resolva as instruções do agente (item acima).' }
    $itens += Item-Verificacao $agente 'Agente do Kiro' '.kiro/agents/card-sigcon.json' $como
    return ,$itens
}

function Comando-Verificar {
    $falta = 0
    foreach ($i in (Verificar-Instalacao)) {
        if ($i.Ok) { Write-Host ("[ ok  ] {0}: {1}" -f $i.Nome, $i.Detalhe) }
        else { $falta++; Write-Host ("[FALTA] {0}: {1}. {2}" -f $i.Nome, $i.Detalhe, $i.Como) }
    }
    Write-Host ''
    if ($falta) { Write-Host "$falta item(ns) para resolver." } else { Write-Host 'Tudo certo: abra o card-ui.cmd.' }
}

function Comando-Configurar {
    try {
        $g = Gerar-Agente -Forcar
        Write-Host "Agente do Kiro gerado para o repositório $($g.Repo)."
        if ($g.Aviso) { Avisar $g.Aviso }
    } catch { Write-Host "Não gerei o agente do Kiro: $($_.Exception.Message)" }
    Write-Host ''
    Comando-Verificar
}
