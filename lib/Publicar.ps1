# card-sigcon - comandos "simular" e "publicar".
# Le o que o agente gravou (plano.md + decisao.json), aplica as regras fixas do quadro
# e monta a lista de acoes. "simular" so mostra; "publicar" grava no GitLab.

$script:SituacoesValidas = @('atendido', 'parcial', 'nao_atendido', 'verificar_no_teste', 'nao_encontrado')
$script:SituacoesPendentes = @('parcial', 'nao_atendido', 'nao_encontrado')

function Validar-Decisao($Decisao, [bool]$Mover) {
    $crit = @($Decisao.criterios)
    if ($crit.Count -eq 0) { throw 'decisao.json sem critérios: o agente precisa gravar a avaliação por critério.' }
    foreach ($c in $crit) {
        if ($script:SituacoesValidas -notcontains $c.situacao) { throw "decisao.json: critério $($c.id) com situação inválida '$($c.situacao)' (válidas: $($script:SituacoesValidas -join ', '))." }
    }
    if (-not $Decisao.banco -or $Decisao.banco.confirmadoPeloDev -ne $true) {
        throw 'decisao.json: banco.confirmadoPeloDev precisa ser true. O dev confirma a parte de banco antes de publicar.'
    }
    $pend = @($crit | Where-Object { $script:SituacoesPendentes -contains $_.situacao })
    if ($Mover -and $pend.Count -gt 0 -and -not ([string]$Decisao.justificativaPendencias).Trim()) {
        throw "Há $($pend.Count) critério(s) pendente(s) ($(@($pend | ForEach-Object { $_.id }) -join ', ')). O card só muda de coluna com justificativaPendencias preenchida no decisao.json."
    }
    return ,$pend
}

# A secao "Execucao pelo dev" (out/<pasta>/execucao.md, escrita pelo agente a partir das
# marcacoes da pagina) entra no plano antes do primeiro cenario. Fica num arquivo
# separado para o agente nao precisar editar o plano.md no meio.
function Juntar-Execucao([string]$Plano, [string]$DirOut) {
    $arq = Join-Path $DirOut 'execucao.md'
    if (-not (Test-Path -LiteralPath $arq)) { return $Plano }
    $secao = (Ler-Texto $arq).Trim()
    if (-not $secao) { return $Plano }
    $linhas = @($Plano -split "\r?\n")
    for ($i = 0; $i -lt $linhas.Count; $i++) {
        if ($linhas[$i] -match '^#{2,4}\s+\**Cen.rio\s*\d') {
            $antes = @(); if ($i -gt 0) { $antes = $linhas[0..($i - 1)] }
            return (($antes + @($secao, '') + $linhas[$i..($linhas.Count - 1)]) -join "`n")
        }
    }
    return ($Plano.TrimEnd() + "`n`n" + $secao)
}

# Comentario do card: plano + criterios cobertos + observacao do dev. Sem assinatura nem
# rodape de ferramenta (decisao do time): o unico rastro e o marcador HTML invisivel,
# usado para atualizar o mesmo comentario em vez de criar outro.
function Montar-ComentarioPlano([string]$Plano, $Decisao) {
    $t = $script:Cfg.textos
    $linhas = @($t.marcadorPlano)
    $primeira = (($Plano.TrimStart() -split "\r?\n")[0])
    if ((Normalizar-Texto $primeira) -notmatch 'plano de teste') { $linhas += $t.cabecalhoPlano; $linhas += '' }
    $linhas += $Plano.TrimEnd()
    $final = @()
    $cobertos = @($Decisao.criterios | Where-Object { ([string]$_.teste).Trim() } | ForEach-Object { $_.id })
    if ($cobertos.Count -gt 0) { $final += (Preencher $t.criteriosCobertos @{ lista = ($cobertos -join ', ') }) }
    $just = ([string]$Decisao.justificativaPendencias).Trim()
    if ($just) { $final += (Preencher $t.observacaoDev @{ texto = $just }) }
    if ($final.Count -gt 0) { $linhas += ''; $linhas += '---'; $linhas += ($final -join "`n`n") }
    return ($linhas -join "`n")
}

