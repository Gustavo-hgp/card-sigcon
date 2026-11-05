<#
card-sigcon - servidor da pagina local (http://localhost:8765/).
So escuta em localhost; toda chamada que grava exige o token gerado nesta execucao
(vai embutido na pagina), entao outro site aberto no navegador nao consegue disparar
nada. Tarefas longas (turno do Kiro, simular, publicar) rodam em outro processo
(ui/executar.ps1) e a pagina acompanha pelo /api/estado.
Uso: card-ui.cmd [-Porta 8765] [-NaoAbrir] [-ArquivoEstado <json>]. Salvo em UTF-8 com BOM (ver lib/Comum.ps1).
#>
param([int]$Porta = 8765, [switch]$NaoAbrir, [string]$ArquivoEstado)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }
$script:Raiz = Split-Path -Parent $PSScriptRoot
$script:Ui = $PSScriptRoot
foreach ($lib in @('Comum', 'Git', 'Gitlab', 'Card', 'Wiki', 'Creditos', 'Publicar', 'Avaliacao', 'Aprendizado', 'Limpeza', 'Instalacao')) { . (Join-Path $script:Raiz "lib\$lib.ps1") }
Carregar-Env $script:Raiz
$script:Cfg = Ler-Config $script:Raiz
# o que muda de maquina para maquina: agente com o caminho do repositorio e o que falta instalar
Write-Host "Repositório do SIGCON: $($script:Cfg.repoPadrao)"
try {
    $g = Gerar-Agente
    if ($g.Gerou) { Write-Host 'Agente do Kiro configurado para esse repositório.' }
    if ($g.Aviso) { Write-Host "AVISO: $($g.Aviso)" }
} catch { Write-Host "AVISO: não consegui configurar o agente do Kiro ($($_.Exception.Message))." }
$verificacao = Verificar-Instalacao
$script:AvisosInstalacao = @($verificacao | Where-Object { -not $_.Ok })
foreach ($a in $script:AvisosInstalacao) { Write-Host "AVISO: $($a.Nome) ($($a.Detalhe)): $($a.Como)" }
$script:Token = [guid]::NewGuid().ToString('N')
$script:ArqEstado = Join-Path $script:Raiz 'out\ui-estado.json'
if ($ArquivoEstado) { $script:ArqEstado = $ArquivoEstado }
$script:ArqRevisao = [System.IO.Path]::ChangeExtension($script:ArqEstado, '.revisao.json')
# um registro por turno do Kiro; fica fora das pastas dos cards, entao a limpeza nao apaga
$script:ArqCreditos = [System.IO.Path]::ChangeExtension($script:ArqEstado, '.creditos.jsonl')
$script:ArquivosDoCard = @('contexto.md', 'contexto.json', 'avaliacao.md', 'banco.md', 'banco.sql', 'plano.md', 'decisao.json', 'comentario-plano.md', 'nota-banco.md', 'retro.md', 'execucao-testes.json', 'execucao.md',
    'avaliacao-tecnica.md', 'decisao-avaliacao.json', 'nota-avaliacao.md')
# 'evidencias' e a pasta das fotos e videos dos testes (vai junto para anteriores/)
$script:ArquivosAnteriores = @('contexto.md', 'contexto.json', 'diff.txt', 'avaliacao.md', 'banco.md', 'banco.sql', 'plano.md', 'decisao.json', 'comentario-plano.md', 'nota-banco.md', 'execucao-testes.json', 'execucao.md', 'evidencias',
    'avaliacao-tecnica.md', 'decisao-avaliacao.json', 'nota-avaliacao.md',
    'comentario-plano.editado.md', 'comentario-plano.editado.base', 'nota-banco.editado.md', 'nota-banco.editado.base', 'nota-avaliacao.editado.md', 'nota-avaliacao.editado.base')
# textos que vao para o card e que o dev pode editar na pre-visualizacao (nome -> marcador)
$script:TextosEditaveis = @{ 'comentario-plano' = 'marcadorPlano'; 'nota-banco' = 'marcadorBanco'; 'nota-avaliacao' = 'marcadorAvaliacao' }
# o que, mudando depois do Simular, obriga a simular de novo (por modo)
$script:InvalidamSimular = @{
    card = @('plano.md', 'decisao.json', 'execucao.md', 'banco.sql', 'evidencias')
    avaliacao = @('avaliacao-tecnica.md', 'decisao-avaliacao.json')
}
$script:Estaticos = @{
    '/app.js' = 'application/javascript; charset=utf-8'
    '/app.css' = 'text/css; charset=utf-8'
}

# ---------------- estado ----------------

function Novo-Estado {
    return [pscustomobject]@{
        modo = 'card'; card = ''; titulo = ''; branch = ''; base = ''; iid = 0; pasta = ''; sessaoId = ''; inicio = ''
        conversa = @(); tarefa = $null; ultimaSimulacao = $null
    }
}

function Salvar-Estado { Gravar-Json $script:ArqEstado $script:Estado }

function Carregar-Estado {
    $e = Novo-Estado
    if (Test-Path -LiteralPath $script:ArqEstado) {
        try {
            $lido = Ler-Json $script:ArqEstado
            foreach ($p in $e.PSObject.Properties.Name) { if ($lido.PSObject.Properties[$p]) { $e.$p = $lido.$p } }
            $e.conversa = @($e.conversa | Where-Object { $_ })
        } catch { Write-Host "AVISO: estado anterior ilegível, começando do zero. $($_.Exception.Message)" }
    }
    return $e
}

