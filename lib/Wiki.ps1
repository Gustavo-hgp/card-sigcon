# card-sigcon - copia local da wiki do SIGCON (config "wiki.projeto": documentacao-sigcon).
# A wiki inteira tem ~4 MB e nao cabe no contexto do agente: fica em wiki/, uma pagina por
# arquivo, e o agente busca nela com glob/grep. O coletar aponta as paginas que casam com o
# card. A copia se renova sozinha depois de "wiki.horasValidade" horas; "card.cmd wiki -Forcar"
# (ou o botao da pagina) baixa de novo na hora.
# Salvo em UTF-8 com BOM (ver lib/Comum.ps1).

function Dir-Wiki { return Join-Path $script:Raiz 'wiki' }

function Ler-IndiceWiki {
    $p = Join-Path (Dir-Wiki) '_indice.json'
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    try { return Ler-Json $p } catch { return $null }
}

# Nome de arquivo a partir do slug, sem os caracteres que o Windows recusa.
function Arquivo-DaPagina([string]$Slug) {
    # colchete atrapalha padrao de busca (glob): "[HM]-Tela" vira "HM-Tela"
    $n = (($Slug -replace '[\[\]]', '') -replace '[<>:"/\\|?*\x00-\x1F]', '-') -replace '-{2,}', '-'
    $n = $n.Trim(' ', '.', '-')
    if (-not $n) { $n = 'pagina' }
    if ($n.Length -gt 120) { $n = $n.Substring(0, 120).TrimEnd(' ', '.', '-') }
    return $n + '.md'
}

function Data-Legivel([string]$Iso) {
    $d = [datetime]::MinValue
    if ([datetime]::TryParse($Iso, [ref]$d)) { return $d.ToString('dd/MM/yyyy HH:mm') }
    return $Iso
}

function Atualizar-Wiki([switch]$Forcar) {
    $cfg = $script:Cfg.wiki
    if (-not $cfg -or -not $cfg.projeto) { throw 'config.json sem "wiki.projeto".' }
    $indice = Ler-IndiceWiki
    if (-not $Forcar -and $indice) {
        $quando = [datetime]::MinValue
        if ([datetime]::TryParse([string]$indice.atualizadoEm, [ref]$quando) -and ((Get-Date) - $quando).TotalHours -lt [double]$cfg.horasValidade) {
            return [pscustomobject]@{ Baixou = $false; Paginas = @($indice.paginas).Count; AtualizadoEm = [string]$indice.atualizadoEm }
        }
    }
    $proj = Invoke-Gitlab -Caminho ('/projects/' + [uri]::EscapeDataString([string]$cfg.projeto))
    # atribuir antes de iterar: o -Todas devolve a lista como um objeto so no pipeline
    $paginas = Invoke-Gitlab -Caminho "/projects/$($proj.id)/wikis?with_content=1" -Todas
    $dir = Dir-Wiki
    if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Force -Path $dir) }
    $base = $script:Cfg.gitlabUrl.TrimEnd('/') + '/' + $proj.path_with_namespace + '/-/wikis/'
    $usados = @{}
    $lista = New-Object System.Collections.ArrayList
    foreach ($p in $paginas) {
        if (-not $p -or -not $p.slug) { continue }
        $arq = Arquivo-DaPagina ([string]$p.slug)
        $raizNome = $arq.Substring(0, $arq.Length - 3); $n = 1
        while ($usados.ContainsKey($arq)) { $n++; $arq = "$raizNome-$n.md" }
        $usados[$arq] = $true
        $titulo = [string]$p.title; if (-not $titulo) { $titulo = [string]$p.slug }
        $url = $base + ((([string]$p.slug) -split '/' | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/')
        Gravar-Texto (Join-Path $dir $arq) ("# $titulo`n`nFonte: $url`n`n" + ([string]$p.content).Trim() + "`n")
        [void]$lista.Add([ordered]@{ titulo = $titulo; slug = [string]$p.slug; arquivo = $arq })
    }
    if ($lista.Count -eq 0) { throw 'a wiki veio vazia: mantive a cópia anterior.' }
    # paginas que sairam da wiki
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter '*.md' -File)) {
        if ($f.Name -ne '_indice.md' -and -not $usados.ContainsKey($f.Name)) { Remove-Item -LiteralPath $f.FullName }
    }
    $agora = (Get-Date).ToString('s')
    $ordenada = @($lista | Sort-Object { Normalizar-Texto $_.titulo })
    $md = New-Object System.Collections.ArrayList
    [void]$md.Add("# Índice da wiki do SIGCON ($($ordenada.Count) páginas, cópia de $(Data-Legivel $agora))")
    [void]$md.Add('')
    [void]$md.Add("Fonte: $base")
    [void]$md.Add('')
    [void]$md.Add('Cada linha: título da página -> arquivo nesta pasta. Para achar uma tela, procure pelo nome dela com grep.')
    [void]$md.Add('')
    foreach ($x in $ordenada) { [void]$md.Add("- $($x.titulo) -> $($x.arquivo)") }
    Gravar-Texto (Join-Path $dir '_indice.md') (($md -join "`n") + "`n")
    Gravar-Json (Join-Path $dir '_indice.json') ([ordered]@{ projetoId = $proj.id; projeto = $proj.path_with_namespace; atualizadoEm = $agora; paginas = $ordenada })
    return [pscustomobject]@{ Baixou = $true; Paginas = $ordenada.Count; AtualizadoEm = $agora }
}

