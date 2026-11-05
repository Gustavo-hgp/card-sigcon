# card-sigcon - limpeza do que fica so na maquina do dev:
# - pastas out/<card> sem uso ha N dias (data mais recente de qualquer arquivo), menos o
#   card aberto na pagina;
# - nos cards que ficam, copias antigas de "anteriores" e logs de turno com mais de N dias;
# - conversas do Kiro desta pasta paradas ha N dias, menos a do card aberto.
# Nunca toca em historico/ nem aprendizado/ (sao do time e vao para o git).

function Ultimo-Uso([string]$Dir) {
    $ultimo = (Get-Item -LiteralPath $Dir).LastWriteTime
    foreach ($f in @(Get-ChildItem -LiteralPath $Dir -Recurse -Force -ErrorAction SilentlyContinue)) {
        if ($f.LastWriteTime -gt $ultimo) { $ultimo = $f.LastWriteTime }
    }
    return $ultimo
}

function Tamanho-Pasta([string]$Dir) {
    $s = (Get-ChildItem -LiteralPath $Dir -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    if ($null -eq $s) { return 0 }
    return [long]$s
}

# Conversas do Kiro abertas nesta pasta; $null quando o kiro-cli nao esta instalado.
function Sessoes-Kiro {
    if (-not (Get-Command kiro-cli -ErrorAction SilentlyContinue)) {
        $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
        if (-not (Get-Command kiro-cli -ErrorAction SilentlyContinue)) { return $null }
    }
    Push-Location -LiteralPath $script:Raiz
    try { $json = (& kiro-cli chat --list-sessions -f json 2>$null) -join "`n" } finally { Pop-Location }
    $lista = @()
    if ($json.Trim()) {
        foreach ($w in @($json | ConvertFrom-Json)) { foreach ($s in @($w.sessions)) { if ($s) { $lista += $s } } }
    }
    return ,$lista
}

function Limpar-Antigos {
    param([int]$Dias, [string]$PastaAtual, [string]$SessaoAtual, [switch]$SoListar)
    if ($Dias -lt 1) { throw 'Dias precisa ser 1 ou mais.' }
    $limite = (Get-Date).AddDays(-$Dias)
    $out = Join-Path $script:Raiz 'out'
    $r = [ordered]@{ dias = $Dias; cards = @(); anteriores = 0; logs = 0; sessoes = @(); bytes = [long]0; avisos = @() }

    if (Test-Path -LiteralPath $out) {
        foreach ($d in @(Get-ChildItem -LiteralPath $out -Directory -Force)) {
            # so pastas comuns com nome de card; nunca segue atalho/juncao
            if ($d.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { continue }
            if ($d.Name -notmatch '^[A-Za-z0-9._-]+$') { continue }
            if ($d.Name -ne $PastaAtual -and (Ultimo-Uso $d.FullName) -lt $limite) {
                $r.cards += $d.Name
                $r.bytes += Tamanho-Pasta $d.FullName
                if (-not $SoListar) { Remove-Item -LiteralPath $d.FullName -Recurse -Force }
                continue
            }
            $ant = Join-Path $d.FullName 'anteriores'
            if (Test-Path -LiteralPath $ant) {
                foreach ($a in @(Get-ChildItem -LiteralPath $ant -Directory -Force)) {
                    if ((Ultimo-Uso $a.FullName) -ge $limite) { continue }
                    $r.anteriores++
                    $r.bytes += Tamanho-Pasta $a.FullName
                    if (-not $SoListar) { Remove-Item -LiteralPath $a.FullName -Recurse -Force }
                }
            }
            $ui = Join-Path $d.FullName 'ui'
            if (Test-Path -LiteralPath $ui) {
                foreach ($f in @(Get-ChildItem -LiteralPath $ui -File -Force)) {
                    if ($f.LastWriteTime -ge $limite) { continue }
                    $r.logs++
                    $r.bytes += $f.Length
                    if (-not $SoListar) { Remove-Item -LiteralPath $f.FullName -Force }
                }
            }
        }
    }

    $sessoes = Sessoes-Kiro
    if ($null -eq $sessoes) {
        $r.avisos += 'kiro-cli não encontrado: as conversas do Kiro não foram limpas.'
    } else {
        foreach ($s in $sessoes) {
            if ($SessaoAtual -and $s.sessionId -eq $SessaoAtual) { continue }
            $quando = [datetime]::MinValue
            if (-not [datetime]::TryParse([string]$s.updatedAt, [ref]$quando)) { continue }
            if ($quando -ge $limite) { continue }
            $r.sessoes += [ordered]@{ id = [string]$s.sessionId; titulo = [string]$s.title; atualizada = $quando.ToString('yyyy-MM-dd') }
            if (-not $SoListar) {
                & kiro-cli chat --delete-session ([string]$s.sessionId) 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0) { $r.avisos += "não consegui apagar a conversa $($s.sessionId)" }
            }
        }
    }
    return $r
}

# O card aberto na pagina (out/ui-estado.json) nunca e limpo, nem a conversa dele.
function Card-Atual-DaPagina {
    $arq = Join-Path $script:Raiz 'out\ui-estado.json'
    if (-not (Test-Path -LiteralPath $arq)) { return [pscustomobject]@{ pasta = ''; sessaoId = '' } }
    try {
        $e = Ler-Json $arq
        return [pscustomobject]@{ pasta = [string]$e.pasta; sessaoId = [string]$e.sessaoId }
    } catch {
        throw 'Não consegui ler out/ui-estado.json; por segurança nada foi limpo.'
    }
}

function Dias-DaLimpeza([int]$Dias) {
    if ($Dias -gt 0) { return $Dias }
    $cfg = $script:Cfg.limpeza
    if ($cfg -and [int]$cfg.dias -gt 0) { return [int]$cfg.dias }
    return 60
}

function Comando-Limpar([int]$Dias, [switch]$SoListar) {
    $atual = Card-Atual-DaPagina
    $r = Limpar-Antigos -Dias (Dias-DaLimpeza $Dias) -PastaAtual $atual.pasta -SessaoAtual $atual.sessaoId -SoListar:$SoListar
    Write-Host (Resumo-Limpeza $r ([bool]$SoListar))
    if ($atual.pasta) { Write-Host "  (o card aberto na página, $($atual.pasta), nunca é limpo)" }
    if ($SoListar) { Write-Host '  Só listado: rode sem -SoListar para apagar.' }
}

function Resumo-Limpeza($R, [bool]$SoListar) {
    $verbo = 'Removido'; if ($SoListar) { $verbo = 'Seria removido' }
    $mb = '{0:N1}' -f ($R.bytes / 1MB)
    $linhas = @("Limpeza (sem uso há mais de $($R.dias) dias): $verbo $mb MB em arquivos.")
    if (@($R.cards).Count) { $linhas += "  cards: $(@($R.cards) -join ', ')" }
    if ($R.anteriores) { $linhas += "  cópias em anteriores/: $($R.anteriores)" }
    if ($R.logs) { $linhas += "  logs de turno: $($R.logs)" }
    if (@($R.sessoes).Count) {
        $linhas += "  conversas do Kiro: $(@($R.sessoes).Count)"
        foreach ($s in @($R.sessoes)) { $linhas += "    $($s.atualizada)  $($s.titulo)" }
    }
    if (-not @($R.cards).Count -and -not $R.anteriores -and -not $R.logs -and -not @($R.sessoes).Count) { $linhas += '  nada para limpar.' }
    foreach ($a in @($R.avisos)) { $linhas += "  AVISO: $a" }
    return ($linhas -join "`n")
}