function Dir-Card { return Join-Path $script:Raiz ('out\' + $script:Estado.pasta) }

# ---------------- texto editado pelo dev antes de publicar ----------------
# <nome>.md e o que o Simular gerou; <nome>.editado.md e a versao do dev (com o marcador);
# <nome>.editado.base guarda o hash do gerado na hora da edicao. Se o gerado mudar depois,
# a edicao fica "desatualizada" e o Publicar recusa ate o dev revisar.

function Info-Texto([string]$Nome) {
    if (-not $script:TextosEditaveis.ContainsKey($Nome)) { throw "Texto desconhecido: $Nome" }
    $dir = Dir-Card
    $g = Join-Path $dir "$Nome.md"; $e = Join-Path $dir "$Nome.editado.md"; $b = Join-Path $dir "$Nome.editado.base"
    $gerado = ''; if ($script:Estado.pasta -and (Test-Path -LiteralPath $g)) { $gerado = Ler-Texto $g }
    $editado = ''; if ($script:Estado.pasta -and (Test-Path -LiteralPath $e)) { $editado = Ler-Texto $e }
    $desatualizado = $false
    if ($editado) {
        $base = ''; if (Test-Path -LiteralPath $b) { $base = (Ler-Texto $b).Trim() }
        $desatualizado = ($base -ne (Hash-Texto $gerado))
    }
    return [ordered]@{ nome = $Nome; gerado = $gerado; editado = $editado; desatualizado = $desatualizado }
}

function Salvar-TextoEditado([string]$Nome, [string]$Texto) {
    $info = Info-Texto $Nome
    if (-not $info.gerado) { throw 'Rode o Simular antes de editar: é ele que gera o texto.' }
    # o marcador (comentario HTML invisivel) identifica a nota no card; o dev nao edita isso
    $limpo = [regex]::Replace(($Texto -replace "`r`n", "`n"), '<!--\s*card-sigcon:\w+\s*-->\s*', '').Trim()
    if (-not $limpo) { throw 'O texto ficou vazio. Para voltar ao texto gerado, use "Voltar ao texto gerado".' }
    $marcador = [string]$script:Cfg.textos.($script:TextosEditaveis[$Nome])
    Gravar-Texto (Join-Path (Dir-Card) "$Nome.editado.md") ($marcador + "`n" + $limpo)
    Gravar-Texto (Join-Path (Dir-Card) "$Nome.editado.base") (Hash-Texto $info.gerado)
}

function Descartar-TextoEditado([string]$Nome) {
    if (-not $script:TextosEditaveis.ContainsKey($Nome)) { throw "Texto desconhecido: $Nome" }
    foreach ($s in @('.editado.md', '.editado.base')) {
        $p = Join-Path (Dir-Card) ($Nome + $s)
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p }
    }
}

# para a aba Publicar: quais textos tem edicao e se ela ficou velha
function Estado-Edicoes {
    $r = [ordered]@{}
    if (-not $script:Estado.pasta) { return $r }
    foreach ($n in $script:TextosEditaveis.Keys) {
        if (Test-Path -LiteralPath (Join-Path (Dir-Card) "$n.editado.md")) {
            $i = Info-Texto $n
            $r[$n] = [ordered]@{ editado = $true; desatualizado = $i.desatualizado }
        }
    }
    return $r
}

function Info-Arquivos {
    $r = [ordered]@{}
    if (-not $script:Estado.pasta) { return $r }
    foreach ($n in $script:ArquivosDoCard) {
        $p = Join-Path (Dir-Card) $n
        if (Test-Path -LiteralPath $p) { $r[$n] = (Get-Item -LiteralPath $p).LastWriteTime.ToString('s') }
    }
    $h = Join-Path $script:Raiz ('historico\' + $script:Estado.pasta + '.md')
    if (Test-Path -LiteralPath $h) { $r['historico'] = (Get-Item -LiteralPath $h).LastWriteTime.ToString('s') }
    # evidencias: a ultima mudanca (arquivo novo ou removido muda a data da pasta)
    $ev = Join-Path (Dir-Card) 'evidencias'
    if (Test-Path -LiteralPath $ev) {
        $ultima = @(@(Get-Item -LiteralPath $ev) + @(Get-ChildItem -LiteralPath $ev -Recurse -Force) | Sort-Object LastWriteTime -Descending)[0]
        $r['evidencias'] = $ultima.LastWriteTime.ToString('s')
    }
    return $r
}

# Numeros da linha de status de cada etapa (barra lateral). Rele os arquivos so quando
# algum muda.
$script:CacheResumo = $null
function Resumo-Etapas {
    $r = [ordered]@{ commits = 0; criterios = 0; aTestar = 0; pendentes = 0; banco = ''; cenarios = 0; testesFeitos = 0; evidencias = 0
        referencia = ''; paginasWiki = 0; pontos = 0; pontosAprovados = $false }
    if (-not $script:Estado.pasta) { return $r }
    $info = Info-Arquivos
    $chave = $script:Estado.pasta + '|' + (@($info.Keys | ForEach-Object { "$_=$($info[$_])" }) -join ';')
    if ($script:CacheResumo -and $script:CacheResumo.Chave -eq $chave) { return $script:CacheResumo.Valor }
    $dir = Dir-Card
    try {
        $ctx = Ler-Json (Join-Path $dir 'contexto.json')
        $r.commits = [int]$ctx.commits
        $r.criterios = @($ctx.criteriosExtraidos | Where-Object { $_ }).Count
        $r.paginasWiki = @($ctx.wiki | Where-Object { $_ }).Count
        if ($ctx.referencia) { $r.referencia = [string]$ctx.referencia.nome }
    } catch { }
    try {
        $da = Ler-Json (Join-Path $dir 'decisao-avaliacao.json')
        $r.pontos = [int]$da.pontos; $r.pontosAprovados = ($da.confirmadoPeloDev -eq $true)
    } catch { }
    try {
        $d = Ler-Json (Join-Path $dir 'decisao.json')
        $crit = @($d.criterios | Where-Object { $_ })
        if ($crit.Count) { $r.criterios = $crit.Count }
        $r.aTestar = @($crit | Where-Object { $_.situacao -eq 'verificar_no_teste' }).Count
        $r.pendentes = @($crit | Where-Object { @('parcial', 'nao_atendido', 'nao_encontrado') -contains $_.situacao }).Count
        if ($d.banco) { if ($d.banco.haMudanca -eq $true) { $r.banco = 'com mudança de banco' } else { $r.banco = 'sem mudança de banco' } }
    } catch { }
    $p = Join-Path $dir 'plano.md'
    if (Test-Path -LiteralPath $p) { $r.cenarios = @((Ler-Texto $p) -split "\r?\n" | Where-Object { $_ -match '^#{2,4}\s+\**Cen.rio\s*\d' }).Count }
    try {
        $t = Ler-Json (Join-Path $dir 'execucao-testes.json')
        $r.testesFeitos = @($t.cenarios.PSObject.Properties | Where-Object { $_.Value.feito -eq $true }).Count
    } catch { }
    $ev = Evidencias-DoCard $dir
    foreach ($k in $ev.Keys) { $r.evidencias += @($ev[$k]).Count }
    $script:CacheResumo = [pscustomobject]@{ Chave = $chave; Valor = $r }
    return $r
}

# ---------------- evidencias dos testes ----------------
# out/<card>/evidencias/cenario-<N>/<arquivo>: fotos e videos que o dev anexa na aba Plano.
# O Publicar envia ao GitLab e poe no comentario, no fim de cada cenario.

function Dir-Evidencias([string]$Chave) {
    if ($Chave -notmatch '^cenario-\d{1,3}$') { throw "Cenário inválido: $Chave" }
    return Join-Path (Dir-Card) ('evidencias\' + $Chave)
}

function Arquivo-Evidencia([string]$Chave, [string]$Nome) {
    if ($Nome -notmatch '^[A-Za-z0-9._-]{1,100}$' -or $Nome -match '^\.') { throw "Nome de evidência inválido: $Nome" }
    $p = Join-Path (Dir-Evidencias $Chave) $Nome
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw "Evidência não encontrada: $Chave/$Nome" }
    return $p
}

$script:TiposEvidencia = @{ '.png' = 'image/png'; '.jpg' = 'image/jpeg'; '.jpeg' = 'image/jpeg'; '.gif' = 'image/gif'; '.webp' = 'image/webp'; '.mp4' = 'video/mp4'; '.webm' = 'video/webm'; '.mov' = 'video/quicktime' }

function Listar-Evidencias {
    $cenarios = [ordered]@{}
    if ($script:Estado.pasta) {
        $ev = Evidencias-DoCard (Dir-Card)
        foreach ($k in $ev.Keys) {
            $cenarios[$k] = @($ev[$k] | ForEach-Object {
                    [ordered]@{ nome = $_.Name; tamanho = $_.Length; video = ([string]$script:TiposEvidencia[$_.Extension.ToLowerInvariant()]).StartsWith('video/'); quando = $_.LastWriteTime.ToString('s') }
                })
        }
    }
    return [ordered]@{ limiteMb = [double]$script:Cfg.evidencias.tamanhoMaximoMb; extensoes = @($script:Cfg.evidencias.extensoes); cenarios = $cenarios }
}

# Grava o corpo da requisicao (o arquivo cru) como evidencia do cenario. O nome vira ASCII
# sem espacos (vai para o markdown do GitLab) e nao sobrescreve arquivo com o mesmo nome.
function Gravar-Evidencia($Req) {
    if (-not $script:Estado.pasta) { throw 'Comece um card primeiro.' }
    $chave = (Parametro $Req 'chave')
    $dir = Dir-Evidencias $chave
    $original = [System.IO.Path]::GetFileName((Parametro $Req 'nome'))
    $ext = [System.IO.Path]::GetExtension($original).ToLowerInvariant()
    if (@($script:Cfg.evidencias.extensoes) -notcontains $ext) { throw "Tipo de arquivo não aceito ($ext). Aceitos: $(@($script:Cfg.evidencias.extensoes) -join ', ')." }
    $limiteMb = [double]$script:Cfg.evidencias.tamanhoMaximoMb
    if ($limiteMb -gt 0 -and $Req.ContentLength64 -gt $limiteMb * 1MB) { throw "Arquivo com $([math]::Round($Req.ContentLength64 / 1MB, 1)) MB: o limite é $limiteMb MB." }
    $base = (Normalizar-Texto ([System.IO.Path]::GetFileNameWithoutExtension($original))) -replace '[^a-z0-9._-]+', '-' -replace '-{2,}', '-' -replace '^[-.]+|[-.]+$', ''
    if (-not $base) { $base = 'evidencia' }
    if ($base.Length -gt 60) { $base = $base.Substring(0, 60) }
    if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Force -Path $dir) }
    $nome = $base + $ext; $n = 1
    while (Test-Path -LiteralPath (Join-Path $dir $nome)) { $n++; $nome = "$base-$n$ext" }
    $destino = Join-Path $dir $nome
    $f = [System.IO.File]::Create($destino)
    try { $Req.InputStream.CopyTo($f) } finally { $f.Close() }
    if ((Get-Item -LiteralPath $destino).Length -eq 0) { Remove-Item -LiteralPath $destino; throw 'Arquivo vazio.' }
    return $nome
}