# Palavras que aparecem em muito titulo e nao dizem qual tela e (comparadas sem acento).
$script:PalavrasGenericasWiki = @('tela', 'telas', 'sistema', 'campo', 'campos', 'botao', 'botoes', 'para', 'como', 'deve', 'devem',
    'pelo', 'pela', 'pelos', 'pelas', 'sobre', 'entre', 'quando', 'onde', 'mais', 'menos', 'cada', 'todo', 'todos', 'toda', 'todas',
    'esta', 'este', 'isso', 'essa', 'esse', 'pode', 'podem', 'apos', 'antes', 'depois', 'novo', 'nova', 'novos', 'novas', 'ajuste',
    'ajustes', 'implementar', 'melhorar', 'melhoria', 'melhorias', 'alterar', 'incluir', 'exibir', 'criar', 'realizar', 'permitir',
    'dados', 'informacoes', 'sigcon', 'saida', 'modulo', 'menu', 'opcao', 'opcoes', 'regra', 'regras')

# Palavras de 4+ letras, sem acento, cortadas em 6 letras: "pesquisa" e "pesquisar",
# "cadastro" e "cadastrar" viram a mesma.
function Radicais-Wiki([string]$Texto, [switch]$SemGenericas) {
    $r = @{}
    foreach ($m in [regex]::Matches((Normalizar-Texto $Texto), '[a-z0-9]{4,}')) {
        if ($SemGenericas -and $script:PalavrasGenericasWiki -contains $m.Value) { continue }
        $v = $m.Value; if ($v.Length -gt 6) { $v = $v.Substring(0, 6) }
        $r[$v] = $true
    }
    return $r
}

# Paginas da wiki que casam com o card, mais relevantes primeiro (no maximo wiki.maxPaginas):
# link para a pagina no card; titulo inteiro citado no card; ou a maior parte das palavras
# do titulo no card.
function Paginas-DaWiki([string]$TextoDoCard) {
    $indice = Ler-IndiceWiki
    if (-not $indice) { return ,@() }
    $max = [int]$script:Cfg.wiki.maxPaginas; if ($max -le 0) { $max = 8 }
    $textoNorm = ' ' + ((Normalizar-Texto $TextoDoCard) -replace '[^a-z0-9]+', ' ') + ' '
    $doCard = Radicais-Wiki $TextoDoCard
    $linkados = @{}
    foreach ($m in [regex]::Matches($TextoDoCard, '/-/wikis/([^\s)\]>"#?]+)')) {
        try { $linkados[(Normalizar-Texto ([uri]::UnescapeDataString($m.Groups[1].Value)))] = $true } catch { }
    }
    $cands = @()
    foreach ($p in @($indice.paginas)) {
        $titNorm = ((Normalizar-Texto ([string]$p.titulo)) -replace '[^a-z0-9]+', ' ').Trim()
        $pontos = 0; $motivo = ''
        # titulo de uma palavra so ("Documentação", "Relatórios") casa com quase todo card
        $doTitulo = @((Radicais-Wiki ([string]$p.titulo) -SemGenericas).Keys)
        if ($linkados.ContainsKey((Normalizar-Texto ([string]$p.slug)))) {
            $pontos = 1000; $motivo = 'link no card'
        } elseif ($doTitulo.Count -ge 2 -and $textoNorm.Contains(' ' + $titNorm + ' ')) {
            $pontos = 100 + $titNorm.Length; $motivo = 'o card cita o título'
        } else {
            if ($doTitulo.Count -ge 2) {
                $casados = @($doTitulo | Where-Object { $doCard.ContainsKey($_) })
                $fracao = $casados.Count / $doTitulo.Count
                if ($casados.Count -ge 2 -and $fracao -ge 0.6) { $pontos = 10 * $fracao + $casados.Count; $motivo = 'palavras do título no card' }
            }
        }
        if ($pontos -gt 0) { $cands += [pscustomobject]@{ Titulo = [string]$p.titulo; Arquivo = 'wiki/' + $p.arquivo; Motivo = $motivo; Pontos = $pontos } }
    }
    return ,@($cands | Sort-Object Pontos -Descending | Select-Object -First $max)
}

function Comando-Wiki([switch]$Forcar) {
    $r = Atualizar-Wiki -Forcar:$Forcar
    if ($r.Baixou) { Write-Host "Wiki baixada: $($r.Paginas) páginas em wiki/ (cópia de $(Data-Legivel $r.AtualizadoEm))." }
    else { Write-Host "A wiki já está atualizada: $($r.Paginas) páginas, cópia de $(Data-Legivel $r.AtualizadoEm). Use -Forcar para baixar de novo." }
}
