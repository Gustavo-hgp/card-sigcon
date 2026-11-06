# card-sigcon - regras do quadro: criterios de aceite, coluna atual e card filho.
# Regra da DSG (out/2026): filho = issue comum ligada ao pai por relates_to, titulo
# "#<titulo do pai> - <Atividade>", so a etiqueta de pontos do pai + feito, milestone
# do pai, responsavel = quem fez; nunca etiqueta de coluna/modulo/tema.

# Tira a marcacao markdown de uma linha da HU (titulo, citacao, negrito, italico, escapes).
function Limpar-Markdown([string]$Texto) {
    if ($null -eq $Texto) { return '' }
    $t = $Texto -replace '^\s*>\s?', '' -replace '^\s*#+\s*', ''
    $t = $t -replace '\*\*', '' -replace '`', '' -replace '(?<!\w)_|_(?!\w)', ''
    $t = $t -replace '\\([\\`*_{}\[\]()#+.!>|-])', '$1' -replace '\\\s*$', ''
    return $t.Trim()
}

# Acha os criterios na descricao do card. Formato das HUs da DSG: secao "CRITERIOS DE
# ACEITE" com itens numerados ("1\.", "2.1.", "2.6.1."), continuacao em paragrafos,
# listas e citacoes, e fim no proximo titulo em negrito ("**PROTOTIPO:**"). Aceita
# tambem "CA1: ..." e, sem numeracao, a lista da secao. O id segue a numeracao da HU
# (CA2.1). O agente confere a lista com o dev.
function Extrair-Criterios([string]$Descricao) {
    if (-not $Descricao) { return ,@() }
    $itens = New-Object System.Collections.ArrayList
    $marcadores = New-Object System.Collections.ArrayList
    $dentro = $false; $atual = $null
    foreach ($l in ($Descricao -split "\r?\n")) {
        $limpa = Limpar-Markdown $l
        $n = Normalizar-Texto $limpa
        $ehTitulo = ($l -match '^\s{0,3}#{1,6}\s' -or $l -match '^\s*\*\*[^*]+\*\*\s*:?\s*$')
        $mCa = [regex]::Match($limpa, '(?i)^(?:[-*+]\s*)?(?:\[[ x]\]\s*)?(?:CA|Crit.rio(?:\s+de\s+aceite)?)\s*(\d+(?:\.\d+)*)\s*[:.)-]\s*(\S.*)$')
        if ($mCa.Success) {
            $atual = [pscustomobject]@{ Num = $mCa.Groups[1].Value; Texto = $mCa.Groups[2].Value.Trim() }
            [void]$itens.Add($atual); continue
        }
        if ($n -match 'criterios? de aceit' -and ($ehTitulo -or $limpa.Length -lt 60)) { $dentro = $true; $atual = $null; continue }
        if (-not $dentro) { continue }
        if ($ehTitulo) { $dentro = $false; $atual = $null; continue }
        if (-not $n) { continue }
        $mNum = [regex]::Match($l, '^\s*(?:\*\*)?(\d+(?:\\?\.\d+)*)\\?[.)](?:\*\*)?\s+(\S.*)$')
        if ($mNum.Success) {
            $atual = [pscustomobject]@{ Num = ($mNum.Groups[1].Value -replace '\\', ''); Texto = (Limpar-Markdown $mNum.Groups[2].Value) }
            [void]$itens.Add($atual); continue
        }
        $mBul = [regex]::Match($l, '^\s*(?:[-*+]|\[[ xX]\])\s+(?:\[[ xX]\]\s+)?(\S.*)$')
        if ($null -eq $atual) {
            if ($mBul.Success) { [void]$marcadores.Add((Limpar-Markdown $mBul.Groups[1].Value)) }
            continue
        }
        $atual.Texto = ($atual.Texto + ' ' + ($limpa -replace '^(?:[-*+]|\[[ xX]\])\s+', '')).Trim()
    }
    $resultado = @()
    if ($itens.Count -gt 0) {
        foreach ($x in $itens) { $resultado += [pscustomobject]@{ id = ('CA' + $x.Num); texto = $x.Texto } }
    } elseif ($marcadores.Count -gt 0) {
        for ($i = 0; $i -lt $marcadores.Count; $i++) { $resultado += [pscustomobject]@{ id = ('CA' + ($i + 1)); texto = $marcadores[$i] } }
    } else {
        $i = 0
        foreach ($l in ($Descricao -split "\r?\n")) {
            $limpa = Limpar-Markdown $l
            if ((Normalizar-Texto $limpa) -match '^cenario\s*\d*\s*[:.-]') { $i++; $resultado += [pscustomobject]@{ id = ('CA' + $i); texto = $limpa } }
        }
    }
    return ,$resultado
}

