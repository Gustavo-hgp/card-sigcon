<#
card-sigcon - executa uma tarefa longa da pagina (turno do Kiro ou card.ps1) em
processo proprio. Le os parametros de um JSON, grava a saida linha a linha no log e,
no fim, um JSON com o codigo de saida (e o id da sessao do Kiro, no primeiro turno).
Salvo em UTF-8 com BOM (ver lib/Comum.ps1).
#>
param([string]$Entrada)

$e = [System.IO.File]::ReadAllText($Entrada, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
. (Join-Path $e.raiz 'lib\Creditos.ps1')
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
# O kiro-cli nao usa o proxy do Windows (PAC), so estas variaveis.
foreach ($n in @('HTTPS_PROXY', 'HTTP_PROXY', 'NO_PROXY')) {
    if (-not [Environment]::GetEnvironmentVariable($n, 'Process')) {
        $v = [Environment]::GetEnvironmentVariable($n, 'User')
        if ($v) { [Environment]::SetEnvironmentVariable($n, $v, 'Process') }
    }
}
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }
$utf8 = New-Object System.Text.UTF8Encoding($false)
Set-Location -LiteralPath $e.raiz

# Grava no log com novas tentativas: a pagina (ou o antivirus) pode estar com o arquivo aberto
# naquele instante. Se continuar preso, a linha fica pendente e vai junto com a proxima; um erro
# aqui nao pode interromper o turno (o Kiro ficaria rodando sem ninguem ler a saida).
$script:Pendente = ''
function Descarregar {
    for ($i = 0; $i -lt 30 -and $script:Pendente; $i++) {
        try { [System.IO.File]::AppendAllText($e.log, $script:Pendente, $utf8); $script:Pendente = '' }
        catch { Start-Sleep -Milliseconds 100 }
    }
}
function Linha([string]$Texto) {
    if ($Texto -match 'System\.Management\.Automation\.RemoteException') { return }
    $script:Pendente += $Texto + "`n"
    Descarregar
}

# Aspas de argumento no Windows (regras do runtime C): o PowerShell 5.1 nao escapa
# aspas dentro de argumento de programa nativo, entao a linha de comando e montada aqui.
function Citar-Argumento([string]$Arg) {
    if ($Arg -eq '') { return '""' }
    if ($Arg -notmatch '[\s"]') { return $Arg }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    $barras = 0
    foreach ($c in $Arg.ToCharArray()) {
        if ($c -eq [char]92) { $barras++; continue }
        if ($c -eq [char]34) { [void]$sb.Append([char]92, 2 * $barras + 1); [void]$sb.Append([char]34); $barras = 0; continue }
        if ($barras) { [void]$sb.Append([char]92, $barras); $barras = 0 }
        [void]$sb.Append($c)
    }
    if ($barras) { [void]$sb.Append([char]92, 2 * $barras) }
    [void]$sb.Append('"')
    return $sb.ToString()
}

# Comandos do agente (git, shell) parados ha mais de $Minutos sob o processo do Kiro.
# Ex.: git grep com saida grande: o Kiro para de ler depois do limite dele e o git fica
# bloqueado escrevendo, para sempre. Matar so o comando devolve o controle ao agente.
function Comandos-Parados([int]$Raiz, [double]$Minutos) {
    $todos = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
    $filhos = @{}
    foreach ($x in $todos) { if (-not $filhos.ContainsKey([int]$x.ParentProcessId)) { $filhos[[int]$x.ParentProcessId] = @() }; $filhos[[int]$x.ParentProcessId] += $x }
    $achados = @()
    $fila = New-Object System.Collections.Queue
    $fila.Enqueue($Raiz)
    while ($fila.Count) {
        $atual = $fila.Dequeue()
        foreach ($c in @($filhos[[int]$atual])) {
            if (-not $c) { continue }
            $fila.Enqueue([int]$c.ProcessId)
            if (@('git.exe', 'powershell.exe', 'cmd.exe', 'bash.exe', 'pwsh.exe') -contains $c.Name -and $c.CreationDate -lt (Get-Date).AddMinutes(-$Minutos)) { $achados += $c }
        }
    }
    return ,$achados
}

