# card-sigcon - funcoes comuns: configuracao, texto, arquivos e referencia do card.
# Os .ps1 sao salvos em UTF-8 com BOM: sem o BOM o PowerShell 5.1 le o arquivo como ANSI e
# estraga os acentos. Texto que vai para o GitLab fica em config/config.json ("textos").

$script:Utf8SemBom = New-Object System.Text.UTF8Encoding($false)
$script:Utf8Estrito = New-Object System.Text.UTF8Encoding($false, $true)
$script:Latin1 = [System.Text.Encoding]::GetEncoding(28591)

# Leitura compartilhada: a pagina le o log do turno enquanto o executar.ps1 ainda grava nele.
# ReadAllText abre so com FileShare.Read e, nesse instante, a gravacao do outro processo falha
# ("o arquivo esta sendo usado por outro processo").
function Ler-Texto([string]$Caminho) {
    $fs = New-Object System.IO.FileStream($Caminho, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]'ReadWrite, Delete')
    try { return (New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8, $true)).ReadToEnd() }
    finally { $fs.Dispose() }
}

function Gravar-Texto([string]$Caminho, [string]$Texto) {
    $dir = Split-Path -Parent $Caminho
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Force -Path $dir) }
    [System.IO.File]::WriteAllText($Caminho, $Texto, $script:Utf8SemBom)
}

function Ler-Json([string]$Caminho) {
    return (Ler-Texto $Caminho) | ConvertFrom-Json
}

function Gravar-Json([string]$Caminho, $Objeto) {
    Gravar-Texto $Caminho (ConvertTo-Json -InputObject $Objeto -Depth 20)
}

# Le NOME=valor do .env da raiz (se existir). Variavel ja definida no processo vence.
function Carregar-Env([string]$Raiz) {
    $caminho = Join-Path $Raiz '.env'
    if (-not (Test-Path -LiteralPath $caminho)) { return }
    foreach ($l in ((Ler-Texto $caminho) -split "\r?\n")) {
        $m = [regex]::Match($l, '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$')
        if (-not $m.Success) { continue }
        $nome = $m.Groups[1].Value; $valor = $m.Groups[2].Value
        if ($valor.Length -ge 2 -and (($valor.StartsWith('"') -and $valor.EndsWith('"')) -or ($valor.StartsWith("'") -and $valor.EndsWith("'")))) {
            $valor = $valor.Substring(1, $valor.Length - 2)
        }
        if ($valor -and -not [Environment]::GetEnvironmentVariable($nome, 'Process')) {
            [Environment]::SetEnvironmentVariable($nome, $valor, 'Process')
        }
    }
}

function Ler-Config([string]$Raiz) {
    $cfg = Ler-Json (Join-Path $Raiz 'config\config.json')
    # Variaveis de ambiente sobrepoem a config (testes e repositorio em outro lugar).
    if ($env:CARD_SIGCON_GITLAB_URL) { $cfg.gitlabUrl = $env:CARD_SIGCON_GITLAB_URL }
    if ($env:CARD_SIGCON_REPO) { $cfg.repoPadrao = $env:CARD_SIGCON_REPO }
    # caminho relativo (padrao "../gggt": o clone do SIGCON ao lado desta pasta) vira absoluto
    $cfg.repoPadrao = Caminho-Absoluto $Raiz ([string]$cfg.repoPadrao)
    return $cfg
}

function Hash-Texto([string]$Texto) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([System.BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Texto))) -replace '-', '') }
    finally { $sha.Dispose() }
}

# Caminho absoluto com barras normais (C:/x/y): e o formato das permissoes do agente.
function Caminho-Absoluto([string]$Raiz, [string]$Caminho) {
    $c = ([string]$Caminho).Trim().Trim('"').Trim("'")
    if (-not $c) { return $c }
    if (-not [System.IO.Path]::IsPathRooted($c)) { $c = Join-Path $Raiz $c }
    return (([System.IO.Path]::GetFullPath($c)).TrimEnd('\', '/') -replace '\\', '/')
}

# Tira acento, baixa a caixa, troca travessao por hifen e junta espacos:
# usado para comparar etiquetas e titulos sem depender da grafia exata.
function Normalizar-Texto([string]$Texto) {
    if ($null -eq $Texto) { return '' }
    $t = $Texto.Normalize([System.Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($c in $t.ToCharArray()) {
        if ([System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($c) -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$sb.Append($c)
        }
    }
    $r = $sb.ToString().ToLowerInvariant()
    $r = [regex]::Replace($r, ('[' + [char]0x2012 + '-' + [char]0x2015 + ']'), '-')
    $r = [regex]::Replace($r, '\s+', ' ')
    return $r.Trim()
}

function Preencher([string]$Modelo, [hashtable]$Valores) {
    $r = $Modelo
    foreach ($k in $Valores.Keys) { $r = $r.Replace('{' + $k + '}', [string]$Valores[$k]) }
    return $r
}

# Aceita o link do card (issues ou work_items), "#1237" ou "1237" (projeto padrao).
function Ler-ReferenciaCard([string]$Card) {
    $cfg = $script:Cfg
    if (-not $Card) { throw 'Informe -Card (link do card ou número).' }
    $m = [regex]::Match($Card.Trim(), '^(https?://[^/]+)/(.+?)/-/(?:issues|work_items)/(\d+)')
    if ($m.Success) {
        return [pscustomobject]@{ Projeto = $m.Groups[2].Value; Iid = [int]$m.Groups[3].Value; Url = $Card.Trim() }
    }
    $m = [regex]::Match($Card.Trim(), '^#?(\d+)$')
    if ($m.Success) {
        $iid = [int]$m.Groups[1].Value
        return [pscustomobject]@{ Projeto = $cfg.projetoPadrao; Iid = $iid; Url = ($cfg.gitlabUrl.TrimEnd('/') + '/' + $cfg.projetoPadrao + '/-/issues/' + $iid) }
    }
    throw "Link de card inválido: $Card"
}

function Nome-PastaCard($Ref) {
    return (($Ref.Projeto -split '/')[-1]) + '-' + $Ref.Iid
}

function Pasta-Saida($Ref) {
    return Join-Path $script:Raiz ('out\' + (Nome-PastaCard $Ref))
}

function Caminho-Relativo([string]$Caminho) {
    $raiz = $script:Raiz.TrimEnd('\') + '\'
    if ($Caminho.StartsWith($raiz, [System.StringComparison]::OrdinalIgnoreCase)) { return $Caminho.Substring($raiz.Length).Replace('\', '/') }
    return $Caminho
}

function Escrever-Titulo([string]$Texto) {
    Write-Host ''
    Write-Host "== $Texto =="
}

function Avisar([string]$Texto) {
    Write-Host "AVISO: $Texto"
}

# Celula de tabela markdown: sem quebra de linha e sem barra vertical.
function Celula([string]$Texto, [int]$Max = 160) {
    if ($null -eq $Texto) { return '' }
    $t = ($Texto -replace '\r?\n', ' ' -replace '\|', '\|').Trim()
    if ($t.Length -gt $Max) { $t = $t.Substring(0, $Max) + '...' }
    return $t
}
