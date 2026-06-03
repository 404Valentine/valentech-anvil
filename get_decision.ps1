param([string]$RequestTs)
$STATE   = Join-Path $PSScriptRoot "state.json"
$PID_F   = Join-Path $PSScriptRoot "window.pid"
$timeout = 120  # seconds
$elapsed = 0

while ($true) {
    Start-Sleep -Milliseconds 400
    $elapsed += 0.4

    # Exit if window closed
    if (-not (Test-Path $PID_F)) { Write-Output "deny"; return }

    # Exit if timed out (prevents zombie loops after relaunch)
    if ($elapsed -ge $timeout) { Write-Output "deny"; return }

    $raw = Get-Content $STATE -Raw -ErrorAction SilentlyContinue
    if (-not $raw -or $raw.Trim() -eq '') { continue }

    try { $obj = $raw | ConvertFrom-Json } catch { continue }

    $resp = [string]$obj.response
    $rts  = [string]$obj.request_ts

    if ($resp -and $resp -ne '') { Write-Output $resp; return }

    # A new node was selected — our proposal is stale
    if ($rts -and $rts -ne '0' -and $rts -ne $RequestTs) {
        Write-Output 'new_request'; return
    }
}