# Ao comecar o card de novo, guarda o contexto e o que o agente gerou antes (evita
# mostrar etapa velha como feita ou publicar decisao velha).
function Arquivar-Anteriores([string]$Pasta) {
    $dir = Join-Path $script:Raiz ('out\' + $Pasta)
    if (-not (Test-Path -LiteralPath $dir)) { return }
    $destino = Join-Path $dir ('anteriores\' + (Get-Date).ToString('yyyyMMdd-HHmmss'))
    foreach ($n in $script:ArquivosAnteriores) {
        $p = Join-Path $dir $n
        if (Test-Path -LiteralPath $p) {
            if (-not (Test-Path -LiteralPath $destino)) { [void](New-Item -ItemType Directory -Force -Path $destino) }
            Move-Item -LiteralPath $p -Destination $destino
        }
    }
}

# ---------------- tarefas ----------------

# Sobe o ui/executar.ps1 com os dados em <dir>/<id>-<tipo>.entrada.json; devolve a
# tarefa (log, arquivo de fim, pid) ainda rodando.
function Iniciar-Executor([string]$Dir, [string]$Tipo, [hashtable]$Dados) {
    $id = (Get-Date).ToString('yyyyMMdd-HHmmss')
    if (-not (Test-Path -LiteralPath $Dir)) { [void](New-Item -ItemType Directory -Force -Path $Dir) }
    $log = Join-Path $Dir "$id-$Tipo.log"
    $fim = Join-Path $Dir "$id-$Tipo.fim.json"
    $entrada = Join-Path $Dir "$id-$Tipo.entrada.json"
    $Dados.raiz = $script:Raiz; $Dados.log = $log; $Dados.fim = $fim
    if (-not $Dados.ContainsKey('tipo')) { $Dados.tipo = $Tipo }
    Gravar-Json $entrada $Dados
    Gravar-Texto $log ''
    $argumentos = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + (Join-Path $script:Ui 'executar.ps1') + '"'), '-Entrada', ('"' + $entrada + '"'))
    $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $argumentos -WindowStyle Hidden -PassThru
    return [pscustomobject]@{
        id = $id; tipo = $Tipo; rodando = $true; inicio = (Get-Date).ToString('s'); fim = ''; codigo = $null
        log = $log; arqFim = $fim; pid = $p.Id; opcoes = $Dados.opcoes
    }
}

function Iniciar-Tarefa([string]$Tipo, [hashtable]$Dados) {
    if ($script:Estado.tarefa -and $script:Estado.tarefa.rodando) { throw 'Já existe uma tarefa rodando: espere terminar ou cancele.' }
    $script:Estado.tarefa = Iniciar-Executor (Join-Path (Dir-Card) 'ui') $Tipo $Dados
    Salvar-Estado
}

# Fecha a tarefa se o executor terminou (arquivo de fim) ou morreu sem gravar o fim.
# Devolve o conteudo do arquivo de fim quando acabou de fechar.
function Fechar-SeTerminou($T) {
    if (-not $T -or -not $T.rodando) { return $null }
    if (Test-Path -LiteralPath $T.arqFim) {
        $f = Ler-Json $T.arqFim
        $T.rodando = $false; $T.codigo = $f.codigo; $T.fim = $f.fim
        return $f
    }
    if (-not (Get-Process -Id $T.pid -ErrorAction SilentlyContinue)) {
        $T.rodando = $false; $T.codigo = -1; $T.fim = (Get-Date).ToString('s')
        return [pscustomobject]@{ codigo = -1; fim = $T.fim; sessaoId = '' }
    }
    return $null
}

# ---------------- revisao do aprendizado ----------------
# Turno avulso do Kiro, numa sessao propria apagada no fim: nao mexe no card aberto,
# na conversa dele nem na tarefa do card. O resultado sao propostas em _propostas.md.

function Carregar-Revisao {
    if (-not (Test-Path -LiteralPath $script:ArqRevisao)) { return $null }
    try { return (Ler-Json $script:ArqRevisao) } catch { return $null }
}

function Iniciar-Revisao {
    if ($script:Revisao -and $script:Revisao.rodando) { throw 'A revisão do aprendizado já está rodando.' }
    $marcador = 'card-sigcon revisao-aprendizado ' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $mensagem = "$marcador (pagina do card-sigcon) | Revisão do aprendizado: siga a seção 'Revisão do aprendizado' do steering. Grave as propostas em aprendizado/_propostas.md e termine com o resumo do que propôs."
    $script:Revisao = Iniciar-Executor (Join-Path $script:Raiz 'out\_aprendizado\ui') 'revisao' @{ tipo = 'kiro'; mensagem = $mensagem; sessaoId = ''; marcador = $marcador; apagarSessao = $true }
    Gravar-Json $script:ArqRevisao $script:Revisao
}

# ---------------- creditos do Kiro ----------------
# out/ui-estado.creditos.jsonl: uma linha por turno do Kiro (card ou revisao), com os
# creditos lidos da sessao pelo executar.ps1. A pagina mostra o total do card e do mes.

function Registrar-Creditos([string]$Tipo, [string]$Pasta, [int]$Iid, $Creditos, [string]$Quando, [string]$Origem = 'pagina') {
    if ($null -eq $Creditos) { return }
    if (-not $Quando) { $Quando = (Get-Date).ToString('s') }
    $linha = ConvertTo-Json -Compress -InputObject ([ordered]@{ quando = $Quando; tipo = $Tipo; pasta = $Pasta; iid = $Iid; creditos = [math]::Round([double]$Creditos, 4); origem = $Origem })
    [System.IO.File]::AppendAllText($script:ArqCreditos, $linha + "`n", $script:Utf8SemBom)
}

$script:CacheCreditos = $null
function Linhas-Creditos {
    if (-not (Test-Path -LiteralPath $script:ArqCreditos)) { return ,@() }
    $info = Get-Item -LiteralPath $script:ArqCreditos
    $chave = "$($info.LastWriteTimeUtc.Ticks)|$($info.Length)"
    if (-not $script:CacheCreditos -or $script:CacheCreditos.Chave -ne $chave) {
        $lista = @()
        foreach ($l in ((Ler-Texto $script:ArqCreditos) -split "\r?\n")) {
            if (-not $l.Trim()) { continue }
            try { $lista += ($l | ConvertFrom-Json) } catch { }
        }
        $script:CacheCreditos = [pscustomobject]@{ Chave = $chave; Linhas = $lista }
    }
    return ,$script:CacheCreditos.Linhas
}

