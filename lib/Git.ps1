# card-sigcon - acesso ao git e analise do diff por arquivo.
# A saida do git e lida como Latin-1 (1 byte = 1 caractere, sem perda) e cada arquivo
# e decodificado com o encoding dele: .java e Cp1252 no SIGCON, .xhtml e UTF-8.

function Formatar-Argumento([string]$Arg) {
    if ($Arg -eq '') { return '""' }
    if ($Arg -notmatch '[\s"]') { return $Arg }
    return '"' + ($Arg -replace '"', '\"') + '"'
}

function Invoke-Git {
    param([string]$Repo, [string[]]$Argumentos, [switch]$PermitirFalha)
    # sem isso o Windows so diz "O nome do diretorio e invalido" ao abrir o git
    if (-not $Repo -or -not (Test-Path -LiteralPath $Repo -PathType Container)) {
        throw "Repositório do SIGCON não encontrado em '$Repo'. Confira CARD_SIGCON_REPO no .env (ou repoPadrao no config/config.json): tem que ser a pasta do clone, a que tem o .git, o JavaSource e o WebContent. Depois reabra o card-ui.cmd."
    }
    $todos = @('-c', 'core.quotepath=off', '-c', 'color.ui=never') + $Argumentos
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'git'
    $psi.Arguments = (($todos | ForEach-Object { Formatar-Argumento $_ }) -join ' ')
    $psi.WorkingDirectory = $Repo
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = $script:Latin1
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    $p = [System.Diagnostics.Process]::Start($psi)
    $tarefaErro = $p.StandardError.ReadToEndAsync()
    $saida = $p.StandardOutput.ReadToEnd()
    $p.WaitForExit()
    $erro = $tarefaErro.Result
    if ($p.ExitCode -ne 0 -and -not $PermitirFalha) {
        throw "git $($Argumentos -join ' ') falhou ($($p.ExitCode)): $($erro.Trim())"
    }
    return [pscustomobject]@{ Saida = $saida; Erro = $erro; Codigo = $p.ExitCode }
}

function Decodificar([string]$Bruto, [System.Text.Encoding]$Encoding) {
    return $Encoding.GetString($script:Latin1.GetBytes($Bruto))
}

function Resolver-Ref([string]$Repo, [string]$Nome, [string[]]$Prefixos) {
    foreach ($p in $Prefixos) {
        $cand = $p + $Nome
        $r = Invoke-Git $Repo @('rev-parse', '--verify', '--quiet', ($cand + '^{commit}')) -PermitirFalha
        if ($r.Codigo -eq 0) { return [pscustomobject]@{ Nome = $Nome; Ref = $cand; Sha = $r.Saida.Trim() } }
    }
    return $null
}

# $true / $false; $null quando o commit nao existe no repositorio local.
function Testar-Ancestral([string]$Repo, [string]$Commit, [string]$Sha) {
    $r = Invoke-Git $Repo @('merge-base', '--is-ancestor', $Commit, $Sha) -PermitirFalha
    if ($r.Codigo -eq 0) { return $true }
    if ($r.Codigo -eq 1) { return $false }
    return $null
}

function Listar-Commits([string]$Repo, [string]$BaseSha, [string]$BranchSha) {
    $r = Invoke-Git $Repo @('log', '--format=%h%x09%an%x09%ad%x09%P%x09%s', '--date=short', ($BaseSha + '..' + $BranchSha))
    $texto = Decodificar $r.Saida ([System.Text.Encoding]::UTF8)
    $lista = @()
    foreach ($l in ($texto -split "`n")) {
        $l = $l.TrimEnd("`r")
        if (-not $l.Trim()) { continue }
        $c = $l -split "`t", 5
        $lista += [pscustomobject]@{
            Sha = $c[0]; Autor = $c[1]; Data = $c[2]
            Merge = ((@($c[3] -split ' ' | Where-Object { $_ })).Count -gt 1)
            Assunto = $c[4]
        }
    }
    return ,$lista
}

function Encoding-DoArquivo([string]$Caminho) {
    $ext = [System.IO.Path]::GetExtension($Caminho).ToLowerInvariant()
    $mapa = $script:Cfg.git.encodingPorExtensao
    $nome = $null
    if ($mapa.PSObject.Properties[$ext]) { $nome = $mapa.$ext }
    if (-not $nome) { return [System.Text.Encoding]::UTF8 }
    return [System.Text.Encoding]::GetEncoding($nome)
}

