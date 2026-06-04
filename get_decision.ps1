param([string]$RequestTs)
$STATE   = Join-Path $PSScriptRoot "state.json"
$PID_F   = Join-Path $PSScriptRoot "window.pid"
$lastWrite = [datetime]::MinValue

while ($true) {
    Start-Sleep -Milliseconds 400

    # Exit if window closed or process behind pid file is dead (crash recovery)
    if (-not (Test-Path $PID_F)) { Write-Output "deny"; return }
    try {
        if (-not (Get-Process -Id ([int](Get-Content $PID_F -Raw).Trim()) -ErrorAction SilentlyContinue)) {
            Write-Output "deny"; return
        }
    } catch {}

    # Skip read if state.json hasn't changed
    $fi = Get-Item $STATE -ErrorAction SilentlyContinue
    if (-not $fi -or $fi.LastWriteTime -le $lastWrite) { continue }
    $lastWrite = $fi.LastWriteTime

    $raw = Get-Content $STATE -Raw -ErrorAction SilentlyContinue
    if (-not $raw -or -not $raw.Trim()) { continue }

    try { $obj = $raw | ConvertFrom-Json } catch { continue }

    $resp = [string]$obj.response
    $rts  = [string]$obj.request_ts

    if ($resp) { Write-Output $resp; return }

    # A new node was selected — our proposal is stale
    if ($rts -and $rts -ne '0' -and $rts -ne $RequestTs) {
        Write-Output 'new_request'; return
    }
}