function Resumo-Creditos {
    $linhas = Linhas-Creditos
    $mes = (Get-Date).ToString('yyyy-MM')
    $r = [ordered]@{ card = 0.0; cardTurnos = 0; mes = 0.0; mesTurnos = 0; inicioMes = $mes + '-01' }
    foreach ($x in $linhas) {
        $c = [double]$x.creditos
        if ($script:Estado.pasta -and [string]$x.pasta -eq $script:Estado.pasta) { $r.card += $c; $r.cardTurnos++ }
        if (([string]$x.quando).StartsWith($mes)) { $r.mes += $c; $r.mesTurnos++ }
    }
    $r.card = [math]::Round($r.card, 2); $r.mes = [math]::Round($r.mes, 2)
    return $r
}

# Na primeira vez, traz o consumo das conversas do card-sigcon que ainda existem no Kiro
# (titulo "card-sigcon #<n> ..."), turno a turno.
function Importar-CreditosAntigos {
    if (Test-Path -LiteralPath $script:ArqCreditos) { return }
    Gravar-Texto $script:ArqCreditos ''
    $dir = Join-Path $env:USERPROFILE '.kiro\sessions\cli'
    if (-not (Test-Path -LiteralPath $dir)) { return }
    $pastas = @(Get-ChildItem -LiteralPath (Join-Path $script:Raiz 'out') -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
    $n = 0
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter '*.json' -File | Sort-Object LastWriteTime)) {
        $titulo = ''
        try { $titulo = [string]([System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8) | ConvertFrom-Json).title } catch { continue }
        $m = [regex]::Match($titulo, '^card-sigcon #(\d+) ')
        if (-not $m.Success) { continue }
        $iid = [int]$m.Groups[1].Value
        $daPasta = @($pastas | Where-Object { $_ -match ('-' + $iid + '$') })
        $pasta = '#' + $iid; if ($daPasta.Count -eq 1) { $pasta = $daPasta[0] }
        $turnos = Turnos-DaSessao $f.BaseName
        if ($null -eq $turnos) { continue }
        foreach ($t in $turnos) {
            $quando = ''; if ($t.Quando) { $quando = $t.Quando.ToString('s') }
            Registrar-Creditos 'card' $pasta $iid $t.Creditos $quando 'importado'
            $n++
        }
    }
    if ($n) { Write-Host "Consumo do Kiro: importei $n turno(s) das conversas que ainda existiam." }
}

function Estado-Revisao([switch]$ComTexto) {
    $r = $script:Revisao
    $f = Fechar-SeTerminou $r
    if ($null -ne $f) {
        $r | Add-Member -NotePropertyName creditos -NotePropertyValue $f.creditos -Force
        Registrar-Creditos 'revisao' '_aprendizado' 0 $f.creditos $r.fim
        Gravar-Json $script:ArqRevisao $r
    }
    if (-not $r) { return $null }
    $saida = [ordered]@{ rodando = $r.rodando; inicio = $r.inicio; fim = $r.fim; codigo = $r.codigo; creditos = $r.creditos }
    if ($ComTexto) {
        $saida.texto = ''
        if (Test-Path -LiteralPath $r.log) { $saida.texto = Ler-Texto $r.log }
    }
    return $saida
}

function Cancelar-Revisao {
    $r = $script:Revisao
    if (-not $r -or -not $r.rodando) { return }
    & taskkill.exe /PID $r.pid /T /F 2>&1 | Out-Null
    [System.IO.File]::AppendAllText($r.log, "`nCANCELADO pelo dev.`n", $script:Utf8SemBom)
    $r.rodando = $false; $r.codigo = -2; $r.fim = (Get-Date).ToString('s')
    Gravar-Json $script:ArqRevisao $r
}

function Atualizar-Tarefa {
    $t = $script:Estado.tarefa
    if (-not $t -or -not $t.rodando) { return }
    if (Test-Path -LiteralPath $t.arqFim) {
        $f = Ler-Json $t.arqFim
        $t.rodando = $false; $t.codigo = $f.codigo; $t.fim = $f.fim
        if ($t.tipo -eq 'kiro') {
            if ($f.sessaoId) { $script:Estado.sessaoId = $f.sessaoId }
            $script:Estado.conversa = @($script:Estado.conversa) + @([pscustomobject]@{ quem = 'agente'; texto = (Ler-Texto $t.log); quando = $t.fim; codigo = $f.codigo; creditos = $f.creditos })
            Registrar-Creditos 'card' $script:Estado.pasta $script:Estado.iid $f.creditos $t.fim
        }
        if ($t.tipo -eq 'simular') { $script:Estado.ultimaSimulacao = [pscustomobject]@{ codigo = $f.codigo; quando = $t.fim; opcoes = $t.opcoes } }
        Salvar-Estado
    } elseif (-not (Get-Process -Id $t.pid -ErrorAction SilentlyContinue)) {
        $t.rodando = $false; $t.codigo = -1; $t.fim = (Get-Date).ToString('s')
        Salvar-Estado
    }
}

function Cancelar-Tarefa {
    $t = $script:Estado.tarefa
    if (-not $t -or -not $t.rodando) { return }
    & taskkill.exe /PID $t.pid /T /F 2>&1 | Out-Null
    [System.IO.File]::AppendAllText($t.log, "`nCANCELADO pelo dev.`n", $script:Utf8SemBom)
    $t.rodando = $false; $t.codigo = -2; $t.fim = (Get-Date).ToString('s')
    Salvar-Estado
}

function Texto-Log {
    $t = $script:Estado.tarefa
    if (-not $t -or -not (Test-Path -LiteralPath $t.log)) { return '' }
    $txt = Ler-Texto $t.log
    if ($txt.Length -gt 30000) { $txt = '...' + $txt.Substring($txt.Length - 30000) }
    return $txt
}

function Chave-Opcoes($B) {
    return '{0}|{1}|{2}|{3}|{4}' -f [string]$B.coluna, [string]$B.atividade, [bool]$B.semFilho, [bool]$B.novoFilho, [string]$B.pontos
}

# 'simular'/'publicar' viram 'simular-avaliacao'/'publicar-avaliacao' no modo avaliacao.
function Argumentos-Card([string]$Comando, $B) {
    $avaliacao = $script:Estado.modo -eq 'avaliacao'
    if ($avaliacao) { $Comando += '-avaliacao' }
    $a = @($Comando, '-Card', $script:Estado.card)
    if ([string]$B.coluna) { $a += @('-Coluna', [string]$B.coluna) }
    if (-not $avaliacao -and [string]$B.atividade) { $a += @('-Atividade', [string]$B.atividade) }
    if ($avaliacao -and [string]$B.pontos -match '^\d+$') { $a += @('-Pontos', [string]$B.pontos) }
    if ([bool]$B.semFilho) { $a += '-SemFilho' }
    if ([bool]$B.novoFilho) { $a += '-NovoFilho' }
    return $a
}

function Rodar-CardAgora([string[]]$Argumentos) {
    $saida = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $script:Raiz 'card.ps1') @Argumentos 2>&1 |
        ForEach-Object { "$_" } | Where-Object { $_ -notmatch 'System\.Management\.Automation\.RemoteException' }
    return [ordered]@{ codigo = $LASTEXITCODE; saida = (@($saida) -join "`n") }
}

# ---------------- escolha do card (formulario) ----------------

