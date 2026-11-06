# card-sigcon - avaliacao tecnica de um card, antes do desenvolvimento.
# Nao ha branch do card nem diff: o agente le a HU, a wiki e o codigo de uma branch de
# referencia (escolhida pelo dev) e escreve a avaliacao (impacto, riscos, estimativa). O
# script coleta e, no publicar, poe a etiqueta de pontos aprovada, conclui o card filho
# "Avaliação Técnica" (regra da DSG) com a avaliacao como nota interna nele e move o card.
# Pasta: out/<projeto>-<n>-avaliacao/ (separada da do desenvolvimento do mesmo card).
# Salvo em UTF-8 com BOM (ver lib/Comum.ps1).

function Pasta-SaidaAvaliacao($Ref) { return (Pasta-Saida $Ref) + '-avaliacao' }

# Etiquetas de pontos do projeto, do menor para o maior: { Pontos, Nome }.
function Etiquetas-DePontos($Etiquetas) {
    $lista = @()
    foreach ($e in @($Etiquetas)) {
        $n = [string]$e.name
        if (-not [regex]::IsMatch($n, $script:Cfg.quadro.regexEtiquetaPontos)) { continue }
        $m = [regex]::Match($n, '^\s*(\d+)')
        if ($m.Success) { $lista += [pscustomobject]@{ Pontos = [int]$m.Groups[1].Value; Nome = $n } }
    }
    return ,@($lista | Sort-Object Pontos)
}

# Avaliacoes tecnicas ja feitas no projeto (os filhos "... - Avaliação Técnica" levam a
# etiqueta de pontos do pai): titulo do pai e pontos, para o agente comparar a estimativa.
function Avaliacoes-Anteriores([int]$ProjetoId, [int]$IidAtual) {
    $atividade = [string]$script:Cfg.avaliacao.atividade
    $max = [int]$script:Cfg.avaliacao.maxAnteriores; if ($max -le 0) { $max = 25 }
    $termo = [uri]::EscapeDataString($atividade)
    $achados = Invoke-Gitlab -Caminho "/projects/$ProjetoId/issues?search=$termo&in=title&per_page=$max&order_by=updated_at&state=all"
    $lista = @()
    $fim = Normalizar-Texto $atividade
    foreach ($i in @($achados)) {
        if (-not $i) { continue }
        if (-not (Normalizar-Texto $i.title).EndsWith($fim)) { continue }
        $pontos = Etiqueta-Pontos $i
        if (-not $pontos) { continue }
        $titulo = ([string]$i.title) -replace '^\s*#\s*', ''
        $titulo = ([regex]::Replace($titulo, '\s*[-–]\s*' + [regex]::Escape($atividade) + '\s*$', '', 'IgnoreCase')).Trim()
        if ($titulo -match ('#' + $IidAtual + '\b')) { continue }
        $lista += [pscustomobject]@{ Titulo = $titulo; Pontos = $pontos; Filho = $i.iid }
    }
    return ,$lista
}