# ---------------- evidencias dos testes (fotos e videos por cenario) ----------------
# A pagina grava em out/<card>/evidencias/cenario-<N>/. No comentario elas entram no fim de
# cada cenario como evidencia:<cenario>/<arquivo>: a previa da pagina mostra o arquivo
# local, e o Publicar troca pelo link do GitLab depois de enviar.

function Evidencias-DoCard([string]$DirOut) {
    $r = [ordered]@{}
    $raiz = Join-Path $DirOut 'evidencias'
    if (-not (Test-Path -LiteralPath $raiz)) { return $r }
    $exts = @($script:Cfg.evidencias.extensoes)
    $pastas = @(Get-ChildItem -LiteralPath $raiz -Directory | Where-Object { $_.Name -match '^cenario-\d+$' } | Sort-Object { [int]($_.Name -replace '\D', '') })
    foreach ($d in $pastas) {
        $arqs = @(Get-ChildItem -LiteralPath $d.FullName -File | Where-Object { $exts -contains $_.Extension.ToLowerInvariant() } | Sort-Object CreationTime, Name)
        if ($arqs.Count) { $r[$d.Name] = $arqs }
    }
    return $r
}

function Juntar-Evidencias([string]$Plano, $Evidencias) {
    if ($Evidencias.Count -eq 0) { return $Plano }
    $saida = New-Object System.Collections.ArrayList
    $usadas = @{}
    $chave = $null
    foreach ($l in @(($Plano -split "\r?\n") + @('#FIM'))) {
        if ($l -match '^#{1,4}\s|^#FIM$') {
            if ($chave -and $Evidencias.Contains($chave)) {
                while ($saida.Count -gt 0 -and -not ([string]$saida[$saida.Count - 1]).Trim()) { $saida.RemoveAt($saida.Count - 1) }
                [void]$saida.Add(''); [void]$saida.Add($script:Cfg.textos.tituloEvidencias); [void]$saida.Add('')
                foreach ($a in $Evidencias[$chave]) { [void]$saida.Add("![$($a.Name)](evidencia:$chave/$($a.Name))"); [void]$saida.Add('') }
                $usadas[$chave] = $true
            }
            $chave = $null
            $m = [regex]::Match($l, '^#{2,4}\s+\**Cen.rio\s*(\d+)')
            if ($m.Success) { $chave = 'cenario-' + $m.Groups[1].Value }
        }
        if ($l -ne '#FIM') { [void]$saida.Add($l) }
    }
    foreach ($k in $Evidencias.Keys) { if (-not $usadas[$k]) { Avisar "há evidência em $k, mas o plano não tem esse cenário: ela fica fora do comentário." } }
    return (($saida -join "`n").TrimEnd())
}

function Hash-Arquivo([string]$Caminho) { return (Get-FileHash -LiteralPath $Caminho -Algorithm SHA256).Hash }

function Tamanho-Legivel([double]$Bytes) {
    if ($Bytes -lt 1MB) { return ('{0} KB' -f [math]::Max(1, [math]::Round($Bytes / 1KB))) }
    return ('{0:N1} MB' -f ($Bytes / 1MB))
}

# out/<card>/evidencias-gitlab.json: hash do arquivo -> markdown devolvido pelo GitLab, para
# publicar de novo sem enviar o mesmo arquivo outra vez.
function Ler-CacheEvidencias([string]$DirOut) {
    $r = @{}
    $p = Join-Path $DirOut 'evidencias-gitlab.json'
    if (Test-Path -LiteralPath $p) { foreach ($x in (Ler-Json $p).PSObject.Properties) { $r[$x.Name] = [string]$x.Value } }
    return $r
}

function Gravar-CacheEvidencias([string]$DirOut, [hashtable]$Cache) {
    Gravar-Json (Join-Path $DirOut 'evidencias-gitlab.json') $Cache
}