# Branches locais e do origin, mais recentes primeiro (uma por nome). Fica em memoria
# por 60 s: o for-each-ref de ~2 mil refs custa ~1 s e a busca roda a cada tecla.
$script:CacheBranches = $null
function Todas-Branches {
    if ($script:CacheBranches -and ((Get-Date) - $script:CacheBranches.Quando).TotalSeconds -lt 60) { return $script:CacheBranches.Lista }
    $r = Invoke-Git $script:Cfg.repoPadrao @('for-each-ref', '--sort=-committerdate', '--format=%(refname)%09%(committerdate:short)%09%(authorname)%09%(subject)', 'refs/heads', 'refs/remotes/origin')
    $vistos = @{}
    $lista = New-Object System.Collections.ArrayList
    foreach ($l in ((Decodificar $r.Saida ([System.Text.Encoding]::UTF8)) -split "`n")) {
        $c = $l.TrimEnd("`r") -split "`t", 4
        if ($c.Count -lt 4) { continue }
        $nome = $c[0] -replace '^refs/heads/', '' -replace '^refs/remotes/origin/', ''
        if ($nome -eq 'HEAD' -or $vistos.ContainsKey($nome)) { continue }
        $vistos[$nome] = $true
        [void]$lista.Add([pscustomobject]@{ nome = $nome; chave = $nome.ToLowerInvariant(); data = $c[1]; autor = $c[2]; assunto = $c[3]; local = $c[0].StartsWith('refs/heads/') })
    }
    $script:CacheBranches = [pscustomobject]@{ Quando = (Get-Date); Lista = $lista }
    return $lista
}

# Filtra por trechos do nome (todos precisam aparecer), ate 25 resultados.
function Listar-Branches([string]$Filtro) {
    $termos = @(([string]$Filtro).ToLowerInvariant() -split '\s+' | Where-Object { $_ })
    $lista = @()
    foreach ($b in (Todas-Branches)) {
        $casa = $true
        foreach ($t in $termos) { if (-not $b.chave.Contains($t)) { $casa = $false; break } }
        if (-not $casa) { continue }
        $lista += [ordered]@{ nome = $b.nome; data = $b.data; autor = $b.autor; assunto = $b.assunto; local = $b.local }
        if ($lista.Count -ge 25) { break }
    }
    return ,$lista
}

# Para cada base conhecida: quantos commits a branch tem fora dela e se o diff viria
# contaminado. Com o numero do card, sugere tambem "antes do 1o commit do card" (branch
# que ja foi mergeada na base da 0 commits contra ela).
function Sugerir-Bases([string]$Branch, [int]$Iid) {
    $repo = $script:Cfg.repoPadrao
    $b = Resolver-Ref $repo $Branch @('refs/heads/', 'refs/remotes/origin/', '')
    if (-not $b) { throw "Branch não encontrada: $Branch" }
    $lista = @()
    $cands = @()
    foreach ($nome in @($script:Cfg.git.basesSugeridas)) {
        $bs = Resolver-Ref $repo $nome @('refs/remotes/origin/', 'refs/heads/')
        if ($bs) { $cands += [pscustomobject]@{ nome = $nome; sha = $bs.Sha; tipo = 'branch'; topo = 0; citam = 0 } }
    }
    if ($Iid -gt 0) {
        # Commits do topo da branch (primeiro pai) ate o ultimo merge: e o trabalho feito
        # depois de a branch sair da geral (ou de receber o merge de outro card). Vale como
        # base quando pelo menos um deles cita o card ("Card 1099", "#1099"); separa o card
        # de um merge de outro card feito antes dele e de branch ja mergeada.
        $padrao = '(#|card[ _-]?)' + $Iid + '([^0-9]|$)'
        $log = Decodificar (Invoke-Git $repo @('log', '--first-parent', '--format=%H%x09%P%x09%s', '-n', '300', $b.Sha)).Saida ([System.Text.Encoding]::UTF8)
        $n = 0; $citam = 0
        foreach ($l in ($log -split "`n")) {
            $c = $l.TrimEnd("`r") -split "`t", 3
            if ($c.Count -lt 3) { continue }
            if (@($c[1] -split ' ' | Where-Object { $_ }).Count -le 1) {
                $n++
                if ([regex]::IsMatch($c[2], $padrao, 'IgnoreCase')) { $citam++ }
                continue
            }
            if ($citam -gt 0) {
                $cands += [pscustomobject]@{ nome = $c[0].Substring(0, 10); sha = $c[0]; tipo = 'card'; topo = $n; citam = $citam }
            }
            break
        }
    }
    foreach ($c in $cands) {
        $n = [int](Invoke-Git $repo @('rev-list', '--count', ($c.sha + '..' + $b.Sha))).Saida.Trim()
        $contaminada = $false
        foreach ($x in @($script:Cfg.git.commitsContaminados)) {
            if ((Testar-Ancestral $repo $x.sha $b.Sha) -eq $true -and (Testar-Ancestral $repo $x.sha $c.sha) -ne $true) { $contaminada = $true }
        }
        $lista += [ordered]@{ nome = $c.nome; tipo = $c.tipo; topo = $c.topo; citam = $c.citam; commits = $n; contaminada = $contaminada; recomendada = $false }
    }
    # Recomendacao:
    # - nenhuma base contem a branch: a branch com menos commits fora dela (de onde saiu);
    # - alguma base ja contem a branch (mergeada): os commits do topo que citam o card;
    # - mergeada (ou sem commit ainda) e sem commit citando o card: nao recomenda.
    $zerada = @($lista | Where-Object { $_.tipo -eq 'branch' -and $_.commits -eq 0 }).Count -gt 0
    $tipo = 'branch'
    if ($zerada) { $tipo = 'card' }
    $boas = @($lista | Where-Object { $_.tipo -eq $tipo -and -not $_.contaminada -and $_.commits -gt 0 } | Sort-Object { $_.commits })
    if ($boas.Count -gt 0) { $boas[0].recomendada = $true }
    return ,$lista
}

# Cards abertos atribuidos ao dono do token nos projetos do SIGCON (config "projetos"),
# mais recentes primeiro; cards de outros sistemas ficam de fora. Fica 60 s em memoria:
# a lista aparece toda vez que o dev clica no campo.
$script:CacheMeusCards = $null
function Meus-Cards {
    if ($script:CacheMeusCards -and ((Get-Date) - $script:CacheMeusCards.Quando).TotalSeconds -lt 60) { return ,$script:CacheMeusCards.Lista }
    $padrao = $script:Cfg.gitlabUrl.TrimEnd('/') + '/' + $script:Cfg.projetoPadrao + '/-/issues/'
    $todos = @()
    foreach ($p in @($script:Cfg.projetos)) {
        if (-not $p) { continue }
        $issues = Invoke-Gitlab -Caminho "/projects/$([int]$p.id)/issues?scope=assigned_to_me&state=opened&per_page=50&order_by=updated_at&sort=desc"
        foreach ($i in @($issues)) {
            if (-not $i) { continue }
            $url = [string]$i.web_url
            # no projeto padrao basta o numero; em outro projeto vai o link inteiro
            $valor = $url; if ($url.StartsWith($padrao)) { $valor = [string]$i.iid }
            $todos += [pscustomobject]@{ iid = $i.iid; titulo = [string]$i.title; url = $url; valor = $valor; projeto = [string]$p.nome; coluna = (Coluna-Atual $i); atualizado = [string]$i.updated_at }
        }
    }
    $lista = @()
    foreach ($c in @($todos | Sort-Object atualizado -Descending)) {
        $dia = $c.atualizado; if ($dia.Length -ge 10) { $dia = $dia.Substring(0, 10) }
        $lista += [ordered]@{ iid = $c.iid; titulo = $c.titulo; url = $c.url; valor = $c.valor; projeto = $c.projeto; coluna = $c.coluna; atualizado = $dia }
    }
    $script:CacheMeusCards = [pscustomobject]@{ Quando = (Get-Date); Lista = $lista }
    return ,$lista
}