# Roda um programa e grava stdout e stderr no log linha a linha, na ordem em que chegam.
# Turno sem nenhuma linha por $MinutosParado: interrompe os comandos parados do agente.
function Rodar-Programa([string]$Programa, [string[]]$Argumentos, [double]$MinutosParado = 0) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Programa
    $psi.Arguments = (@($Argumentos | ForEach-Object { Citar-Argumento $_ }) -join ' ')
    $psi.WorkingDirectory = $e.raiz
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = $utf8
    $psi.StandardErrorEncoding = $utf8
    $p = [System.Diagnostics.Process]::Start($psi)
    $tOut = $p.StandardOutput.ReadLineAsync()
    $tErr = $p.StandardError.ReadLineAsync()
    $ultimaSaida = Get-Date
    while ($tOut -or $tErr) {
        $lista = @(); if ($tOut) { $lista += $tOut }; if ($tErr) { $lista += $tErr }
        $i = [System.Threading.Tasks.Task]::WaitAny([System.Threading.Tasks.Task[]]$lista, 15000)
        if ($i -lt 0) {
            if ($MinutosParado -gt 0 -and ((Get-Date) - $ultimaSaida).TotalMinutes -ge $MinutosParado) {
                foreach ($c in (Comandos-Parados $p.Id $MinutosParado)) {
                    $cmd = [string]$c.CommandLine; if ($cmd.Length -gt 140) { $cmd = $cmd.Substring(0, 140) + '...' }
                    Linha "AVISO: comando parado há mais de $MinutosParado min sem saída, interrompido para o agente seguir: $cmd"
                    Stop-Process -Id $c.ProcessId -Force -ErrorAction SilentlyContinue
                }
                $ultimaSaida = Get-Date
            }
            continue
        }
        $ultimaSaida = Get-Date
        $t = $lista[$i]
        $texto = $t.Result
        if ([object]::ReferenceEquals($t, $tOut)) {
            if ($null -eq $texto) { $tOut = $null } else { Linha $texto; $tOut = $p.StandardOutput.ReadLineAsync() }
        } else {
            if ($null -eq $texto) { $tErr = $null } else { Linha $texto; $tErr = $p.StandardError.ReadLineAsync() }
        }
    }
    $p.WaitForExit()
    return $p.ExitCode
}

$codigo = 1
$sessao = ''
$creditos = $null
try {
    if ($e.tipo -eq 'kiro') {
        $kiro = Get-Command kiro-cli -ErrorAction SilentlyContinue
        if (-not $kiro) { throw 'kiro-cli não encontrado no PATH (veja o guia de instalação, Passo 3).' }
        # creditos do turno = total da sessao depois - antes (sessao nova comeca em zero)
        $antes = 0.0
        if ($e.sessaoId) { $antes = Creditos-DaSessao ([string]$e.sessaoId) }
        $a = @('chat', '--agent', 'card-sigcon', '--no-interactive', '--wrap', 'never')
        if ($e.sessaoId) { $a += @('--resume-id', [string]$e.sessaoId) }
        $a += ([string]$e.mensagem -replace "`r`n", "`n")
        $codigo = Rodar-Programa $kiro.Source $a 5
        $sessao = [string]$e.sessaoId
        if (-not $sessao -and $e.marcador) {
            # A sessao nova tem como titulo o comeco da primeira mensagem (o marcador).
            $json = (& kiro-cli chat --list-sessions -f json 2>$null) -join "`n"
            foreach ($w in @($json | ConvertFrom-Json)) {
                foreach ($s in @($w.sessions)) {
                    if (([string]$s.title).StartsWith([string]$e.marcador)) { $sessao = $s.sessionId; break }
                }
            }
            if (-not $sessao -and -not $e.apagarSessao) { Linha 'AVISO: não achei a sessão do Kiro desta conversa; recomece o card na página.' }
        }
        if ($sessao -and $null -ne $antes) {
            # o Kiro grava o consumo na sessao alguns segundos depois de sair: espera ate 10 s;
            # sem valor novo, o custo do turno fica desconhecido (nulo), nao zero
            for ($i = 0; $i -lt 20; $i++) {
                $depois = Creditos-DaSessao $sessao
                if ($null -ne $depois -and $depois -gt $antes) { $creditos = [math]::Round($depois - $antes, 4); break }
                Start-Sleep -Milliseconds 500
            }
        }
        # Turno avulso (revisao do aprendizado): a conversa nao serve para mais nada.
        if ($e.apagarSessao -and $sessao) {
            & kiro-cli chat --delete-session $sessao 2>&1 | Out-Null
            $sessao = ''
        }
    } else {
        $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $e.raiz 'card.ps1')) + @($e.argumentos)
        & powershell @a 2>&1 | ForEach-Object { Linha "$_" }
        $codigo = $LASTEXITCODE
    }
} catch {
    Linha "ERRO: $($_.Exception.Message)"
    $codigo = 1
}
Descarregar
$fim = @{ codigo = $codigo; fim = (Get-Date).ToString('s'); sessaoId = $sessao; creditos = $creditos }
[System.IO.File]::WriteAllText($e.fim, (ConvertTo-Json -InputObject $fim -Compress), $utf8)