function Resolver-Evidencias([string]$Corpo, [string]$DirOut) {
    $cache = Ler-CacheEvidencias $DirOut
    return [regex]::Replace($Corpo, '!\[[^\]]*\]\(evidencia:(cenario-\d+)/([A-Za-z0-9._-]+)\)', {
            param($m)
            $p = Join-Path $DirOut ('evidencias\' + $m.Groups[1].Value + '\' + $m.Groups[2].Value)
            $h = Hash-Arquivo $p
            if (-not $cache.ContainsKey($h)) { throw "a evidência $($m.Groups[1].Value)/$($m.Groups[2].Value) não foi enviada ao GitLab." }
            return $cache[$h]
        })
}

# ---------------- SQL do banco (nota interna) ----------------

# .sql do SIGCON pode estar em Cp1252: tenta UTF-8 estrito e cai para windows-1252.
function Texto-DeBytes([byte[]]$Bytes) {
    $estrito = New-Object System.Text.UTF8Encoding($false, $true)
    try { return $estrito.GetString($Bytes).TrimStart([char]0xFEFF) }
    catch { return [System.Text.Encoding]::GetEncoding(1252).GetString($Bytes) }
}

# Scripts de banco.scripts do decisao.json (caminhos relativos ao repositorio do SIGCON):
# vale o arquivo commitado na branch, que e o que vai para producao; se nao estiver na
# branch, o da pasta do repositorio, com aviso. Mais o out/<card>/banco.sql, que o agente
# grava quando o dev passou o SQL na conversa.
function Scripts-DeBanco($Decisao, $Ctx, [string]$DirOut) {
    $repo = $script:Cfg.repoPadrao
    $ponta = [string]$Ctx.branch.ref; if (-not $ponta) { $ponta = [string]$Ctx.branch.sha }
    $lista = @()
    foreach ($s in @($Decisao.banco.scripts | Where-Object { ([string]$_).Trim() })) {
        $caminho = ([string]$s).Trim() -replace '\\', '/'
        $texto = $null
        if (-not [System.IO.Path]::IsPathRooted($caminho) -and $caminho -notmatch '(^|/)\.\.(/|$)') {
            $r = Invoke-Git $repo @('cat-file', '-p', "${ponta}:$caminho") -PermitirFalha
            if ($r.Codigo -eq 0) {
                $texto = Texto-DeBytes ($script:Latin1.GetBytes($r.Saida))
            } else {
                $local = Join-Path $repo $caminho
                if (Test-Path -LiteralPath $local -PathType Leaf) {
                    $texto = Texto-DeBytes ([System.IO.File]::ReadAllBytes($local))
                    Avisar "$caminho não está commitado na branch: a nota interna leva a versão da pasta do repositório. Commite o script antes de publicar."
                }
            }
        }
        if ($null -eq $texto) { Avisar "script de banco '$caminho' não encontrado na branch nem na pasta do repositório: fica fora da nota interna."; continue }
        $lista += [pscustomobject]@{ Titulo = "**``$caminho``**"; Texto = $texto.TrimEnd() }
    }
    $doDev = Join-Path $DirOut 'banco.sql'
    if (Test-Path -LiteralPath $doDev) {
        $t = (Ler-Texto $doDev).TrimEnd()
        if ($t) { $lista += [pscustomobject]@{ Titulo = '**SQL informado pelo dev**'; Texto = $t } }
    }
    return ,$lista
}

function Montar-NotaBanco($Scripts, $Decisao) {
    $t = $script:Cfg.textos
    $linhas = @($t.marcadorBanco, $t.cabecalhoBanco, '')
    $obs = ([string]$Decisao.banco.observacao).Trim()
    if ($obs) { $linhas += $obs; $linhas += '' }
    foreach ($s in $Scripts) {
        $cerca = '```'; if ($s.Texto.Contains('```')) { $cerca = '````' }
        $linhas += $s.Titulo; $linhas += ''
        $linhas += ($cerca + 'sql'); $linhas += $s.Texto; $linhas += $cerca; $linhas += ''
    }
    return (($linhas -join "`n").TrimEnd())
}

# Texto que o dev editou na pre-visualizacao (out/<card>/<nome>.editado.md) no lugar do
# gerado. Vale so enquanto o gerado for o mesmo de quando ele editou (<nome>.editado.base
# guarda o hash): se o plano ou a avaliacao mudaram depois, a edicao estaria velha.
function Texto-ParaPublicar([string]$DirOut, [string]$Nome, [string]$Gerado, [bool]$Executar) {
    $arq = Join-Path $DirOut "$Nome.editado.md"
    if (-not (Test-Path -LiteralPath $arq)) { return $Gerado }
    $base = ''
    $pb = Join-Path $DirOut "$Nome.editado.base"
    if (Test-Path -LiteralPath $pb) { $base = (Ler-Texto $pb).Trim() }
    if ($base -ne (Hash-Texto $Gerado)) {
        $msg = "o texto gerado ($Nome) mudou depois da sua edição: revise na pré-visualização e salve de novo, ou volte ao texto gerado."
        if ($Executar) { throw "Não publiquei: $msg" }
        Avisar $msg
        return $Gerado
    }
    Write-Host "Usando o texto editado por você ($Nome)."
    return (Ler-Texto $arq)
}

# Card filho da atividade (regra da DSG): conclui o filho aberto dessa atividade, ou cria um
# com a etiqueta de pontos do pai (ou a informada) + feito, milestone do pai, responsavel =
# quem publica, ligado ao pai e ja fechado. Usado pelo fechamento e pela avaliacao tecnica.
function Acoes-Filho($Issue, $Links, $Eu, $Etiquetas, [string]$Atividade, [bool]$NovoFilho, [string]$EtiquetaPontos) {
    $cfg = $script:Cfg
    $iid = $Issue.iid
    $acoes = @()
    $feito = Achar-Etiqueta $Etiquetas $cfg.quadro.etiquetaFeito
    if (-not $feito) { $feito = $cfg.quadro.etiquetaFeito }
    $filhos = Filhos-DaAtividade $Links $Atividade
    $abertos = @($filhos | Where-Object { $_.state -eq 'opened' })
    if ($filhos.Count -gt 0 -and -not $NovoFilho) {
        foreach ($f in $abertos) {
            $acoes += [pscustomobject]@{ Tipo = 'filho-concluir'; Descricao = "Concluir o filho #$($f.iid) '$($f.title)' (etiqueta $feito + fechar)"; FilhoIid = $f.iid; Feito = $feito }
        }
        if ($abertos.Count -eq 0) { Write-Host "Filho de '$Atividade' já existe e está fechado: $(@($filhos | ForEach-Object { '#' + $_.iid }) -join ', '). Nada a fazer (use -NovoFilho para criar outro)." }
    } else {
        $pontos = $EtiquetaPontos; if (-not $pontos) { $pontos = Etiqueta-Pontos $Issue }
        if (-not $pontos) { Avisar 'o card pai não tem etiqueta de pontos: o filho vai só com a etiqueta feito.' }
        $etqs = @(@($pontos, $feito) | Where-Object { $_ })
        $tituloFilho = Preencher $cfg.textos.tituloFilho @{ tituloPai = $Issue.title; atividade = $Atividade; iid = $iid }
        $milestoneId = $null; if ($Issue.milestone) { $milestoneId = $Issue.milestone.id }
        $acoes += [pscustomobject]@{
            Tipo = 'filho-criar'
            Descricao = "Criar o filho '$tituloFilho' [etiquetas: $($etqs -join ', ')] [milestone: $(if ($Issue.milestone) { $Issue.milestone.title } else { 'nenhum' })] [responsável: $($Eu.username)], ligar ao #$iid (relates_to) e fechar"
            Titulo = $tituloFilho
            DescricaoFilho = (Preencher $cfg.textos.descricaoFilho @{ atividade = $Atividade; iid = $iid; tituloPai = $Issue.title })
            Etiquetas = $etqs; MilestoneId = $milestoneId; ResponsavelId = $Eu.id
        }
    }
    return ,$acoes
}

# Mover para qualquer coluna do quadro do card (no GitLab, coluna = etiqueta). $null se o
# card ja esta nela.
function Acao-MoverColuna([int]$ProjetoId, $Issue, [string]$Coluna) {
    $quadro = Colunas-DoQuadro $ProjetoId $Issue
    $alvo = Normalizar-Texto $Coluna
    $destino = @($quadro.colunas | Where-Object { (Normalizar-Texto $_) -eq $alvo }) | Select-Object -First 1
    if (-not $destino) { throw "A coluna '$Coluna' não existe no quadro '$($quadro.quadro)' do card. Colunas: $($quadro.colunas -join ', ')." }
    if (Tem-Etiqueta $Issue $destino) { Write-Host "O card já está na coluna '$destino': nada a mover."; return $null }
    $colunasNorm = @($quadro.colunas | ForEach-Object { Normalizar-Texto $_ })
    $remover = @($Issue.labels | Where-Object { (($colunasNorm -contains (Normalizar-Texto $_)) -or (Eh-Coluna $_)) -and ((Normalizar-Texto $_) -ne $alvo) })
    $de = 'sem coluna'; if ($remover.Count) { $de = $remover -join ', ' }
    return [pscustomobject]@{ Tipo = 'etiquetas-pai'; Descricao = "Mover o card de '$de' para '$destino' (quadro $($quadro.quadro))"; Adicionar = @($destino); Remover = $remover }
}

function Comando-Publicar {
    param([string]$Card, [switch]$Executar, [switch]$Mover, [string]$Coluna, [string]$Atividade, [switch]$SemFilho, [switch]$NovoFilho)
    $cfg = $script:Cfg
    $ref = Ler-ReferenciaCard $Card
    $dirOut = Pasta-Saida $ref
    $rel = Caminho-Relativo $dirOut
    foreach ($arq in @('contexto.json', 'plano.md', 'decisao.json')) {
        if (-not (Test-Path -LiteralPath (Join-Path $dirOut $arq))) { throw "Falta $rel/$arq. Rode o coletar e deixe o agente gravar plano.md e decisao.json." }
    }
    $ctx = Ler-Json (Join-Path $dirOut 'contexto.json')
    $decisao = Ler-Json (Join-Path $dirOut 'decisao.json')
    $planoBruto = (Ler-Texto (Join-Path $dirOut 'plano.md')).Trim()
    $plano = Juntar-Execucao $planoBruto $dirOut
    $evidencias = Evidencias-DoCard $dirOut
    $planoCard = Juntar-Execucao (Juntar-Evidencias $planoBruto $evidencias) $dirOut
    $pend = Validar-Decisao $decisao ([bool]$Mover -or [bool]$Coluna)

    $projetoId = Obter-ProjetoId $ref
    $iid = $ref.Iid
    $issue = Invoke-Gitlab -Caminho "/projects/$projetoId/issues/$iid"
    $links = Invoke-Gitlab -Caminho "/projects/$projetoId/issues/$iid/links" -Todas
    $notas = Invoke-Gitlab -Caminho "/projects/$projetoId/issues/$iid/notes?sort=asc&order_by=created_at&per_page=100" -Todas
    $eu = Invoke-Gitlab -Caminho '/user'
    $etiquetas = Listar-Etiquetas $projetoId
    $colunaAtual = Coluna-Atual $issue

    Escrever-Titulo "Card #$iid - $($issue.title)"
    Write-Host "Coluna: $colunaAtual | Pontos: $(Etiqueta-Pontos $issue) | Você: $($eu.username)"
    if ($pend.Count -gt 0) { Avisar "critérios pendentes: $(@($pend | ForEach-Object { "$($_.id)=$($_.situacao)" }) -join ', ')" }

    $acoes = New-Object System.Collections.ArrayList

    # 0. evidencias: os arquivos sobem antes do comentario, que leva os links deles (so os
    #    de cenarios que estao no plano)
    $todasEvid = @($evidencias.Keys | Where-Object { $planoCard.Contains("](evidencia:$_/") } | ForEach-Object { $evidencias[$_] })
    if ($todasEvid.Count -gt 0) {
        $limiteMb = [double]$cfg.evidencias.tamanhoMaximoMb
        foreach ($a in $todasEvid) {
            if ($limiteMb -gt 0 -and $a.Length / 1MB -gt $limiteMb) { throw "A evidência $($a.Directory.Name)/$($a.Name) tem $([math]::Round($a.Length / 1MB, 1)) MB; o limite é $limiteMb MB (config evidencias.tamanhoMaximoMb)." }
        }
        $cache = Ler-CacheEvidencias $dirOut
        $novas = @($todasEvid | Where-Object { -not $cache.ContainsKey((Hash-Arquivo $_.FullName)) })
        if ($novas.Count -gt 0) {
            $tamanho = Tamanho-Legivel (($novas | Measure-Object Length -Sum).Sum)
            $jaEnviadas = ''; if ($todasEvid.Count -gt $novas.Count) { $jaEnviadas = "; $($todasEvid.Count - $novas.Count) já enviada(s) antes" }
            [void]$acoes.Add([pscustomobject]@{ Tipo = 'evidencias-enviar'; Descricao = "Enviar $($novas.Count) evidência(s) ao GitLab ($tamanho) para o comentário$jaEnviadas"; Arquivos = $novas; DirOut = $dirOut })
        } else {
            Write-Host "Evidências: as $($todasEvid.Count) já foram enviadas ao GitLab; o comentário reaproveita os links."
        }
    }

    # 1. plano no comentario (atualiza o comentario anterior do proprio dev, se houver)
    $corpo = Montar-ComentarioPlano $planoCard $decisao
    $corpoFinal = Texto-ParaPublicar $dirOut 'comentario-plano' $corpo ([bool]$Executar)
    $anterior = @($notas | Where-Object { -not $_.system -and $_.author.id -eq $eu.id -and ([string]$_.body).Contains($cfg.textos.marcadorPlano) } | Select-Object -Last 1)
    if ($anterior.Count -gt 0) {
        [void]$acoes.Add([pscustomobject]@{ Tipo = 'comentario-atualizar'; Descricao = "Atualizar o comentário do plano (nota $($anterior[0].id))"; NotaId = $anterior[0].id; Corpo = $corpoFinal })
    } else {
        [void]$acoes.Add([pscustomobject]@{ Tipo = 'comentario-novo'; Descricao = 'Comentar o plano de teste no card'; Corpo = $corpoFinal })
    }

    # 2. etiqueta de banco no pai
    if ($decisao.banco.haMudanca -eq $true) {
        $etqBanco = Achar-Etiqueta $etiquetas $cfg.quadro.etiquetaBanco
        if (-not $etqBanco) { Avisar "etiqueta '$($cfg.quadro.etiquetaBanco)' não existe no projeto: não vou etiquetar." }
        elseif (-not (Tem-Etiqueta $issue $etqBanco)) {
            [void]$acoes.Add([pscustomobject]@{ Tipo = 'etiquetas-pai'; Descricao = "Etiquetar o card com '$etqBanco'"; Adicionar = @($etqBanco); Remover = @() })
        }
    }

    # 2b. SQL do banco como nota interna (so membros do projeto veem; atualiza a anterior)
    $corpoBanco = ''
    if ($decisao.banco.haMudanca -eq $true) {
        $scripts = Scripts-DeBanco $decisao $ctx $dirOut
        if ($scripts.Count -eq 0) {
            Avisar 'há mudança de banco, mas nenhum script foi encontrado: a nota interna com o SQL não vai. Informe o caminho em banco.scripts do decisao.json ou passe o SQL ao agente.'
        } else {
            $corpoBanco = Montar-NotaBanco $scripts $decisao
            $corpoBancoFinal = Texto-ParaPublicar $dirOut 'nota-banco' $corpoBanco ([bool]$Executar)
            $anteriorBanco = @($notas | Where-Object { -not $_.system -and $_.author.id -eq $eu.id -and ([string]$_.body).Contains($cfg.textos.marcadorBanco) } | Select-Object -Last 1)
            if ($anteriorBanco.Count -gt 0) {
                [void]$acoes.Add([pscustomobject]@{ Tipo = 'comentario-atualizar'; Descricao = "Atualizar a nota interna com o SQL do banco (nota $($anteriorBanco[0].id))"; NotaId = $anteriorBanco[0].id; Corpo = $corpoBancoFinal })
            } else {
                [void]$acoes.Add([pscustomobject]@{ Tipo = 'nota-interna'; Descricao = "Comentar o SQL do banco como nota interna ($($scripts.Count) script(s))"; Corpo = $corpoBancoFinal })
            }
        }
    }

    # 3. card filho da atividade
    $ativ = $Atividade
    if (-not $SemFilho -and -not $ativ) {
        $ativ = Atividade-DaColuna $colunaAtual
        if (-not $ativ) { Avisar "a coluna '$colunaAtual' não tem atividade de card filho: card filho ignorado. Se precisar, informe -Atividade '<nome>'." }
    }
    if (-not $SemFilho -and $ativ) {
        foreach ($a in (Acoes-Filho $issue $links $eu $etiquetas $ativ ([bool]$NovoFilho) '')) { [void]$acoes.Add($a) }
    }

    # 4. mudar de coluna: -Coluna escolhe qualquer coluna do quadro do card; -Mover e o
    #    atalho para "Processo Merge / Publicacao", so a partir das colunas de trabalho.
    if ($Coluna) {
        $acaoColuna = Acao-MoverColuna $projetoId $issue $Coluna
        if ($acaoColuna) { [void]$acoes.Add($acaoColuna) }
    } elseif ($Mover) {
        $destino = Achar-Etiqueta $etiquetas $cfg.quadro.colunaDestinoMover
        if (-not $destino) { throw "Etiqueta da coluna '$($cfg.quadro.colunaDestinoMover)' não encontrada no projeto." }
        $origens = @($cfg.quadro.moverSomenteDe | ForEach-Object { Normalizar-Texto $_ })
        if (-not (Tem-Etiqueta $issue $destino) -and $origens -notcontains (Normalizar-Texto $colunaAtual)) {
            throw "O card está na coluna '$colunaAtual'; -Mover só leva para '$destino' a partir de: $($cfg.quadro.moverSomenteDe -join ', '). Mova pelo quadro se for o caso."
        }
        if (-not (Tem-Etiqueta $issue $destino)) {
            $remover = @($issue.labels | Where-Object { (Eh-Coluna $_) -and ((Normalizar-Texto $_) -ne (Normalizar-Texto $destino)) })
            [void]$acoes.Add([pscustomobject]@{ Tipo = 'etiquetas-pai'; Descricao = "Mover o card de '$($remover -join ', ')' para '$destino'"; Adicionar = @($destino); Remover = $remover })
        }
    }

    Escrever-Titulo "Ações ($($acoes.Count))"
    $i = 0
    foreach ($a in $acoes) { $i++; Write-Host "$i. $($a.Descricao)" }
    Gravar-Texto (Join-Path $dirOut 'comentario-plano.md') $corpo
    $arqNota = Join-Path $dirOut 'nota-banco.md'
    if ($corpoBanco) { Gravar-Texto $arqNota $corpoBanco } elseif (Test-Path -LiteralPath $arqNota) { Remove-Item -LiteralPath $arqNota }
    Write-Host ''
    Write-Host "Texto do comentário: $rel/comentario-plano.md"
    if ($corpoBanco) { Write-Host "Nota interna com o SQL: $rel/nota-banco.md" }
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
        try {
            if ($a.Corpo -and ([string]$a.Corpo).Contains('](evidencia:')) { $a.Corpo = Resolver-Evidencias $a.Corpo $dirOut }
            Executar-Acao $a $projetoId $iid
        }
        catch { throw "Parou na ação $i ($($a.Descricao)): $($_.Exception.Message). As ações anteriores já foram gravadas." }
    }
    $hist = Gravar-Historico $ref $issue $ctx $decisao $plano
    Write-Host ''
    Write-Host "Pronto. Histórico: $hist"
}

