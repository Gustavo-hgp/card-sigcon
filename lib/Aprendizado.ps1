# card-sigcon - aprendizado e retrospectiva.
# O agente so escreve propostas em aprendizado/_propostas.md; quem decide e o dev, com
# "aprender -Aceitar 1,3 -Descartar 2". Formato de cada proposta:
#   ## area: banco | card: #1115 | data: 2026-10-21
#   Regra: ...
#   Por que: ...
#   Evidencia: ...   (opcional)
# Na revisao do aprendizado o cabecalho ganha "tipo: remover" e a Regra e o texto de uma
# linha que ja esta no arquivo da area (a regra, sem o "Por quê"). Sem tipo = adicionar.
# Juntar duplicadas ou reescrever uma regra = remover a(s) antiga(s) + adicionar a nova.

function Caminho-Propostas { return Join-Path $script:Raiz 'aprendizado\_propostas.md' }

# Indices das linhas do arquivo de area que casam com o texto de uma proposta "remover":
# a linha inteira ou so a regra (antes do "_Por quê:_"), sem diferenciar acento,
# maiuscula ou espacos repetidos.
function Linhas-DaRegra([string[]]$Linhas, [string]$Regra) {
    $alvo = Normalizar-Texto ($Regra -replace '^\s*-\s+', '')
    $r = @()
    if (-not $alvo) { return ,$r }
    for ($i = 0; $i -lt $Linhas.Count; $i++) {
        if ($Linhas[$i] -notmatch '^\s*-\s+') { continue }
        $corpo = Normalizar-Texto ($Linhas[$i] -replace '^\s*-\s+', '')
        $soRegra = (($corpo -split '\s*_por qu', 2)[0]).Trim()
        if ($corpo -eq $alvo -or $soRegra -eq $alvo) { $r += $i }
    }
    return ,$r
}

# Confere uma proposta contra o arquivo da area: devolve '' se pode ser gravada, ou o motivo.
function Problema-DaProposta($Proposta, [AllowNull()][string[]]$LinhasDaArea) {
    if ($Proposta.Tipo -notin @('adicionar', 'remover')) { return "tipo '$($Proposta.Tipo)' desconhecido (use adicionar ou remover)" }
    if (-not $Proposta.Regra) { return "sem 'Regra:'" }
    if ($null -eq $LinhasDaArea) { return "a área '$($Proposta.Area)' não tem arquivo em aprendizado/" }
    if ($Proposta.Tipo -eq 'remover') {
        $achadas = (Linhas-DaRegra $LinhasDaArea $Proposta.Regra).Count
        if ($achadas -eq 0) { return "a regra a remover não está em aprendizado/$($Proposta.Area).md (já saiu ou o texto não confere)" }
        if ($achadas -gt 1) { return "a regra a remover casa com $achadas linhas de aprendizado/$($Proposta.Area).md: use o texto exato de uma" }
    }
    return ''
}

function Linhas-DaArea([string]$Area) {
    if (-not $Area -or $Area -notmatch '^[A-Za-z0-9._-]+$') { return $null }
    $arq = Join-Path $script:Raiz "aprendizado\$Area.md"
    if (-not (Test-Path -LiteralPath $arq)) { return $null }
    return ,@((Ler-Texto $arq) -split "\r?\n")
}

function Ler-Propostas {
    $caminho = Caminho-Propostas
    $cabecalho = New-Object System.Collections.ArrayList
    $props = New-Object System.Collections.ArrayList
    if (-not (Test-Path -LiteralPath $caminho)) { return [pscustomobject]@{ Cabecalho = @(); Propostas = @() } }
    $atual = $null; $campo = $null
    foreach ($l in ((Ler-Texto $caminho) -split "\r?\n")) {
        if ($l -match '^##\s+(.*)$') {
            $atual = [pscustomobject]@{ Tipo = 'adicionar'; Area = ''; Card = ''; Data = ''; Regra = ''; PorQue = ''; Evidencia = ''; Bruto = New-Object System.Collections.ArrayList }
            foreach ($parte in ($Matches[1] -split '\|')) {
                $kv = $parte -split ':', 2
                if ($kv.Count -lt 2) { continue }
                switch (Normalizar-Texto $kv[0]) {
                    'tipo' { $atual.Tipo = Normalizar-Texto $kv[1] }
                    'area' { $atual.Area = $kv[1].Trim() }
                    'card' { $atual.Card = $kv[1].Trim() }
                    'data' { $atual.Data = $kv[1].Trim() }
                }
            }
            [void]$atual.Bruto.Add($l)
            [void]$props.Add($atual); $campo = $null
            continue
        }
        if ($null -eq $atual) { [void]$cabecalho.Add($l); continue }
        [void]$atual.Bruto.Add($l)
        $m = [regex]::Match((Normalizar-Texto $l), '^-?\s*(regra|por ?que|evidencia)\s*:')
        if ($m.Success) {
            $valor = $l.Substring($l.IndexOf(':') + 1).Trim()
            switch ($m.Groups[1].Value) {
                'regra' { $campo = 'Regra' }
                'evidencia' { $campo = 'Evidencia' }
                default { $campo = 'PorQue' }
            }
            $atual.$campo = $valor
        } elseif ($campo -and $l.Trim()) {
            $atual.$campo = ($atual.$campo + ' ' + $l.Trim()).Trim()
        }
    }
    return [pscustomobject]@{ Cabecalho = @($cabecalho); Propostas = @($props) }
}

