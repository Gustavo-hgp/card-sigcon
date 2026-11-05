# card-sigcon - camada 1 da checagem de banco (sem IA).
# No SIGCON o script de banco quase nunca esta no diff, entao a checagem olha os sinais
# no codigo (entidade, SQL nativo, enum de dominio, permissao) e confere se cada nome
# novo ja aparecia na base. A camada 2 (agente) julga os achados; a 3 e o dev.

function Analisar-Banco($Arquivos, [string]$Repo, [string]$BaseSha) {
    $cfg = $script:Cfg.banco
    $achados = New-Object System.Collections.ArrayList
    $ids = [ordered]@{}

    foreach ($a in @($Arquivos)) {
        foreach ($r in @($cfg.arquivos)) {
            if (-not [regex]::IsMatch($a.Caminho, $r.arquivo)) { continue }
            if ($r.somenteNovo -and $a.Status -ne 'A') { continue }
            [void]$achados.Add([pscustomobject]@{ Tipo = $r.nome; Arquivo = $a.Caminho; Linha = 0; Trecho = $r.descricao })
        }
        $ehEnum = [regex]::IsMatch($a.Caminho, '/enums/')
        foreach ($l in @($a.LinhasAdicionadas)) {
            $t = $l.Texto
            if (-not $t.Trim()) { continue }
            if ([regex]::IsMatch($t, '^\s*(//|\*|/\*)')) { continue }
            foreach ($p in @($cfg.linhas)) {
                if ($p.arquivo -and -not [regex]::IsMatch($a.Caminho, $p.arquivo)) { continue }
                if ([regex]::IsMatch($t, $p.regex)) {
                    [void]$achados.Add([pscustomobject]@{ Tipo = $p.nome; Arquivo = $a.Caminho; Linha = $l.Linha; Trecho = $t.Trim() })
                }
            }
            foreach ($m in [regex]::Matches($t, $cfg.regexObjeto)) {
                $chave = 'objeto|' + $m.Value
                if (-not $ids.Contains($chave)) { $ids[$chave] = [pscustomobject]@{ Tipo = 'objeto'; Nome = $m.Value; Arquivo = $a.Caminho; Linha = $l.Linha; Escopo = '' } }
            }
            foreach ($m in [regex]::Matches($t, $cfg.regexNomeAnotacao)) {
                $nome = $m.Groups[1].Value
                if ([regex]::IsMatch($nome, $cfg.regexObjeto)) { continue }
                $chave = 'coluna|' + $a.Caminho + '|' + $nome
                if (-not $ids.Contains($chave)) { $ids[$chave] = [pscustomobject]@{ Tipo = 'coluna'; Nome = $nome; Arquivo = $a.Caminho; Linha = $l.Linha; Escopo = $a.Caminho } }
            }
            if ($ehEnum) {
                $m = [regex]::Match($t, $cfg.regexValorEnum)
                if ($m.Success) {
                    $chave = 'enum|' + $a.Caminho + '|' + $m.Groups[1].Value
                    if (-not $ids.Contains($chave)) { $ids[$chave] = [pscustomobject]@{ Tipo = 'valor-enum'; Nome = $m.Groups[1].Value; Arquivo = $a.Caminho; Linha = $l.Linha; Escopo = $a.Caminho } }
                }
            }
            $m = [regex]::Match($t, $cfg.regexPermissao)
            if ($m.Success) {
                $chave = 'permissao|' + $a.Caminho + '|' + $m.Groups[1].Value
                if (-not $ids.Contains($chave)) { $ids[$chave] = [pscustomobject]@{ Tipo = 'permissao'; Nome = $m.Groups[1].Value; Arquivo = $a.Caminho; Linha = $l.Linha; Escopo = $a.Caminho } }
            }
        }
    }

    $status = @{}
    foreach ($a in @($Arquivos)) { $status[$a.Caminho] = $a.Status }
    $identificadores = @()
    $n = 0
    foreach ($id in $ids.Values) {
        $n++
        $existe = $null
        if ($n -le $cfg.limiteIdentificadores) {
            if ($id.Escopo -and $status[$id.Escopo] -eq 'A') { $existe = $false }
            else { $existe = Nome-ApareceNaBase $Repo $BaseSha $id.Nome $id.Escopo }
        }
        $identificadores += [pscustomobject]@{ Tipo = $id.Tipo; Nome = $id.Nome; Arquivo = $id.Arquivo; Linha = $id.Linha; ExisteNaBase = $existe }
    }

    $novos = @($identificadores | Where-Object { $_.ExisteNaBase -eq $false })
    $fortes = @($achados | Where-Object { @('script-sql', 'entidade-nova', 'mapeamento', 'dml-ddl') -contains $_.Tipo })
    return [pscustomobject]@{
        Indicio = (($novos.Count + $fortes.Count) -gt 0)
        Achados = @($achados)
        Identificadores = $identificadores
        Novos = $novos
        Scripts = @($achados | Where-Object { $_.Tipo -eq 'script-sql' } | ForEach-Object { $_.Arquivo })
    }
}