function Comando-ColetarAvaliacao {
    param([string]$Card, [string]$Ref, [string]$Repo, [switch]$SemFetch)
    $cfg = $script:Cfg
    if (-not $Card -or -not $Ref) { throw 'Informe -Card e -Ref (a branch com o código atual do módulo, ex.: master ou feature/registro-execucao/geral-merge).' }
    if (-not $Repo) { $Repo = $cfg.repoPadrao }
    if (-not (Test-Path -LiteralPath (Join-Path $Repo '.git'))) { throw "Repositório git não encontrado em $Repo (use -Repo)." }
    $cardRef = Ler-ReferenciaCard $Card
    $dirOut = Pasta-SaidaAvaliacao $cardRef
    $pastaRel = Caminho-Relativo $dirOut

    Escrever-Titulo "Git ($Repo)"
    if (-not $SemFetch -and $Ref -notmatch '^[0-9a-f]{7,40}([~^]\d*)*$') {
        Write-Host "git fetch origin $Ref"
        $f = Invoke-Git $Repo @('fetch', '--quiet', 'origin', $Ref) -PermitirFalha
        if ($f.Codigo -ne 0) { Avisar "fetch de '$Ref' falhou; seguindo com o que existe localmente. $($f.Erro.Trim())" }
    }
    $r = Resolver-Ref $Repo $Ref @('refs/remotes/origin/', 'refs/heads/', '')
    if (-not $r) { throw "Referência '$Ref' não encontrada (nem no origin nem local)." }
    $sha10 = $r.Sha.Substring(0, 10)
    Write-Host "Referência: $Ref ($($r.Ref), $sha10)"

    Escrever-Titulo 'GitLab'
    $projetoId = Obter-ProjetoId $cardRef
    $issue = Invoke-Gitlab -Caminho "/projects/$projetoId/issues/$($cardRef.Iid)"
    $notas = Notas-Humanas (Invoke-Gitlab -Caminho "/projects/$projetoId/issues/$($cardRef.Iid)/notes?sort=asc&order_by=created_at&per_page=100" -Todas)
    $links = Invoke-Gitlab -Caminho "/projects/$projetoId/issues/$($cardRef.Iid)/links" -Todas
    Write-Host "Card #$($issue.iid): $($issue.title)"
    $avaliacoesFilho = @()
    try { $avaliacoesFilho = Avaliacoes-DosFilhos $projetoId $links } catch { Avisar "não consegui ler a avaliação anterior do card filho ($($_.Exception.Message))." }
    $criterios = Extrair-Criterios $issue.description
    $escala = Etiquetas-DePontos (Listar-Etiquetas $projetoId)
    $anteriores = @()
    try { $anteriores = Avaliacoes-Anteriores $projetoId $cardRef.Iid } catch { Avisar "não consegui ler as avaliações anteriores ($($_.Exception.Message))." }

    $paginasWiki = @()
    try {
        $w = Atualizar-Wiki
        if ($w.Baixou) { Write-Host "Wiki atualizada: $($w.Paginas) páginas." }
    } catch { Avisar "não consegui atualizar a wiki ($($_.Exception.Message)); uso a cópia que já existe, se houver." }
    $textoCard = (@([string]$issue.title, [string]$issue.description) + @($notas | ForEach-Object { [string]$_.body })) -join "`n"
    $paginasWiki = Paginas-DaWiki $textoCard
    $indiceWiki = Ler-IndiceWiki

    $aprendizado = @()
    foreach ($n in @($cfg.avaliacao.aprendizado)) {
        $p = Join-Path $script:Raiz "aprendizado\$n.md"
        if (Test-Path -LiteralPath $p) { $aprendizado += [pscustomobject]@{ Caminho = "aprendizado/$n.md"; Texto = (Ler-Texto $p).Trim() } }
    }

    $md = New-Object System.Collections.ArrayList
    function L([string]$t = '') { [void]$md.Add($t) }
    $milestone = ''; if ($issue.milestone) { $milestone = $issue.milestone.title }
    L "# Contexto da avaliacao tecnica do card #$($cardRef.Iid) - $($issue.title)"
    L ''
    L "- Card: $($cardRef.Url)"
    L "- Estado: $($issue.state) | Coluna: $(Coluna-Atual $issue) | Pontos hoje: $(Etiqueta-Pontos $issue) | Milestone: $milestone"
    L "- Etiquetas: $(@($issue.labels) -join ', ')"
    L "- Referencia de codigo: ``$Ref`` ($($r.Ref), commit $sha10)"
    L "- Repositorio: $Repo"
    L "- Pasta de saida: $pastaRel (grave aqui avaliacao-tecnica.md e decisao-avaliacao.json)"
    L ''
    # os exemplos de comando ficam no steering (avaliacao-tecnica.md): o antivirus da
    # Prodemge bloqueia este .ps1 se ele tiver texto com comandos de git montados
    L "**Leia o codigo SEMPRE no commit $sha10 da referencia, nao na pasta do repositorio** (ela pode estar em outra branch). Como ler: veja o steering avaliacao-tecnica.md."
    L ''
    L '## Criterios de aceite extraidos (confirmar o escopo com o dev)'
    L ''
    if ($criterios.Count -eq 0) { L '- Nenhum criterio reconhecido automaticamente: extraia da descricao e dos comentarios abaixo.' }
    else { foreach ($c in $criterios) { L "- **$($c.id)** $($c.texto)" } }
    L ''
    L '## Descricao do card'
    L ''
    L ([string]$issue.description)
    L ''
    L "## Comentarios do card ($($notas.Count), mais antigos primeiro)"
    L ''
    foreach ($n in $notas) { L "### $($n.author.name) - $($n.created_at)"; L ''; L ([string]$n.body); L '' }
    if (@($avaliacoesFilho).Count) {
        L '## Avaliacao tecnica ja publicada (nota interna no card filho): parta dela e diga o que mudou'
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
    L '## Wiki (documentacao do sistema)'
    L ''
    if (-not $indiceWiki) { L '- wiki nao baixada (o dev roda card.cmd wiki ou o botao Atualizar wiki da pagina).' }
    else {
        if ($paginasWiki.Count -eq 0) { L '- nenhuma pagina casou com o card: procure a tela em wiki/_indice.md ou com grep em wiki/.' }
        else { foreach ($p in $paginasWiki) { L "- $($p.Titulo): ``$($p.Arquivo)`` ($($p.Motivo))" } }
        L ''
        L "A wiki inteira esta em wiki/ (indice em wiki/_indice.md, copia de $(Data-Legivel ([string]$indiceWiki.atualizadoEm)))."
    }
    L ''
    L '## Classes compartilhadas (mexer nelas e risco: afeta outros fluxos)'
    L ''
    foreach ($c in @($cfg.classesCompartilhadas)) { L "- ``$($c.padrao)``: $($c.motivo)" }
    L ''
    L '## Escala de pontos do quadro'
    L ''
    if ($escala.Count -eq 0) { L '- nenhuma etiqueta de pontos encontrada no projeto' } else { L ((@($escala | ForEach-Object { $_.Nome })) -join ' | ') }
    L ''
    L "## Avaliacoes tecnicas anteriores neste projeto ($($anteriores.Count)) - para comparar a estimativa"
    L ''
    if ($anteriores.Count -eq 0) { L '- nenhuma' } else {
        L '| pontos | card avaliado |'
        L '|---|---|'
        foreach ($a in $anteriores) { L "| $($a.Pontos) | $(Celula $a.Titulo 200) |" }
    }
    L ''
    L '## Aprendizado aplicavel (respeite; proponha correcao se algo estiver errado)'
    L ''
    foreach ($a in $aprendizado) { L "### $($a.Caminho)"; L ''; L $a.Texto; L '' }
    Gravar-Texto (Join-Path $dirOut 'contexto.md') (($md -join "`n") + "`n")

    $ctx = [ordered]@{
        modo = 'avaliacao'; card = $cardRef.Url; projeto = $cardRef.Projeto; projetoId = $projetoId; iid = $cardRef.Iid; pasta = $pastaRel
        titulo = $issue.title
        referencia = [ordered]@{ nome = $Ref; ref = $r.Ref; sha = $r.Sha }
        pontosHoje = (Etiqueta-Pontos $issue); colunaHoje = (Coluna-Atual $issue)
        criteriosExtraidos = $criterios
        wiki = @($paginasWiki | ForEach-Object { [ordered]@{ titulo = $_.Titulo; arquivo = $_.Arquivo } })
        escalaPontos = @($escala | ForEach-Object { $_.Nome })
        coletadoEm = (Get-Date).ToString('yyyy-MM-dd HH:mm')
    }
    Gravar-Json (Join-Path $dirOut 'contexto.json') $ctx

    Escrever-Titulo 'Resumo'
    Write-Host "Critérios extraídos: $($criterios.Count) | Páginas da wiki: $($paginasWiki.Count) | Avaliações anteriores: $($anteriores.Count)"
    Write-Host "Contexto: $pastaRel/contexto.md"
    Write-Host ''
    Write-Host 'PRÓXIMO PASSO: resumir o escopo e confirmar com o dev.'
}

function Comando-PublicarAvaliacao {
    param([string]$Card, [switch]$Executar, [string]$Coluna, [int]$Pontos, [switch]$SemFilho, [switch]$NovoFilho)
    $cfg = $script:Cfg
    $cardRef = Ler-ReferenciaCard $Card
    $dirOut = Pasta-SaidaAvaliacao $cardRef
    $rel = Caminho-Relativo $dirOut
    foreach ($arq in @('contexto.json', 'avaliacao-tecnica.md', 'decisao-avaliacao.json')) {
        if (-not (Test-Path -LiteralPath (Join-Path $dirOut $arq))) { throw "Falta $rel/$arq. Rode o avaliar e deixe o agente gravar avaliacao-tecnica.md e decisao-avaliacao.json." }
    }
    $ctx = Ler-Json (Join-Path $dirOut 'contexto.json')
    $decisao = Ler-Json (Join-Path $dirOut 'decisao-avaliacao.json')
    if ($decisao.confirmadoPeloDev -ne $true) { throw 'decisao-avaliacao.json: confirmadoPeloDev precisa ser true. O dev aprova os pontos antes de publicar.' }
    if (-not $Pontos) { $Pontos = [int]$decisao.pontos }
    if ($Pontos -le 0) { throw 'Sem pontos: o agente grava "pontos" no decisao-avaliacao.json, ou informe -Pontos.' }
    $texto = (Ler-Texto (Join-Path $dirOut 'avaliacao-tecnica.md')).Trim()
    if (-not $texto) { throw "$rel/avaliacao-tecnica.md está vazio." }

    $projetoId = Obter-ProjetoId $cardRef
    $iid = $cardRef.Iid
    $issue = Invoke-Gitlab -Caminho "/projects/$projetoId/issues/$iid"
    $links = Invoke-Gitlab -Caminho "/projects/$projetoId/issues/$iid/links" -Todas
    $notas = Invoke-Gitlab -Caminho "/projects/$projetoId/issues/$iid/notes?sort=asc&order_by=created_at&per_page=100" -Todas
    $eu = Invoke-Gitlab -Caminho '/user'
    $etiquetas = Listar-Etiquetas $projetoId

    Escrever-Titulo "Avaliação técnica do card #$iid - $($issue.title)"
    Write-Host "Coluna: $(Coluna-Atual $issue) | Pontos hoje: $(Etiqueta-Pontos $issue) | Você: $($eu.username)"
    $acoes = New-Object System.Collections.ArrayList

    # 1. etiqueta de pontos aprovada (troca a anterior)
    $escala = Etiquetas-DePontos $etiquetas
    $alvo = @($escala | Where-Object { $_.Pontos -eq $Pontos }) | Select-Object -First 1
    if (-not $alvo) { throw "Não há etiqueta de $Pontos ponto(s) no projeto. Escala: $(@($escala | ForEach-Object { $_.Nome }) -join ', ')." }
    if (-not (Tem-Etiqueta $issue $alvo.Nome)) {
        $tirar = @($issue.labels | Where-Object { [regex]::IsMatch($_, $cfg.quadro.regexEtiquetaPontos) })
        $de = ''; if ($tirar.Count) { $de = " (tira '$($tirar -join ', ')')" }
        [void]$acoes.Add([pscustomobject]@{ Tipo = 'etiquetas-pai'; Descricao = "Pôr a etiqueta de pontos '$($alvo.Nome)' no card$de"; Adicionar = @($alvo.Nome); Remover = $tirar })
    } else {
        Write-Host "O card já tem a etiqueta '$($alvo.Nome)'."
    }

    # 2. card filho "Avaliação Técnica" com os pontos aprovados, e a avaliacao como nota interna
    # NO FILHO (so neste fluxo; o fechamento comenta no pai). Filho novo: a nota sai junto com a
    # criacao. Filho existente: o aberto que sera concluido, ou o mais recente. Sem filho nenhum
    # (Nao mexer em card filho e nenhum existente): a nota vai no pai.
    $corpo = $cfg.textos.marcadorAvaliacao + "`n" + $texto
    $corpoFinal = Texto-ParaPublicar $dirOut 'nota-avaliacao' $corpo ([bool]$Executar)
    $atividade = [string]$cfg.avaliacao.atividade
    $acoesFilho = @()
    if (-not $SemFilho) { $acoesFilho = Acoes-Filho $issue $links $eu $etiquetas $atividade ([bool]$NovoFilho) $alvo.Nome }
    $criar = @($acoesFilho | Where-Object { $_.Tipo -eq 'filho-criar' }) | Select-Object -First 1
    $antigasPai = Minhas-Avaliacoes $notas $eu
    $obsPai = ''; if (@($antigasPai).Count) { $obsPai = " (a avaliação anterior no card pai, nota $(@($antigasPai)[-1].id), fica como está)" }
    $acaoNota = $null
    if ($criar) {
        $criar | Add-Member -NotePropertyName NotaInterna -NotePropertyValue $corpoFinal -Force
        $criar.Descricao = $criar.Descricao + ', com a avaliação técnica como nota interna nele' + $obsPai
    } else {
        $filhos = Filhos-DaAtividade $links $atividade
        $abertos = @(@($filhos) | Where-Object { $_.state -eq 'opened' })
        $filho = $null
        if ($abertos.Count) { $filho = $abertos | Sort-Object { [int]$_.iid } | Select-Object -Last 1 }
        elseif (@($filhos).Count) { $filho = @($filhos) | Sort-Object { [int]$_.iid } | Select-Object -Last 1 }
        $ondeIid = $iid; $onde = 'no card pai'; $obs = ''; $anteriores = $antigasPai
        if ($filho) {
            $ondeIid = [int]$filho.iid; $onde = "no filho #$($filho.iid)"; $obs = $obsPai
            $anteriores = Minhas-Avaliacoes (Invoke-Gitlab -Caminho "/projects/$projetoId/issues/$ondeIid/notes?sort=asc&order_by=created_at&per_page=100" -Todas) $eu
        } else {
            Avisar 'não há card filho da avaliação (e "Não mexer em card filho" está marcado): a nota interna vai no card pai.'
        }
        # nota interna nao vira comentario (nem o contrario) pela API: so atualiza a anterior interna
        $anterior = @(@($anteriores) | Where-Object { $_.internal -eq $true } | Select-Object -Last 1)
        if ($anterior.Count) {
            $acaoNota = [pscustomobject]@{ Tipo = 'comentario-atualizar'; IssueIid = $ondeIid; NotaId = $anterior[0].id; Corpo = $corpoFinal; Descricao = "Atualizar a nota interna da avaliação técnica $onde (nota $($anterior[0].id))" }
        } else {
            $acaoNota = [pscustomobject]@{ Tipo = 'nota-interna'; IssueIid = $ondeIid; Corpo = $corpoFinal; Descricao = "Gravar a avaliação técnica como nota interna $onde$obs" }
        }
    }
    # a nota entra antes de concluir (fechar) o filho
    if ($acaoNota) { [void]$acoes.Add($acaoNota) }
    foreach ($a in @($acoesFilho)) { [void]$acoes.Add($a) }

    # 3. coluna
    if ($Coluna) {
        $acaoColuna = Acao-MoverColuna $projetoId $issue $Coluna
        if ($acaoColuna) { [void]$acoes.Add($acaoColuna) }
    }

    Escrever-Titulo "Ações ($($acoes.Count))"
    $i = 0
    foreach ($a in $acoes) { $i++; Write-Host "$i. $($a.Descricao)" }
    Gravar-Texto (Join-Path $dirOut 'nota-avaliacao.md') $corpo
    Write-Host ''
    Write-Host "Texto da nota interna: $rel/nota-avaliacao.md"
    if (-not $Executar) {
        Write-Host ''
        Write-Host 'SIMULAÇÃO: nada foi gravado no GitLab. Para gravar, use Publicar com as mesmas opções.'
        return
    }

    Escrever-Titulo 'Gravando no GitLab'
    $i = 0
    foreach ($a in $acoes) {
        $i++
        Write-Host "$i. $($a.Descricao)"
        try { Executar-Acao $a $projetoId $iid }
        catch { throw "Parou na ação $i ($($a.Descricao)): $($_.Exception.Message). As ações anteriores já foram gravadas." }
    }
    # historico: a avaliacao fica para comparar, no fechamento, o previsto com o feito
    $hist = Join-Path $script:Raiz ('historico\' + (Nome-PastaCard $cardRef) + '-avaliacao.md')
    $cab = @("# #$iid - $($issue.title)", '', 'tipo: avaliacao-tecnica', "data: $((Get-Date).ToString('yyyy-MM-dd'))",
        "referencia: $($ctx.referencia.nome) ($(([string]$ctx.referencia.sha).Substring(0, 10)))", "pontos: $($alvo.Nome)", '')
    # o que foi publicado (com a edicao do dev, se houve), sem o marcador
    Gravar-Texto $hist ((($cab + @(($corpoFinal -replace '^\s*<!--[^>]*-->\s*', ''))) -join "`n") + "`n")
    Write-Host ''
    Write-Host "Pronto. Histórico: $(Caminho-Relativo $hist)"
}