function Executar-Acao($Acao, [int]$ProjetoId, [int]$Iid) {
    switch ($Acao.Tipo) {
        'comentario-novo' {
            [void](Invoke-Gitlab -Metodo POST -Caminho "/projects/$ProjetoId/issues/$Iid/notes" -Corpo @{ body = $Acao.Corpo })
        }
        'comentario-atualizar' {
            [void](Invoke-Gitlab -Metodo PUT -Caminho "/projects/$ProjetoId/issues/$Iid/notes/$($Acao.NotaId)" -Corpo @{ body = $Acao.Corpo })
        }
        'nota-interna' {
            [void](Invoke-Gitlab -Metodo POST -Caminho "/projects/$ProjetoId/issues/$Iid/notes" -Corpo @{ body = $Acao.Corpo; internal = $true })
        }
        'evidencias-enviar' {
            $cache = Ler-CacheEvidencias $Acao.DirOut
            foreach ($f in $Acao.Arquivos) {
                $h = Hash-Arquivo $f.FullName
                if ($cache.ContainsKey($h)) { continue }
                Write-Host "   $($f.Directory.Name)/$($f.Name) ($(Tamanho-Legivel $f.Length))"
                $r = Enviar-ArquivoGitlab $ProjetoId $f.FullName
                if (-not $r.markdown) { throw "o GitLab não devolveu o link de $($f.Name)." }
                $cache[$h] = [string]$r.markdown
                Gravar-CacheEvidencias $Acao.DirOut $cache
            }
        }
        'etiquetas-pai' {
            $corpo = @{ add_labels = (@($Acao.Adicionar) -join ',') }
            if (@($Acao.Remover).Count -gt 0) { $corpo.remove_labels = (@($Acao.Remover) -join ',') }
            [void](Invoke-Gitlab -Metodo PUT -Caminho "/projects/$ProjetoId/issues/$Iid" -Corpo $corpo)
        }
        'filho-criar' {
            $corpo = @{ title = $Acao.Titulo; description = $Acao.DescricaoFilho; labels = (@($Acao.Etiquetas) -join ','); assignee_ids = @($Acao.ResponsavelId) }
            if ($Acao.MilestoneId) { $corpo.milestone_id = $Acao.MilestoneId }
            $novo = Invoke-Gitlab -Metodo POST -Caminho "/projects/$ProjetoId/issues" -Corpo $corpo
            Write-Host "   criado #$($novo.iid)"
            [void](Invoke-Gitlab -Metodo POST -Caminho "/projects/$ProjetoId/issues/$($novo.iid)/links" -Corpo @{ target_project_id = $ProjetoId; target_issue_iid = $Iid; link_type = 'relates_to' })
            [void](Invoke-Gitlab -Metodo PUT -Caminho "/projects/$ProjetoId/issues/$($novo.iid)" -Corpo @{ state_event = 'close' })
        }
        'filho-concluir' {
            [void](Invoke-Gitlab -Metodo PUT -Caminho "/projects/$ProjetoId/issues/$($Acao.FilhoIid)" -Corpo @{ add_labels = $Acao.Feito; state_event = 'close' })
        }
        default { throw "Ação desconhecida: $($Acao.Tipo)" }
    }
}