# Analisa um trecho "diff --git" de um arquivo: linhas adicionadas (com numero na versao
# nova), areas do sistema e alertas de encoding / quebra de linha / arquivo sensivel.
function Analisar-ArquivoDiff([string]$Caminho, [string]$Bruto, [string]$Status, [int]$Adicoes, [int]$Remocoes, [bool]$Binario) {
    $cfg = $script:Cfg
    $enc = Encoding-DoArquivo $Caminho
    $ext = [System.IO.Path]::GetExtension($Caminho).ToLowerInvariant()
    $ehCp1252 = ($enc.CodePage -eq 1252 -or $enc.CodePage -eq 28591)
    $decodificado = Decodificar $Bruto $enc
    $linhasBrutas = $Bruto -split "`n"
    $linhasTexto = $decodificado -split "`n"

    $adicionadas = New-Object System.Collections.ArrayList
    $alertas = New-Object System.Collections.ArrayList
    $emHunk = $false; $linhaNova = 0
    $addCrlf = 0; $addLf = 0; $remCrlf = 0; $remLf = 0
    $fffd = 0; $utf8EmCp1252 = 0; $naoUtf8 = 0
    for ($i = 0; $i -lt $linhasBrutas.Count; $i++) {
        $lb = $linhasBrutas[$i]
        $m = [regex]::Match($lb, '^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@')
        if ($m.Success) { $linhaNova = [int]$m.Groups[1].Value; $emHunk = $true; continue }
        if (-not $emHunk) { continue }
        if ($lb.StartsWith('+')) {
            if ($lb.EndsWith("`r")) { $addCrlf++ } else { $addLf++ }
            $conteudo = $lb.Substring(1).TrimEnd("`r")
            if ($conteudo.Contains([string][char]0xEF + [char]0xBF + [char]0xBD)) { $fffd++ }
            if ($ehCp1252) {
                if ([regex]::IsMatch($conteudo, '[\xC2\xC3][\x80-\xBF]')) { $utf8EmCp1252++ }
            } else {
                try { [void]$script:Utf8Estrito.GetString($script:Latin1.GetBytes($conteudo)) } catch { $naoUtf8++ }
            }
            $txt = ''
            if ($i -lt $linhasTexto.Count) { $txt = $linhasTexto[$i].Substring(1).TrimEnd("`r") }
            [void]$adicionadas.Add([pscustomobject]@{ Linha = $linhaNova; Texto = $txt })
            $linhaNova++
        } elseif ($lb.StartsWith('-')) {
            if ($lb.EndsWith("`r")) { $remCrlf++ } else { $remLf++ }
        } elseif ($lb.StartsWith(' ')) {
            $linhaNova++
        }
    }

    if ($fffd -gt 0) { [void]$alertas.Add("$Caminho tem $fffd linha(s) adicionada(s) com U+FFFD (caractere perdido por encoding errado).") }
    if ($utf8EmCp1252 -gt 0) { [void]$alertas.Add("$Caminho tem $utf8EmCp1252 linha(s) adicionada(s) que parecem UTF-8, mas o arquivo é Cp1252: acento vai aparecer quebrado.") }
    if ($naoUtf8 -gt 0) { [void]$alertas.Add("$Caminho tem $naoUtf8 linha(s) adicionada(s) que não são UTF-8 válido (acento gravado em Cp1252 num arquivo UTF-8).") }
    $totalAdd = $addCrlf + $addLf; $totalRem = $remCrlf + $remLf
    if (@($cfg.git.crlfObrigatorio) -contains $ext) {
        if ($Status -eq 'A' -and $addLf -gt $addCrlf) {
            [void]$alertas.Add("$Caminho é novo e está com quebra de linha LF; o padrão do SIGCON para $ext é CRLF.")
        } elseif ($Status -eq 'M' -and $totalRem -gt 0 -and $totalAdd -ge 5 -and ($remCrlf / $totalRem) -gt 0.9 -and ($addLf / $totalAdd) -gt 0.5) {
            [void]$alertas.Add("$Caminho é CRLF, mas $addLf de $totalAdd linhas adicionadas estão em LF (sed -i? editor?).")
        }
    }
    $maior = [math]::Max($Adicoes, $Remocoes)
    if ($Adicoes -ge 300 -and $Remocoes -ge 300 -and [math]::Abs($Adicoes - $Remocoes) -le (0.05 * $maior)) {
        [void]$alertas.Add("$Caminho foi reescrito quase inteiro (+$Adicoes/-$Remocoes): costuma ser quebra de linha ou encoding trocados no arquivo todo.")
    }
    foreach ($a in @($cfg.arquivosAviso)) {
        if ([regex]::IsMatch($Caminho, $a.padrao)) { [void]$alertas.Add("$Caminho no diff: $($a.motivo)") }
    }
    $compartilhada = $null
    foreach ($c in @($cfg.classesCompartilhadas)) {
        if ([regex]::IsMatch($Caminho, $c.padrao)) { $compartilhada = $c.motivo; break }
    }
    $areas = @()
    foreach ($ar in @($cfg.areas)) {
        foreach ($p in @($ar.padroes)) {
            if ([regex]::IsMatch($Caminho, $p)) { $areas += $ar.nome; break }
        }
    }

    return [pscustomobject]@{
        Caminho = $Caminho; Status = $Status; Adicoes = $Adicoes; Remocoes = $Remocoes; Binario = $Binario
        Encoding = $enc.WebName; Areas = $areas; Alertas = @($alertas); Compartilhada = $compartilhada
        LinhasAdicionadas = @($adicionadas); TextoDiff = ($decodificado -replace "`r", '')
    }
}