function Comando-Propostas {
    $p = Ler-Propostas
    if ($p.Propostas.Count -eq 0) { Write-Host 'Nenhuma proposta pendente em aprendizado/_propostas.md.'; return }
    $i = 0
    foreach ($x in $p.Propostas) {
        $i++
        Write-Host ''
        $topo = @("[$i] $($x.Tipo)", "área: $($x.Area)")
        if ($x.Card) { $topo += "card: $($x.Card)" }
        if ($x.Data) { $topo += "data: $($x.Data)" }
        Write-Host ($topo -join ' | ')
        Write-Host "    Regra: $($x.Regra)"
        Write-Host "    Por quê: $($x.PorQue)"
        if ($x.Evidencia) { Write-Host "    Evidência: $($x.Evidencia)" }
        $problema = Problema-DaProposta $x (Linhas-DaArea $x.Area)
        if ($problema) { Avisar "$problema`: corrija a proposta antes de aceitar (ou descarte)." }
    }
    Write-Host ''
    Write-Host 'Para decidir: aprender -Aceitar 1,3 -Descartar 2'
}

function Ler-Indices([string]$Texto, [int]$Max) {
    $r = @()
    if (-not $Texto) { return ,$r }
    foreach ($p in ($Texto -split '[,; ]+')) {
        if (-not $p) { continue }
        $n = 0
        if (-not [int]::TryParse($p, [ref]$n) -or $n -lt 1 -or $n -gt $Max) { throw "Índice de proposta inválido: '$p' (há $Max proposta(s))." }
        $r += $n
    }
    return ,$r
}

function Comando-Aprender([string]$Aceitar, [string]$Descartar) {
    $p = Ler-Propostas
    $total = $p.Propostas.Count
    if ($total -eq 0) { Write-Host 'Nenhuma proposta pendente.'; return }
    $aceitos = Ler-Indices $Aceitar $total
    $descartados = Ler-Indices $Descartar $total
    if ($aceitos.Count + $descartados.Count -eq 0) { throw 'Informe -Aceitar e/ou -Descartar com os números mostrados em "propostas".' }
    foreach ($n in $aceitos) { if ($descartados -contains $n) { throw "Proposta $n está em -Aceitar e em -Descartar." } }

    # Aplica tudo em memoria primeiro: se uma proposta nao confere, nenhum arquivo muda.
    $cfg = $script:Cfg
    $areas = [ordered]@{}
    $feitas = @()
    foreach ($n in $aceitos) {
        $x = $p.Propostas[$n - 1]
        if (-not $areas.Contains($x.Area)) {
            $lidas = Linhas-DaArea $x.Area
            $lista = $null
            if ($null -ne $lidas) { $lista = New-Object System.Collections.ArrayList; foreach ($l in $lidas) { [void]$lista.Add($l) } }
            $areas[$x.Area] = $lista
        }
        $linhas = $areas[$x.Area]
        $problema = Problema-DaProposta $x $linhas
        if ($problema) { throw "Proposta ${n}: $problema. Nada foi gravado." }
        if ($x.Tipo -eq 'remover') {
            $i = (Linhas-DaRegra $linhas $x.Regra)[0]
            $linhas.RemoveAt($i)
            $feitas += "Aceita [$n] -> removida de aprendizado/$($x.Area).md"
        } else {
            while ($linhas.Count -gt 0 -and -not ([string]$linhas[$linhas.Count - 1]).Trim()) { $linhas.RemoveAt($linhas.Count - 1) }
            [void]$linhas.Add((Preencher $cfg.textos.linhaAprendizado @{ regra = $x.Regra; porque = $x.PorQue; card = $x.Card; data = $x.Data }))
            $feitas += "Aceita [$n] -> aprendizado/$($x.Area).md"
        }
    }
    foreach ($area in $areas.Keys) {
        $linhas = $areas[$area]
        while ($linhas.Count -gt 0 -and -not ([string]$linhas[$linhas.Count - 1]).Trim()) { $linhas.RemoveAt($linhas.Count - 1) }
        Gravar-Texto (Join-Path $script:Raiz "aprendizado\$area.md") ((@($linhas) -join "`n") + "`n")
        if ($linhas.Count -gt [int]$cfg.limiteLinhasAprendizado) { Avisar "aprendizado/$area.md passou de $($cfg.limiteLinhasAprendizado) linhas: peça uma revisão do aprendizado (botão na aba Aprendizado da página)." }
    }
    foreach ($f in $feitas) { Write-Host $f }
    $restantes = New-Object System.Collections.ArrayList
    foreach ($l in $p.Cabecalho) { [void]$restantes.Add($l) }
    for ($i = 1; $i -le $total; $i++) {
        if ($aceitos -contains $i -or $descartados -contains $i) { continue }
        foreach ($l in $p.Propostas[$i - 1].Bruto) { [void]$restantes.Add($l) }
    }
    Gravar-Texto (Caminho-Propostas) ((($restantes -join "`n").TrimEnd()) + "`n")
    foreach ($n in $descartados) { Write-Host "Descartada [$n]" }
}