function Gravar-Historico($Ref, $Issue, $Ctx, $Decisao, [string]$Plano) {
    $nome = Nome-PastaCard $Ref
    $caminho = Join-Path $script:Raiz "historico\$nome.md"
    $md = @(
        "# #$($Ref.Iid) - $($Issue.title)"
        ''
        "areas: $(@($Ctx.areas) -join ', ')"
        "data: $((Get-Date).ToString('yyyy-MM-dd'))"
        "branch: $($Ctx.branch.nome) | base: $($Ctx.base.nome) | commit: $($Ctx.branch.sha.Substring(0, 10))"
        "banco: $(if ($Decisao.banco.haMudanca -eq $true) { 'sim' } else { 'não' }) $(@($Decisao.banco.scripts) -join ', ')"
        ''
        '## Avaliação por critério'
        ''
        '| CA | situação | teste | critério |'
        '|---|---|---|---|'
    )
    foreach ($c in @($Decisao.criterios)) { $md += "| $($c.id) | $($c.situacao) | $(Celula $c.teste 60) | $(Celula $c.texto) |" }
    $md += ''
    $md += '## Plano publicado'
    $md += ''
    $md += $Plano
    Gravar-Texto $caminho (($md -join "`n") + "`n")
    return (Caminho-Relativo $caminho)
}
