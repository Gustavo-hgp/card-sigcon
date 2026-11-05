# card-sigcon - creditos do Kiro gastos por turno.
# O kiro-cli grava em %USERPROFILE%\.kiro\sessions\cli\<sessao>.json, para cada mensagem do
# dev, session_state.conversation_metadata.user_turn_metadatas[].metering_usage (unit
# "credit"). E formato interno do Kiro: se mudar, as funcoes devolvem $null e a pagina so
# deixa de mostrar o custo.
# Salvo em UTF-8 com BOM (ver lib/Comum.ps1).

function Arquivo-SessaoKiro([string]$Id) {
    if ($Id -notmatch '^[A-Za-z0-9-]{8,64}$') { return $null }
    $p = Join-Path $env:USERPROFILE ".kiro\sessions\cli\$Id.json"
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    return $p
}

# Turnos da sessao: { Quando (data local), Creditos }. $null se nao deu para ler.
function Turnos-DaSessao([string]$Id) {
    $p = Arquivo-SessaoKiro $Id
    if (-not $p) { return $null }
    try {
        $d = [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        $lista = @()
        foreach ($t in @($d.session_state.conversation_metadata.user_turn_metadatas)) {
            if (-not $t) { continue }
            $soma = 0.0
            foreach ($m in @($t.metering_usage)) { if ($m -and $m.unit -eq 'credit') { $soma += [double]$m.value } }
            # "2026-10-28T18:00:11.262725600Z": o .NET so le ate 7 casas de fracao
            $quando = $null
            $iso = [string]$t.end_timestamp
            if ($iso.Length -ge 19) {
                $utc = [datetime]::MinValue
                if ([datetime]::TryParse($iso.Substring(0, 19) + 'Z', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$utc)) { $quando = $utc.ToLocalTime() }
            }
            $lista += [pscustomobject]@{ Quando = $quando; Creditos = $soma }
        }
        return ,$lista
    } catch { return $null }
}

function Creditos-DaSessao([string]$Id) {
    $turnos = Turnos-DaSessao $Id
    if ($null -eq $turnos) { return $null }
    $soma = 0.0
    foreach ($t in $turnos) { $soma += $t.Creditos }
    return $soma
}