# Junta o que aconteceu depois do plano publicado (retorno de homologacao, comentarios
# de QA) com o plano e a avaliacao, para o agente achar o que o plano deixou passar.
function Comando-Retro([string]$Card) {
    $cfg = $script:Cfg
    $ref = Ler-ReferenciaCard $Card
    $dirOut = Pasta-Saida $ref
    $projetoId = Obter-ProjetoId $ref
    $issue = Invoke-Gitlab -Caminho "/projects/$projetoId/issues/$($ref.Iid)"
    $notas = Notas-Humanas (Invoke-Gitlab -Caminho "/projects/$projetoId/issues/$($ref.Iid)/notes?sort=asc&order_by=created_at&per_page=100" -Todas)
    $marcador = $cfg.textos.marcadorPlano
    $planos = @($notas | Where-Object { ([string]$_.body).Contains($marcador) })
    $depois = $notas
    $notaPlano = $null
    if ($planos.Count -gt 0) {
        $notaPlano = $planos[-1]
        $depois = @($notas | Where-Object { ([datetime]$_.created_at) -gt ([datetime]$notaPlano.created_at) -and -not ([string]$_.body).Contains($marcador) })
    } else {
        Avisar 'nenhum plano do card-sigcon no card: a retro vai considerar todos os comentários.'
    }
    $hist = Join-Path $script:Raiz ("historico\" + (Nome-PastaCard $ref) + '.md')

    $md = @("# Retro do card #$($ref.Iid) - $($issue.title)", '', "- Coluna atual: $(Coluna-Atual $issue)", "- Etiquetas: $(@($issue.labels) -join ', ')", '')
    $md += '## Plano e avaliacao publicados'
    $md += ''
    if (Test-Path -LiteralPath $hist) { $md += (Ler-Texto $hist).Trim() }
    elseif ($notaPlano) { $md += [string]$notaPlano.body }
    else { $md += '(nao encontrado)' }
    $md += ''
    $md += "## Comentarios depois do plano ($($depois.Count))"
    $md += ''
    foreach ($n in $depois) { $md += "### $($n.author.name) - $($n.created_at)"; $md += ''; $md += [string]$n.body; $md += '' }
    $md += '## O que fazer'
    $md += ''
    $md += 'Para cada problema relatado: o plano tinha um teste que pegaria isso? A avaliacao marcou o criterio como atendido? Proponha em aprendizado/_propostas.md a regra que teria evitado o retorno (area, card, regra, por que, evidencia).'
    $caminho = Join-Path $dirOut 'retro.md'
    Gravar-Texto $caminho (($md -join "`n") + "`n")
    Write-Host "Comentários depois do plano: $($depois.Count)"
    Write-Host "Retro: $(Caminho-Relativo $caminho)"
}
