# card-sigcon - API REST do GitLab com o token pessoal do dev (GITLAB_TOKEN, escopo api).
# Usa HttpWebRequest para controlar o encoding: corpo enviado em bytes UTF-8 e resposta
# lida como UTF-8 (o Invoke-RestMethod do PowerShell 5.1 quebra acento nos dois sentidos).

try {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
} catch { }

function Definir-Parametro([string]$Url, [string]$Nome, [string]$Valor) {
    $padrao = '([?&])' + [regex]::Escape($Nome) + '=[^&]*'
    if ([regex]::IsMatch($Url, $padrao)) { return [regex]::Replace($Url, $padrao, ('${1}' + $Nome + '=' + $Valor)) }
    $sep = '?'; if ($Url.Contains('?')) { $sep = '&' }
    return $Url + $sep + $Nome + '=' + $Valor
}

function Token-Gitlab {
    $token = $env:GITLAB_TOKEN
    # Variavel gravada para o usuario depois que o terminal/Kiro abriu ainda nao esta no processo.
    if (-not $token) { $token = [Environment]::GetEnvironmentVariable('GITLAB_TOKEN', 'User') }
    if (-not $token) { throw 'GITLAB_TOKEN não definido. Crie um token pessoal no GitLab e coloque no arquivo .env desta pasta (copie o .env.exemplo) ou na variável de ambiente GITLAB_TOKEN (veja o guia de instalação).' }
    return $token
}

# Resposta do GitLab como objeto; erro HTTP vira excecao com o corpo da resposta.
function Resposta-Gitlab($Req, [string]$Descricao) {
    try {
        $resp = $Req.GetResponse()
    } catch {
        $ex = $_.Exception
        while ($ex -and -not ($ex -is [System.Net.WebException])) { $ex = $ex.InnerException }
        $msg = $_.Exception.Message
        if ($ex -and $ex.Response) {
            $sr = New-Object System.IO.StreamReader($ex.Response.GetResponseStream(), [System.Text.Encoding]::UTF8)
            $msg = "HTTP $([int]$ex.Response.StatusCode) $($sr.ReadToEnd())"
            $sr.Close()
        }
        throw "GitLab $Descricao falhou: $msg"
    }
    return $resp
}

# Envia um arquivo ao projeto (anexo de comentario) e devolve o que o GitLab responde
# (markdown, url). Multipart montado aqui: o PowerShell 5.1 nao tem cliente multipart.
function Enviar-ArquivoGitlab([int]$ProjetoId, [string]$Caminho) {
    $token = Token-Gitlab
    $nome = [System.IO.Path]::GetFileName($Caminho)
    $tipos = @{ '.png' = 'image/png'; '.jpg' = 'image/jpeg'; '.jpeg' = 'image/jpeg'; '.gif' = 'image/gif'; '.webp' = 'image/webp'; '.mp4' = 'video/mp4'; '.webm' = 'video/webm'; '.mov' = 'video/quicktime' }
    $tipo = $tipos[[System.IO.Path]::GetExtension($nome).ToLowerInvariant()]
    if (-not $tipo) { $tipo = 'application/octet-stream' }
    $limite = 'card-sigcon-' + [guid]::NewGuid().ToString('N')
    $cab = [System.Text.Encoding]::UTF8.GetBytes("--$limite`r`nContent-Disposition: form-data; name=`"file`"; filename=`"$nome`"`r`nContent-Type: $tipo`r`n`r`n")
    $fim = [System.Text.Encoding]::UTF8.GetBytes("`r`n--$limite--`r`n")
    $req = [System.Net.HttpWebRequest]::Create($script:Cfg.gitlabUrl.TrimEnd('/') + "/api/v4/projects/$ProjetoId/uploads")
    $req.Method = 'POST'
    $req.Accept = 'application/json'
    $req.Timeout = 600000
    $req.ReadWriteTimeout = 600000
    $req.Headers.Add('PRIVATE-TOKEN', $token)
    $req.ContentType = "multipart/form-data; boundary=$limite"
    $req.AllowWriteStreamBuffering = $false
    $req.ContentLength = $cab.Length + (Get-Item -LiteralPath $Caminho).Length + $fim.Length
    $s = $req.GetRequestStream()
    try {
        $s.Write($cab, 0, $cab.Length)
        $f = [System.IO.File]::OpenRead($Caminho)
        try { $f.CopyTo($s) } finally { $f.Close() }
        $s.Write($fim, 0, $fim.Length)
    } finally { $s.Close() }
    $resp = Resposta-Gitlab $req "upload de $nome"
    $sr = New-Object System.IO.StreamReader($resp.GetResponseStream(), [System.Text.Encoding]::UTF8)
    $texto = $sr.ReadToEnd(); $sr.Close(); $resp.Close()
    return ($texto | ConvertFrom-Json)
}

function Invoke-Gitlab {
    param([string]$Metodo = 'GET', [string]$Caminho, $Corpo = $null, [switch]$Todas)
    $token = Token-Gitlab
    $url = $script:Cfg.gitlabUrl.TrimEnd('/') + '/api/v4' + $Caminho
    $resultado = New-Object System.Collections.ArrayList
    while ($true) {
        $req = [System.Net.HttpWebRequest]::Create($url)
        $req.Method = $Metodo
        $req.Accept = 'application/json'
        $req.Timeout = 60000
        $req.Headers.Add('PRIVATE-TOKEN', $token)
        if ($null -ne $Corpo) {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $Corpo -Depth 20 -Compress))
            $req.ContentType = 'application/json; charset=utf-8'
            $req.ContentLength = $bytes.Length
            $s = $req.GetRequestStream(); $s.Write($bytes, 0, $bytes.Length); $s.Close()
        }
        $resp = Resposta-Gitlab $req "$Metodo $Caminho"
        $sr = New-Object System.IO.StreamReader($resp.GetResponseStream(), [System.Text.Encoding]::UTF8)
        $texto = $sr.ReadToEnd(); $sr.Close()
        $proxima = $resp.Headers['X-Next-Page']
        $resp.Close()
        $dados = $null
        if ($texto) { $dados = $texto | ConvertFrom-Json }
        if (-not $Todas) { return $dados }
        foreach ($d in @($dados)) { if ($null -ne $d) { [void]$resultado.Add($d) } }
        if (-not $proxima) { break }
        $url = Definir-Parametro $url 'page' $proxima
    }
    return ,$resultado.ToArray()
}