function Coluna-Atual($Issue) {
    $colunas = @($script:Cfg.quadro.colunas | ForEach-Object { Normalizar-Texto $_ })
    foreach ($l in @($Issue.labels)) { if ($colunas -contains (Normalizar-Texto $l)) { return $l } }
    return $null
}

function Eh-Coluna([string]$Etiqueta) {
    $alvo = Normalizar-Texto $Etiqueta
    foreach ($c in @($script:Cfg.quadro.colunas)) { if ((Normalizar-Texto $c) -eq $alvo) { return $true } }
    return $false
}

function Atividade-DaColuna([string]$Coluna) {
    if (-not $Coluna) { return $null }
    $alvo = Normalizar-Texto $Coluna
    foreach ($p in $script:Cfg.quadro.atividadePorColuna.PSObject.Properties) {
        if ((Normalizar-Texto $p.Name) -eq $alvo) { return $p.Value }
    }
    return $null
}

# Cards ligados cujo titulo termina com o nome da atividade (sem depender de acento/travessao).
function Filhos-DaAtividade($Links, [string]$Atividade) {
    $alvo = Normalizar-Texto $Atividade
    return ,@($Links | Where-Object { (Normalizar-Texto $_.title).EndsWith($alvo) })
}

# Notas da avaliacao tecnica (marcador do card-sigcon) gravadas por $Eu.
function Minhas-Avaliacoes($Notas, $Eu) {
    $m = [string]$script:Cfg.textos.marcadorAvaliacao
    return ,@(@($Notas) | Where-Object { $_ -and -not $_.system -and $_.author.id -eq $Eu.id -and ([string]$_.body).Contains($m) })
}

# Avaliacao tecnica publicada pelo card-sigcon: fica como nota interna no card filho
# "... - Avaliação Técnica" (antes de 05/11/2026, nos comentarios do proprio card, que o
# coletar ja le). Devolve [{ Iid, Autor, Data, Texto }] dos filhos.
function Avaliacoes-DosFilhos([int]$ProjetoId, $Links) {
    $m = [string]$script:Cfg.textos.marcadorAvaliacao
    $lista = @()
    $filhos = Filhos-DaAtividade $Links ([string]$script:Cfg.avaliacao.atividade)
    foreach ($f in @($filhos)) {
        $notas = Invoke-Gitlab -Caminho "/projects/$ProjetoId/issues/$($f.iid)/notes?sort=asc&order_by=created_at&per_page=100" -Todas
        foreach ($n in @($notas)) {
            if ($n -and -not $n.system -and ([string]$n.body).Contains($m)) {
                $lista += [pscustomobject]@{ Iid = $f.iid; Autor = $n.author.name; Data = $n.created_at; Texto = [string]$n.body }
            }
        }
    }
    return ,$lista
}

function Filhos-Conhecidos($Links) {
    $lista = @()
    foreach ($l in @($Links)) {
        foreach ($a in @($script:Cfg.quadro.atividades)) {
            if ((Normalizar-Texto $l.title).EndsWith((Normalizar-Texto $a))) { $lista += [pscustomobject]@{ Link = $l; Atividade = $a }; break }
        }
    }
    return ,$lista
}

function Etiqueta-Pontos($Issue) {
    foreach ($l in @($Issue.labels)) { if ([regex]::IsMatch($l, $script:Cfg.quadro.regexEtiquetaPontos)) { return $l } }
    return $null
}