function Previa-Card([string]$Texto) {
    $ref = Ler-ReferenciaCard $Texto
    $r = [ordered]@{ iid = $ref.Iid; url = $ref.Url; titulo = ''; coluna = ''; estado = ''; erro = '' }
    try {
        $projeto = Obter-ProjetoId $ref
        $issue = Invoke-Gitlab -Caminho "/projects/$projeto/issues/$($ref.Iid)"
        $r.titulo = $issue.title; $r.estado = $issue.state; $r.coluna = Coluna-Atual $issue
        if ($issue.web_url) { $r.url = $issue.web_url }
    } catch { $r.erro = $_.Exception.Message }
    return $r
}

# ---------------- execucao dos testes pelo dev ----------------

# out/<pasta>/execucao-testes.json: { cenarios: { "cenario-3": { titulo, feito, observacao, atualizadoEm } } }
# A chave e o numero do cenario; o agente le este arquivo quando o dev envia os resultados.
function Gravar-Teste($B) {
    if (-not $script:Estado.pasta) { throw 'Comece um card primeiro.' }
    $chave = Exigir $B.chave 'o cenario'
    if ($chave -notmatch '^[a-z0-9-]{1,60}$') { throw "Chave de cenário inválida: $chave" }
    $p = Join-Path (Dir-Card) 'execucao-testes.json'
    $cenarios = [ordered]@{}
    if (Test-Path -LiteralPath $p) {
        try {
            $lido = Ler-Json $p
            if ($lido.cenarios) { foreach ($x in $lido.cenarios.PSObject.Properties) { $cenarios[$x.Name] = $x.Value } }
        } catch { }
    }
    $cenarios[$chave] = [ordered]@{ titulo = [string]$B.titulo; feito = [bool]$B.feito; observacao = ([string]$B.observacao).Trim(); atualizadoEm = (Get-Date).ToString('s') }
    Gravar-Json $p ([ordered]@{ cenarios = $cenarios })
}

# ---------------- aprendizado ----------------

function Propostas-Json {
    $lista = @()
    $n = 0
    foreach ($p in @((Ler-Propostas).Propostas)) {
        $n++
        $lista += [ordered]@{
            n = $n; tipo = $p.Tipo; area = $p.Area; card = $p.Card; data = $p.Data
            regra = $p.Regra; porque = $p.PorQue; evidencia = $p.Evidencia
            problema = (Problema-DaProposta $p (Linhas-DaArea $p.Area))
        }
    }
    return ,$lista
}

# A pagina manda o numero e o texto da regra de cada proposta marcada: se o arquivo
# mudou desde que a lista foi mostrada (o agente acrescentou outra), os numeros nao
# batem mais e nada e gravado.
function Conferir-Propostas($Marcadas) {
    $atuais = Propostas-Json
    $numeros = @()
    foreach ($m in @($Marcadas | Where-Object { $_ })) {
        $n = [int]$m.n
        if ($n -lt 1 -or $n -gt $atuais.Count -or [string]$atuais[$n - 1].regra -ne [string]$m.regra) {
            throw 'As propostas mudaram desde que a lista foi carregada: recarregue a aba Aprendizado e marque de novo.'
        }
        $numeros += $n
    }
    return ,$numeros
}

# ---------------- HTTP ----------------

function Responder($Ctx, [int]$Status, [string]$Tipo, [byte[]]$Bytes) {
    $r = $Ctx.Response
    $r.StatusCode = $Status
    $r.ContentType = $Tipo
    $r.Headers['Cache-Control'] = 'no-store'
    $r.Headers['X-Content-Type-Options'] = 'nosniff'
    $r.ContentLength64 = $Bytes.Length
    $r.OutputStream.Write($Bytes, 0, $Bytes.Length)
    $r.OutputStream.Close()
}

function Responder-Json($Ctx, $Objeto, [int]$Status = 200) {
    $json = ConvertTo-Json -InputObject $Objeto -Depth 10 -Compress
    Responder $Ctx $Status 'application/json; charset=utf-8' ([System.Text.Encoding]::UTF8.GetBytes($json))
}

# Parametro da URL decodificado em UTF-8 (o encodeURIComponent da pagina). O QueryString do
# HttpListener decodifica na codificacao do Windows e estraga os acentos.
function Parametro($Req, [string]$Nome) {
    foreach ($par in ([string]$Req.Url.Query).TrimStart('?').Split('&')) {
        $kv = $par.Split('=', 2)
        if ([System.Uri]::UnescapeDataString($kv[0].Replace('+', ' ')) -eq $Nome) {
            if ($kv.Count -lt 2) { return '' }
            return [System.Uri]::UnescapeDataString($kv[1].Replace('+', ' '))
        }
    }
    return ''
}

function Ler-Corpo($Req) {
    $sr = New-Object System.IO.StreamReader($Req.InputStream, [System.Text.Encoding]::UTF8)
    $txt = $sr.ReadToEnd(); $sr.Close()
    if (-not $txt) { return [pscustomobject]@{} }
    return $txt | ConvertFrom-Json
}

function Exigir([string]$Valor, [string]$Nome) {
    if (-not ([string]$Valor).Trim()) { throw "Informe $Nome." }
    return ([string]$Valor).Trim()
}

function Montar-Estado {
    $t = $script:Estado.tarefa
    if (-not $script:Estado.titulo -and $script:Estado.pasta) {
        $ctxJson = Join-Path (Dir-Card) 'contexto.json'
        if (Test-Path -LiteralPath $ctxJson) { try { $script:Estado.titulo = [string](Ler-Json $ctxJson).titulo; Salvar-Estado } catch { } }
    }
    return [ordered]@{
        modo = $script:Estado.modo; card = $script:Estado.card; titulo = $script:Estado.titulo; branch = $script:Estado.branch; base = $script:Estado.base; inicio = $script:Estado.inicio
        iid = $script:Estado.iid; pasta = $script:Estado.pasta; temSessao = [bool]$script:Estado.sessaoId
        conversa = @($script:Estado.conversa)
        tarefa = $(if ($t) { [ordered]@{ tipo = $t.tipo; rodando = $t.rodando; inicio = $t.inicio; fim = $t.fim; codigo = $t.codigo; opcoes = $t.opcoes } } else { $null })
        log = (Texto-Log)
        ultimaSimulacao = $script:Estado.ultimaSimulacao
        arquivos = (Info-Arquivos)
        propostas = @((Ler-Propostas).Propostas).Count
        revisao = (Estado-Revisao)
        creditos = (Resumo-Creditos)
        resumo = (Resumo-Etapas)
        edicoes = (Estado-Edicoes)
    }
}