function Obter-ArquivosDoDiff([string]$Repo, [string]$De, [string]$Para, [string[]]$Pathspecs) {
    $comum = @('--no-color', '--no-renames', '--no-ext-diff', $De, $Para, '--') + $Pathspecs
    $diff = (Invoke-Git $Repo (@('diff') + $comum)).Saida
    $numstat = (Invoke-Git $Repo (@('diff', '--numstat') + $comum)).Saida
    $nameStatus = (Invoke-Git $Repo (@('diff', '--name-status') + $comum)).Saida

    $status = @{}
    foreach ($l in ($nameStatus -split "`n")) {
        $l = $l.TrimEnd("`r"); if (-not $l) { continue }
        $c = $l -split "`t", 2
        $status[(Decodificar $c[1] ([System.Text.Encoding]::UTF8))] = $c[0].Substring(0, 1)
    }
    $contagem = @{}
    foreach ($l in ($numstat -split "`n")) {
        $l = $l.TrimEnd("`r"); if (-not $l) { continue }
        $c = $l -split "`t", 3
        $bin = ($c[0] -eq '-')
        $add = 0; $rem = 0
        if (-not $bin) { $add = [int]$c[0]; $rem = [int]$c[1] }
        $contagem[(Decodificar $c[2] ([System.Text.Encoding]::UTF8))] = @($add, $rem, $bin)
    }

    $arquivos = @()
    foreach ($parte in [regex]::Split($diff, '(?m)^(?=diff --git )')) {
        if (-not $parte.StartsWith('diff --git ')) { continue }
        $fim = $parte.IndexOf("`n"); if ($fim -lt 0) { $fim = $parte.Length }
        $cabecalho = (Decodificar $parte.Substring(0, $fim) ([System.Text.Encoding]::UTF8)).TrimEnd("`r")
        $m = [regex]::Match($cabecalho, '^diff --git a/(.+?) b/(.+)$')
        $caminho = $m.Groups[2].Value
        $st = 'M'; if ($status.ContainsKey($caminho)) { $st = $status[$caminho] }
        $n = @(0, 0, $false); if ($contagem.ContainsKey($caminho)) { $n = $contagem[$caminho] }
        $arquivos += Analisar-ArquivoDiff $caminho $parte $st $n[0] $n[1] $n[2]
    }
    return ,$arquivos
}

function Alteracoes-NaoCommitadas([string]$Repo, [string]$Branch) {
    $atual = (Invoke-Git $Repo @('symbolic-ref', '--quiet', '--short', 'HEAD') -PermitirFalha).Saida.Trim()
    if ($atual -ne $Branch) { return @() }
    $st = Decodificar (Invoke-Git $Repo @('status', '--porcelain', '--untracked-files=no')).Saida ([System.Text.Encoding]::UTF8)
    $pend = @()
    foreach ($l in ($st -split "`n")) {
        $l = $l.TrimEnd("`r"); if ($l.Length -lt 4) { continue }
        $caminho = $l.Substring(3)
        $ignorar = $false
        foreach ($p in @($script:Cfg.git.ignorarNaoCommitado)) { if ([regex]::IsMatch($caminho, $p)) { $ignorar = $true; break } }
        if (-not $ignorar) { $pend += $caminho }
    }
    return ,$pend
}

function Nome-ApareceNaBase([string]$Repo, [string]$Sha, [string]$Nome, [string]$Arquivo) {
    $argumentos = @('grep', '-q', '-I', '-w', '-F', '-e', $Nome, $Sha, '--')
    if ($Arquivo) { $argumentos += $Arquivo }
    $r = Invoke-Git $Repo $argumentos -PermitirFalha
    return ($r.Codigo -eq 0)
}