# Projetos do SIGCON conhecidos (config "projetos"): id e nome curto por caminho.
function Projeto-Conhecido([string]$Caminho) {
    foreach ($p in @($script:Cfg.projetos)) { if ($p -and [string]$p.path -eq $Caminho) { return $p } }
    return $null
}

function Obter-ProjetoId($Ref) {
    $conhecido = Projeto-Conhecido $Ref.Projeto
    if ($conhecido) { return [int]$conhecido.id }
    try {
        return [int](Invoke-Gitlab -Caminho ('/projects/' + [uri]::EscapeDataString($Ref.Projeto))).id
    } catch {
        $nome = ($Ref.Projeto -split '/')[-1]
        $lista = Invoke-Gitlab -Caminho ('/projects?simple=true&per_page=100&search=' + [uri]::EscapeDataString($nome)) -Todas
        foreach ($p in $lista) { if ($p.path_with_namespace -eq $Ref.Projeto) { return [int]$p.id } }
        throw "Projeto não encontrado no GitLab: $($Ref.Projeto)"
    }
}

# Colunas do quadro do card, na ordem do quadro (cada coluna e uma etiqueta). Escolhe o
# quadro do projeto que tem a coluna atual do card; sem isso, o que tem mais colunas.
function Colunas-DoQuadro([int]$ProjetoId, $Issue) {
    # atribuir antes de filtrar: o -Todas devolve a lista como um objeto so no pipeline
    $todos = Invoke-Gitlab -Caminho "/projects/$ProjetoId/boards" -Todas
    $quadros = @($todos | ForEach-Object { $_ } | Where-Object { $_ })
    $escolhido = $null
    $etqCard = @($Issue.labels | ForEach-Object { Normalizar-Texto $_ })
    foreach ($q in $quadros) {
        $nomes = @($q.lists | Where-Object { $_.label } | ForEach-Object { Normalizar-Texto $_.label.name })
        if (@($nomes | Where-Object { $etqCard -contains $_ }).Count -gt 0) { $escolhido = $q; break }
    }
    if (-not $escolhido) { $escolhido = $quadros | Sort-Object { @($_.lists).Count } -Descending | Select-Object -First 1 }
    if (-not $escolhido) { return [pscustomobject]@{ quadro = ''; colunas = @() } }
    $colunas = @($escolhido.lists | Where-Object { $_.label } | Sort-Object { [int]$_.position } | ForEach-Object { [string]$_.label.name })
    return [pscustomobject]@{ quadro = [string]$escolhido.name; colunas = $colunas }
}

function Listar-Etiquetas([int]$ProjetoId) {
    return Invoke-Gitlab -Caminho "/projects/$ProjetoId/labels?per_page=100&include_ancestor_groups=true" -Todas
}

# Nome real da etiqueta (com acento) a partir de um nome escrito sem acento na config.
function Achar-Etiqueta($Etiquetas, [string]$Nome) {
    $alvo = Normalizar-Texto $Nome
    foreach ($e in @($Etiquetas)) { if ((Normalizar-Texto $e.name) -eq $alvo) { return $e.name } }
    return $null
}

function Tem-Etiqueta($Issue, [string]$Nome) {
    $alvo = Normalizar-Texto $Nome
    foreach ($l in @($Issue.labels)) { if ((Normalizar-Texto $l) -eq $alvo) { return $true } }
    return $false
}

function Notas-Humanas($Notas) {
    return ,@($Notas | Where-Object { -not $_.system })
}
