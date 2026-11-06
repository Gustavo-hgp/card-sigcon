# card-sigcon - comando "coletar": junta git + card num contexto.md para o agente.
# Nao decide nada do card: so confere a base, mede o diff, roda a camada 1 de banco
# e escreve out/<projeto>-<iid>/{contexto.md, contexto.json, diff.txt}.

function Comando-Coletar {
    param([string]$Card, [string]$Branch, [string]$Base, [string]$Repo, [switch]$SemGitlab, [switch]$SemFetch)
    $cfg = $script:Cfg
    if (-not $Card -or -not $Branch -or -not $Base) { throw 'Informe -Card, -Branch e -Base (a base de onde a branch saiu).' }
    if (-not $Repo) { $Repo = $cfg.repoPadrao }
    if (-not (Test-Path -LiteralPath (Join-Path $Repo '.git'))) { throw "Repositório git não encontrado em $Repo (use -Repo)." }
    $ref = Ler-ReferenciaCard $Card
    $dirOut = Pasta-Saida $ref
    $alertas = New-Object System.Collections.ArrayList

    Escrever-Titulo "Git ($Repo)"
    if (-not $SemFetch) {
        foreach ($nome in @($Base, $Branch)) {
            if ($nome -match '^[0-9a-f]{7,40}([~^]\d*)*$') { continue }
            Write-Host "git fetch origin $nome"
            $f = Invoke-Git $Repo @('fetch', '--quiet', 'origin', $nome) -PermitirFalha
            if ($f.Codigo -ne 0) { Avisar "fetch de '$nome' falhou; seguindo com o que existe localmente. $($f.Erro.Trim())" }
        }
    }
    $b = Resolver-Ref $Repo $Branch @('refs/heads/', 'refs/remotes/origin/', '')
    if (-not $b) { throw "Branch '$Branch' não encontrada (nem local nem no origin)." }
    $bs = Resolver-Ref $Repo $Base @('refs/remotes/origin/', 'refs/heads/', '')
    if (-not $bs) { throw "Base '$Base' não encontrada (nem no origin nem local)." }

    if ($b.Ref -like 'refs/heads/*') {
        $o = Resolver-Ref $Repo $Branch @('refs/remotes/origin/')
        if ($o -and $o.Sha -ne $b.Sha) {
            $naoEnviados = (Invoke-Git $Repo @('rev-list', '--count', ($o.Sha + '..' + $b.Sha))).Saida.Trim()
            $soNoOrigin = (Invoke-Git $Repo @('rev-list', '--count', ($b.Sha + '..' + $o.Sha))).Saida.Trim()
            [void]$alertas.Add("A branch local difere do origin ($naoEnviados commit(s) não enviados, $soNoOrigin só no origin). A análise usou a LOCAL.")
        }
    }

    foreach ($c in @($cfg.git.commitsContaminados)) {
        $naBranch = Testar-Ancestral $Repo $c.sha $b.Sha
        if ($naBranch -ne $true) { continue }
        $naBase = Testar-Ancestral $Repo $c.sha $bs.Sha
        if ($naBase -ne $true) {
            throw "A branch contém o commit $($c.sha) e a base '$Base' não. $($c.motivo) O diff viria com milhares de commits de outros cards: confira a base informada ou recrie a branch."
        }
    }

    $commits = Listar-Commits $Repo $bs.Sha $b.Sha
    if ($commits.Count -eq 0) {
        [void]$alertas.Add("Nenhum commit entre a base e a branch: a branch já está na base (já foi mergeada?) ou a base informada está errada.")
    } elseif ($commits.Count -gt [int]$cfg.git.limiteCommitsAviso) {
        [void]$alertas.Add("$($commits.Count) commits entre a base e a branch: confira se a base é mesmo '$Base'.")
    }
    $mbr = Invoke-Git $Repo @('merge-base', $bs.Sha, $b.Sha) -PermitirFalha
    if ($mbr.Codigo -ne 0) { throw "A branch e a base não têm ancestral comum." }
    $mb = $mbr.Saida.Trim()

    $pathspecs = @('.') + @($cfg.git.excluirDoDiff)
    $arquivos = Obter-ArquivosDoDiff $Repo $mb $b.Sha $pathspecs
    foreach ($a in $arquivos) { foreach ($x in $a.Alertas) { [void]$alertas.Add($x) } }
    $pend = Alteracoes-NaoCommitadas $Repo $Branch
    if ($pend.Count -gt 0) { [void]$alertas.Add("Há alterações NÃO commitadas na branch (não entram na análise): $($pend -join ', ')") }
    $compartilhadas = @($arquivos | Where-Object { $_.Compartilhada })
    $areas = @($arquivos | ForEach-Object { $_.Areas } | Where-Object { $_ } | Sort-Object -Unique)

    Write-Host "Analisando sinais de banco em $($arquivos.Count) arquivo(s)..."
    $banco = Analisar-Banco $arquivos $Repo $mb

    $issue = $null; $notas = @(); $links = @(); $projetoId = $null
    if (-not $SemGitlab) {
        Escrever-Titulo 'GitLab'
        $projetoId = Obter-ProjetoId $ref
        $issue = Invoke-Gitlab -Caminho "/projects/$projetoId/issues/$($ref.Iid)"
        $notas = Notas-Humanas (Invoke-Gitlab -Caminho "/projects/$projetoId/issues/$($ref.Iid)/notes?sort=asc&order_by=created_at&per_page=100" -Todas)
        $links = Invoke-Gitlab -Caminho "/projects/$projetoId/issues/$($ref.Iid)/links" -Todas
        Write-Host "Card #$($issue.iid): $($issue.title)"
    }
    # avaliacao tecnica feita antes do desenvolvimento: nota interna no card filho
    $avaliacoesFilho = @()
    if ($issue) {
        try { $avaliacoesFilho = Avaliacoes-DosFilhos $projetoId $links } catch { Avisar "não consegui ler a avaliação técnica do card filho ($($_.Exception.Message))." }
    }
    $criterios = @()
    if ($issue) { $criterios = Extrair-Criterios $issue.description }

    # wiki do sistema: renova a copia local se estiver velha e aponta as paginas do card
    $paginasWiki = @()
    if ($issue) {
        try {
            $w = Atualizar-Wiki
            if ($w.Baixou) { Write-Host "Wiki atualizada: $($w.Paginas) páginas." }
        } catch { Avisar "não consegui atualizar a wiki ($($_.Exception.Message)); uso a cópia que já existe, se houver." }
        $textoCard = (@([string]$issue.title, [string]$issue.description) + @($notas | ForEach-Object { [string]$_.body })) -join "`n"
        $paginasWiki = Paginas-DaWiki $textoCard
    }
    $indiceWiki = Ler-IndiceWiki

    $nomesAprendizado = @(@($cfg.aprendizadoSempre) + $areas | Select-Object -Unique)
    $aprendizado = @()
    foreach ($n in $nomesAprendizado) {
        $p = Join-Path $script:Raiz "aprendizado\$n.md"
        if (Test-Path -LiteralPath $p) { $aprendizado += [pscustomobject]@{ Nome = $n; Caminho = "aprendizado/$n.md"; Texto = (Ler-Texto $p).Trim() } }
    }
    $exemplos = Exemplos-DoHistorico $areas (Nome-PastaCard $ref)

    # ---- arquivos de saida ----
    $pastaRel = Caminho-Relativo $dirOut
    $diffTexto = ($arquivos | ForEach-Object { $_.TextoDiff }) -join ''
    Gravar-Texto (Join-Path $dirOut 'diff.txt') $diffTexto
    $linhasDiff = ($diffTexto -split "`n").Count

    $md = New-Object System.Collections.ArrayList
    function L([string]$t = '') { [void]$md.Add($t) }
    $titulo = '(sem GitLab)'; if ($issue) { $titulo = $issue.title }
    L "# Contexto do card #$($ref.Iid) - $titulo"
    L ''
    L "- Card: $($ref.Url)"
    if ($issue) {
        $milestone = ''; if ($issue.milestone) { $milestone = $issue.milestone.title }
        L "- Estado: $($issue.state) | Coluna: $(Coluna-Atual $issue) | Pontos: $(Etiqueta-Pontos $issue) | Milestone: $milestone"
        L "- Etiquetas: $(@($issue.labels) -join ', ')"
    }
    L "- Branch: ``$Branch`` ($($b.Ref), $($b.Sha.Substring(0, 10)))"
    L "- Base informada pelo dev: ``$Base`` ($($bs.Ref), $($bs.Sha.Substring(0, 10))) | merge-base $($mb.Substring(0, 10))"
    L "- Repositorio: $Repo"
    L "- Pasta de saida: $pastaRel (grave aqui avaliacao.md, banco.md, plano.md e decisao.json)"
    L "- Areas tocadas: $($areas -join ', ')"
    L ''
    $merges = @($commits | Where-Object { $_.Merge }).Count
    L "## Commits ($($commits.Count), $merges merge) - confirmar com o dev"
    L ''
    L '| sha | data | autor | assunto |'
    L '|---|---|---|---|'
    foreach ($c in $commits) { L "| $($c.Sha) | $($c.Data) | $(Celula $c.Autor 40) | $(Celula $c.Assunto) |" }
    L ''
    L '## Alertas do script'
    L ''
    if ($alertas.Count -eq 0) { L '- nenhum' } else { foreach ($x in $alertas) { L "- $x" } }
    foreach ($a in $compartilhadas) { L "- Classe compartilhada ``$($a.Caminho)``: $($a.Compartilhada)" }
    L ''
    L '## Criterios de aceite extraidos (confirmar a lista com o dev)'
    L ''
    if (-not $issue) { L '- (coletado com -SemGitlab: sem card)' }
    elseif ($criterios.Count -eq 0) { L '- Nenhum criterio reconhecido automaticamente: extraia da descricao e dos comentarios abaixo.' }
    else { foreach ($c in $criterios) { L "- **$($c.id)** $($c.texto)" } }
    L ''
    L "## Arquivos alterados ($($arquivos.Count))"
    L ''
    L '| arquivo | status | + | - | encoding | areas |'
    L '|---|---|---|---|---|---|'
    foreach ($a in $arquivos) {
        $bin = ''; if ($a.Binario) { $bin = ' (binario)' }
        L "| $($a.Caminho)$bin | $($a.Status) | $($a.Adicoes) | $($a.Remocoes) | $($a.Encoding) | $($a.Areas -join ', ') |"
    }
    L ''
    $ind = 'NAO'; if ($banco.Indicio) { $ind = 'SIM' }
    L "## Banco de dados - camada 1 (script). Indicio de mudanca: $ind"
    L ''
    L 'Camada 2 e sua: para cada item, decida se e objeto novo, alteracao de objeto existente ou falso positivo, e grave em banco.md. Camada 3 e o dev: pergunte tem script? onde esta? ja rodou em HOMOLOG?'
    L ''
    if ($banco.Scripts.Count -gt 0) { L "Scripts no diff: $($banco.Scripts -join ', ')"; L '' }
    L '### Nomes de banco nas linhas adicionadas'
    L ''
    if ($banco.Identificadores.Count -eq 0) { L '- nenhum' } else {
        L '| tipo | nome | onde | ja aparecia na base? |'
        L '|---|---|---|---|'
        foreach ($i in $banco.Identificadores) {
            $ex = 'nao conferido'
            if ($i.ExisteNaBase -eq $true) { $ex = 'sim' } elseif ($i.ExisteNaBase -eq $false) { $ex = '**NAO (novo?)**' }
            L "| $($i.Tipo) | $($i.Nome) | $($i.Arquivo):$($i.Linha) | $ex |"
        }
    }
    L ''
    L '### Sinais nas linhas adicionadas'
    L ''
    if ($banco.Achados.Count -eq 0) { L '- nenhum' } else {
        L '| tipo | onde | trecho |'
        L '|---|---|---|'
        foreach ($x in $banco.Achados) { L "| $($x.Tipo) | $($x.Arquivo):$($x.Linha) | $(Celula $x.Trecho 140) |" }
    }
    L ''
    if ($issue) {
        L '## Descricao do card'
        L ''
        L ([string]$issue.description)
        L ''
        L "## Comentarios do card ($($notas.Count), mais antigos primeiro)"
        L ''
        foreach ($n in $notas) {
            $marca = ''; if ([string]$n.body -like ('*' + $cfg.textos.marcadorPlano + '*')) { $marca = ' (plano publicado pelo card-sigcon)' }
            if ([string]$n.body -like ('*' + $cfg.textos.marcadorAvaliacao + '*')) { $marca = ' (avaliação técnica do card-sigcon)' }
            L "### $($n.author.name) - $($n.created_at)$marca"
            L ''
            L ([string]$n.body)
            L ''
        }
        if (@($avaliacoesFilho).Count) {
            L '## Avaliacao tecnica (nota interna no card filho, feita antes do desenvolvimento)'
            L ''
            foreach ($a in @($avaliacoesFilho)) { L "### Filho #$($a.Iid) - $($a.Autor) - $($a.Data)"; L ''; L $a.Texto; L '' }
        }
        L '## Cards ligados'
        L ''
        if (@($links).Count -eq 0) { L '- nenhum' } else {
            L '| iid | titulo | estado | etiquetas |'
            L '|---|---|---|---|'
            foreach ($k in $links) { L "| #$($k.iid) | $(Celula $k.title) | $($k.state) | $(@($k.labels) -join ', ') |" }
        }
        L ''
    }
    L '## Wiki (documentacao do sistema)'
    L ''
    if (-not $indiceWiki) {
        L '- wiki nao baixada (o dev roda card.cmd wiki ou o botao Atualizar wiki da pagina).'
    } else {
        if ($paginasWiki.Count -eq 0) { L '- nenhuma pagina casou com o card: procure a tela em wiki/_indice.md ou com grep em wiki/.' }
        else { foreach ($p in $paginasWiki) { L "- $($p.Titulo): ``$($p.Arquivo)`` ($($p.Motivo))" } }
        L ''
        L "A wiki inteira esta em wiki/ (uma pagina por arquivo, indice em wiki/_indice.md, copia de $(Data-Legivel ([string]$indiceWiki.atualizadoEm))). Leia as paginas acima antes de avaliar; para outra tela citada na HU, procure pelo nome com grep em wiki/."
    }
    L ''
    L '## Aprendizado aplicavel (respeite; proponha correcao se algo estiver errado)'
    L ''
    foreach ($a in $aprendizado) { L "### $($a.Caminho)"; L ''; L $a.Texto; L '' }
    L '## Exemplos do historico (planos aprovados de cards da mesma area)'
    L ''
    if ($exemplos.Count -eq 0) { L '- nenhum ainda' } else { foreach ($e in $exemplos) { L "- $e" } }
    L ''
    L '## Diff'
    L ''
    L "Arquivo: $pastaRel/diff.txt ($linhasDiff linhas, ja decodificado: .java em Cp1252, resto em UTF-8). Leia em partes se for grande."
    Gravar-Texto (Join-Path $dirOut 'contexto.md') (($md -join "`n") + "`n")

    $ctx = [ordered]@{
        card = $ref.Url; projeto = $ref.Projeto; projetoId = $projetoId; iid = $ref.Iid; pasta = $pastaRel
        titulo = $titulo
        branch = [ordered]@{ nome = $Branch; ref = $b.Ref; sha = $b.Sha }
        base = [ordered]@{ nome = $Base; ref = $bs.Ref; sha = $bs.Sha }
        mergeBase = $mb; commits = $commits.Count; areas = $areas
        banco = [ordered]@{ indicio = $banco.Indicio; scripts = $banco.Scripts; novos = @($banco.Novos | ForEach-Object { $_.Nome }) }
        criteriosExtraidos = $criterios
        wiki = @($paginasWiki | ForEach-Object { [ordered]@{ titulo = $_.Titulo; arquivo = $_.Arquivo } })
        wikiAtualizadaEm = $(if ($indiceWiki) { [string]$indiceWiki.atualizadoEm } else { '' })
        coletadoEm = (Get-Date).ToString('yyyy-MM-dd HH:mm')
    }
    Gravar-Json (Join-Path $dirOut 'contexto.json') $ctx

    # ---- resumo no console ----
    Escrever-Titulo "Commits ($($commits.Count))"
    $mostrar = @($commits | Select-Object -First 20)
    foreach ($c in $mostrar) { Write-Host ("{0} {1} {2,-20} {3}" -f $c.Sha, $c.Data, (Celula $c.Autor 20), (Celula $c.Assunto 90)) }
    if ($commits.Count -gt $mostrar.Count) { Write-Host "... e mais $($commits.Count - $mostrar.Count)" }
    Escrever-Titulo 'Alertas'
    if ($alertas.Count -eq 0) { Write-Host 'nenhum' } else { foreach ($x in $alertas) { Write-Host "- $x" } }
    Escrever-Titulo 'Resumo'
    Write-Host "Arquivos: $($arquivos.Count) | Áreas: $($areas -join ', ') | Indício de banco: $ind | Critérios extraídos: $($criterios.Count)"
    Write-Host "Contexto: $pastaRel/contexto.md"
    if ($indiceWiki) { Write-Host "Wiki:     $($paginasWiki.Count) página(s) relacionada(s) ao card, listadas no contexto" }
    Write-Host "Diff:     $pastaRel/diff.txt"
    Write-Host ''
    Write-Host 'PRÓXIMO PASSO: confirmar com o dev que os commits acima são do card.'
}

function Exemplos-DoHistorico([string[]]$Areas, [string]$PastaAtual) {
    $dir = Join-Path $script:Raiz 'historico'
    if (-not (Test-Path -LiteralPath $dir)) { return ,@() }
    $cands = @()
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter '*.md' | Sort-Object LastWriteTime -Descending)) {
        if ($f.BaseName -eq $PastaAtual) { continue }
        $linha = @((Ler-Texto $f.FullName) -split "\r?\n" | Where-Object { $_ -match '^areas:' } | Select-Object -First 1)
        if ($linha.Count -eq 0) { continue }
        $as = @(($linha[0] -replace '^areas:\s*', '') -split '\s*,\s*' | Where-Object { $_ })
        if (@($as | Where-Object { $Areas -contains $_ }).Count -gt 0) { $cands += ('historico/' + $f.Name) }
        if ($cands.Count -ge 2) { break }
    }
    return ,$cands
}