function Tratar($Ctx) {
    $req = $Ctx.Request
    $rota = $req.Url.AbsolutePath
    $metodo = $req.HttpMethod
    if ($metodo -eq 'POST' -and $req.Headers['X-Token'] -ne $script:Token) {
        Responder-Json $Ctx @{ erro = 'Token inválido: recarregue a página (o servidor foi reiniciado?).' } 403; return
    }
    if ($metodo -eq 'GET' -and $rota -eq '/') {
        $html = (Ler-Texto (Join-Path $script:Ui 'index.html')).Replace('__TOKEN__', $script:Token)
        Responder $Ctx 200 'text/html; charset=utf-8' ([System.Text.Encoding]::UTF8.GetBytes($html)); return
    }
    if ($metodo -eq 'GET' -and $script:Estaticos.ContainsKey($rota)) {
        Responder $Ctx 200 $script:Estaticos[$rota] ([System.IO.File]::ReadAllBytes((Join-Path $script:Ui $rota.TrimStart('/')))); return
    }
    # imagens de ui/public (logo, favicon): so nome simples, sem subpasta
    $mImg = [regex]::Match($rota, '^/public/([A-Za-z0-9._-]+\.(png|jpe?g|svg|ico|webp))$', 'IgnoreCase')
    if ($metodo -eq 'GET' -and $mImg.Success) {
        $arq = Join-Path $script:Ui ('public\' + $mImg.Groups[1].Value)
        if (-not (Test-Path -LiteralPath $arq)) { Responder-Json $Ctx @{ erro = 'imagem não encontrada' } 404; return }
        $tipos = @{ png = 'image/png'; jpg = 'image/jpeg'; jpeg = 'image/jpeg'; svg = 'image/svg+xml'; ico = 'image/x-icon'; webp = 'image/webp' }
        Responder $Ctx 200 $tipos[$mImg.Groups[2].Value.ToLowerInvariant()] ([System.IO.File]::ReadAllBytes($arq)); return
    }
    switch ("$metodo $rota") {
        'GET /api/estado' {
            Atualizar-Tarefa
            Responder-Json $Ctx (Montar-Estado); return
        }
        'GET /api/config' {
            $av = $script:Cfg.avaliacao
            Responder-Json $Ctx ([ordered]@{
                    atividades = @($script:Cfg.quadro.atividades); colunaDestino = $script:Cfg.quadro.colunaDestinoMover; moverSomenteDe = @($script:Cfg.quadro.moverSomenteDe)
                    avaliacao = [ordered]@{ atividade = [string]$av.atividade; colunaDestino = [string]$av.colunaDestino; referencias = @($av.referencias) }
                    avisos = @($script:AvisosInstalacao | ForEach-Object { [ordered]@{ nome = $_.Nome; detalhe = $_.Detalhe; como = $_.Como } })
                }); return
        }
        'GET /api/repo' {
            $atual = (Invoke-Git $script:Cfg.repoPadrao @('symbolic-ref', '--quiet', '--short', 'HEAD') -PermitirFalha).Saida.Trim()
            Responder-Json $Ctx ([ordered]@{ repo = $script:Cfg.repoPadrao; branchAtual = $atual }); return
        }
        'GET /api/branches' {
            Responder-Json $Ctx ([ordered]@{ branches = (Listar-Branches ((Parametro $req 'q'))) }); return
        }
        'GET /api/bases' {
            $iid = 0; [void][int]::TryParse((Parametro $req 'iid'), [ref]$iid)
            Responder-Json $Ctx ([ordered]@{ bases = (Sugerir-Bases ((Parametro $req 'branch')) $iid) }); return
        }
        'GET /api/colunas' {
            if (-not $script:Estado.card) { throw 'Comece um card primeiro.' }
            $ref = Ler-ReferenciaCard $script:Estado.card
            $projeto = Obter-ProjetoId $ref
            $issue = Invoke-Gitlab -Caminho "/projects/$projeto/issues/$($ref.Iid)"
            $q = Colunas-DoQuadro $projeto $issue
            $atualNorm = @($issue.labels | ForEach-Object { Normalizar-Texto $_ })
            $atual = @($q.colunas | Where-Object { $atualNorm -contains (Normalizar-Texto $_) }) | Select-Object -First 1
            # escala de pontos do projeto: a avaliacao tecnica escolhe uma no Publicar
            $pontos = @()
            if ($script:Estado.modo -eq 'avaliacao') {
                # atribuir antes: a lista inteira passada direto no pipeline vira um objeto so
                $escala = Etiquetas-DePontos (Listar-Etiquetas $projeto)
                $pontos = @($escala | ForEach-Object { [ordered]@{ pontos = $_.Pontos; nome = $_.Nome } })
            }
            Responder-Json $Ctx ([ordered]@{ quadro = $q.quadro; colunas = @($q.colunas); atual = [string]$atual; pontos = $pontos; pontosHoje = [string](Etiqueta-Pontos $issue) }); return
        }
        'GET /api/meus-cards' {
            Responder-Json $Ctx ([ordered]@{ cards = (Meus-Cards) }); return
        }
        'GET /api/card' {
            Responder-Json $Ctx (Previa-Card ((Parametro $req 'ref'))); return
        }
        'GET /api/arquivo' {
            $nome = (Parametro $req 'nome')
            if ($script:ArquivosDoCard -notcontains $nome) { throw "Arquivo não permitido: $nome" }
            $p = Join-Path (Dir-Card) $nome
            $txt = ''; if ($script:Estado.pasta -and (Test-Path -LiteralPath $p)) { $txt = Ler-Texto $p }
            Responder-Json $Ctx ([ordered]@{ nome = $nome; texto = $txt }); return
        }
        'POST /api/iniciar' {
            $b = Ler-Corpo $req
            $card = Exigir $b.card 'o link do card'; $branch = Exigir $b.branch 'a branch'; $base = Exigir $b.base 'a base'
            Atualizar-Tarefa
            if ($script:Estado.tarefa -and $script:Estado.tarefa.rodando) { throw 'Já existe uma tarefa rodando: espere terminar ou cancele.' }
            $ref = Ler-ReferenciaCard $card
            $pasta = Nome-PastaCard $ref
            Arquivar-Anteriores $pasta
            $script:Estado = Novo-Estado
            $card = $ref.Url
            $script:Estado.card = $card; $script:Estado.branch = $branch; $script:Estado.base = $base
            $script:Estado.iid = $ref.Iid; $script:Estado.pasta = $pasta; $script:Estado.titulo = [string]$b.titulo
            $script:Estado.inicio = (Get-Date).ToString('s')
            $marcador = "card-sigcon #$($ref.Iid) " + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            $texto = "Card: $card | Branch: $branch | Base: $base"
            $script:Estado.conversa = @([pscustomobject]@{ quem = 'dev'; texto = $texto; quando = (Get-Date).ToString('s') })
            Iniciar-Tarefa 'kiro' @{ mensagem = "$marcador (pagina do card-sigcon) | $texto. Comece o fluxo."; sessaoId = ''; marcador = $marcador }
            Responder-Json $Ctx @{ ok = $true }; return
        }
        'POST /api/iniciar-avaliacao' {
            # avaliacao tecnica: card + branch de referencia do codigo, sem branch do card
            $b = Ler-Corpo $req
            $card = Exigir $b.card 'o link do card'; $referencia = Exigir $b.referencia 'a branch de referência do código'
            Atualizar-Tarefa
            if ($script:Estado.tarefa -and $script:Estado.tarefa.rodando) { throw 'Já existe uma tarefa rodando: espere terminar ou cancele.' }
            $ref = Ler-ReferenciaCard $card
            $pasta = (Nome-PastaCard $ref) + '-avaliacao'
            Arquivar-Anteriores $pasta
            $script:Estado = Novo-Estado
            $script:Estado.modo = 'avaliacao'
            $script:Estado.card = $ref.Url; $script:Estado.branch = $referencia; $script:Estado.base = ''
            $script:Estado.iid = $ref.Iid; $script:Estado.pasta = $pasta; $script:Estado.titulo = [string]$b.titulo
            $script:Estado.inicio = (Get-Date).ToString('s')
            $marcador = "card-sigcon #$($ref.Iid) " + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            $texto = "Avaliação técnica | Card: $($ref.Url) | Referência: $referencia"
            $script:Estado.conversa = @([pscustomobject]@{ quem = 'dev'; texto = $texto; quando = (Get-Date).ToString('s') })
            Iniciar-Tarefa 'kiro' @{ mensagem = "$marcador (pagina do card-sigcon) | $texto. Comece a avaliação técnica (steering avaliacao-tecnica.md)."; sessaoId = ''; marcador = $marcador }
            Responder-Json $Ctx @{ ok = $true }; return
        }
        'POST /api/responder' {
            $b = Ler-Corpo $req
            $texto = Exigir $b.texto 'a resposta'
            if (-not $script:Estado.sessaoId) { throw 'Sessão do Kiro não identificada: comece o card de novo.' }
            $script:Estado.conversa = @($script:Estado.conversa) + @([pscustomobject]@{ quem = 'dev'; texto = $texto; quando = (Get-Date).ToString('s') })
            Iniciar-Tarefa 'kiro' @{ mensagem = $texto; sessaoId = $script:Estado.sessaoId }
            Responder-Json $Ctx @{ ok = $true }; return
        }
        'POST /api/simular' {
            $b = Ler-Corpo $req
            if (-not $script:Estado.card) { throw 'Comece um card primeiro.' }
            Iniciar-Tarefa 'simular' @{ tipo = 'card'; argumentos = (Argumentos-Card 'simular' $b); opcoes = (Chave-Opcoes $b) }
            Responder-Json $Ctx @{ ok = $true }; return
        }
        'POST /api/publicar' {
            $b = Ler-Corpo $req
            if ($b.confirmo -ne $true) { throw 'Publicação não confirmada.' }
            $u = $script:Estado.ultimaSimulacao
            if (-not $u -or $u.codigo -ne 0) { throw 'Rode o Simular (sem erro) antes de publicar.' }
            if ($u.opcoes -ne (Chave-Opcoes $b)) { throw 'As opções mudaram desde o último Simular: simule de novo.' }
            $info = Info-Arquivos
            foreach ($n in @($script:InvalidamSimular[[string]$script:Estado.modo])) {
                if ($info[$n] -and $info[$n] -gt [string]$u.quando) { throw "$n mudou depois do último Simular: simule de novo." }
            }
            Iniciar-Tarefa 'publicar' @{ tipo = 'card'; argumentos = (Argumentos-Card 'publicar' $b); opcoes = (Chave-Opcoes $b) }
            Responder-Json $Ctx @{ ok = $true }; return
        }
        'GET /api/texto' {
            Responder-Json $Ctx (Info-Texto (Parametro $req 'nome')); return
        }
        'POST /api/texto' {
            $b = Ler-Corpo $req
            Salvar-TextoEditado ([string]$b.nome) ([string]$b.texto)
            Responder-Json $Ctx (Info-Texto ([string]$b.nome)); return
        }
        'POST /api/texto/descartar' {
            $b = Ler-Corpo $req
            Descartar-TextoEditado ([string]$b.nome)
            Responder-Json $Ctx (Info-Texto ([string]$b.nome)); return
        }
        'GET /api/wiki' {
            $i = Ler-IndiceWiki
            $n = 0; $em = ''; if ($i) { $n = @($i.paginas).Count; $em = [string]$i.atualizadoEm }
            Responder-Json $Ctx ([ordered]@{ paginas = $n; atualizadaEm = $em }); return
        }
        'POST /api/wiki/atualizar' {
            Responder-Json $Ctx (Rodar-CardAgora @('wiki', '-Forcar')); return
        }
        'GET /api/evidencias' {
            Responder-Json $Ctx (Listar-Evidencias); return
        }
        'POST /api/evidencias' {
            $nome = Gravar-Evidencia $req
            Responder-Json $Ctx @{ ok = $true; nome = $nome }; return
        }
        'POST /api/evidencias/remover' {
            $b = Ler-Corpo $req
            Remove-Item -LiteralPath (Arquivo-Evidencia ([string]$b.chave) ([string]$b.nome))
            Responder-Json $Ctx @{ ok = $true }; return
        }
        'GET /api/evidencia' {
            $p = Arquivo-Evidencia ((Parametro $req 'chave')) ((Parametro $req 'nome'))
            $tipo = $script:TiposEvidencia[[System.IO.Path]::GetExtension($p).ToLowerInvariant()]
            if (-not $tipo) { $tipo = 'application/octet-stream' }
            Responder $Ctx 200 $tipo ([System.IO.File]::ReadAllBytes($p)); return
        }
        'POST /api/testes' {
            Gravar-Teste (Ler-Corpo $req)
            Responder-Json $Ctx @{ ok = $true }; return
        }
        'GET /api/revisao' {
            Responder-Json $Ctx ([ordered]@{ revisao = (Estado-Revisao -ComTexto) }); return
        }
        'POST /api/revisao' {
            Iniciar-Revisao
            Responder-Json $Ctx @{ ok = $true }; return
        }
        'POST /api/revisao/cancelar' {
            Cancelar-Revisao
            Responder-Json $Ctx @{ ok = $true }; return
        }
        'POST /api/cancelar' {
            Cancelar-Tarefa
            Responder-Json $Ctx @{ ok = $true }; return
        }
        'GET /api/propostas' {
            Responder-Json $Ctx ([ordered]@{ propostas = (Propostas-Json) }); return
        }
        'POST /api/aprender' {
            $b = Ler-Corpo $req
            $aceitar = Conferir-Propostas $b.aceitar
            $descartar = Conferir-Propostas $b.descartar
            if ($aceitar.Count + $descartar.Count -eq 0) { throw 'Marque pelo menos uma proposta.' }
            $a = @('aprender')
            if ($aceitar.Count) { $a += @('-Aceitar', ($aceitar -join ',')) }
            if ($descartar.Count) { $a += @('-Descartar', ($descartar -join ',')) }
            Responder-Json $Ctx (Rodar-CardAgora $a); return
        }
    }
    Responder-Json $Ctx @{ erro = "Rota desconhecida: $metodo $rota" } 404
}

# ---------------- laco principal ----------------

$script:Estado = Carregar-Estado
$script:Revisao = Carregar-Revisao
# antes da limpeza, que apaga as conversas velhas do Kiro (e o consumo gravado nelas)
try { Importar-CreditosAntigos } catch { Write-Host "AVISO: não consegui importar o consumo das conversas antigas ($($_.Exception.Message))." }
# Limpeza de cards e conversas sem uso (config "limpeza"); o card aberto fica.
if ($script:Cfg.limpeza -and $script:Cfg.limpeza.aoAbrirPagina -eq $true) {
    try {
        $r = Limpar-Antigos -Dias (Dias-DaLimpeza 0) -PastaAtual $script:Estado.pasta -SessaoAtual $script:Estado.sessaoId
        Write-Host (Resumo-Limpeza $r $false)
    } catch {
        Write-Host "AVISO: a limpeza automática falhou ($($_.Exception.Message)); seguindo sem limpar."
    }
}
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Porta/")
try { $listener.Start() } catch { Write-Host "ERRO: não consegui abrir a porta $Porta ($($_.Exception.Message)). Tente: card-ui.cmd -Porta 8766"; exit 1 }
$url = "http://localhost:$Porta/"
Write-Host "Kiro updater: página em $url  (Ctrl+C para parar)"
if (-not $NaoAbrir) { Start-Process $url }
try {
    while ($listener.IsListening) {
        $pendente = $listener.GetContextAsync()
        # Espera em fatias para o Ctrl+C conseguir parar o servidor.
        while (-not $pendente.AsyncWaitHandle.WaitOne(500)) { }
        $ctx = $pendente.Result
        try { Tratar $ctx }
        catch {
            try { Responder-Json $ctx @{ erro = $_.Exception.Message } 400 } catch { }
        }
    }
} finally {
    $listener.Stop()
}
