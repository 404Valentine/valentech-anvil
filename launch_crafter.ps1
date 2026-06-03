$ROOT     = $PSScriptRoot
$PID_F    = Join-Path $ROOT "window.pid"
$STATE    = Join-Path $ROOT "state.json"
$LAUNCH_F = Join-Path $ROOT "launch_ts.txt"
$VBS      = Join-Path $ROOT "run_hidden.vbs"
$WIN      = Join-Path $ROOT "window.ps1"

# Kill existing instance
if (Test-Path $PID_F) {
    $old = Get-Content $PID_F -ErrorAction SilentlyContinue
    if ($old) { Stop-Process -Id ([int]$old) -Force -ErrorAction SilentlyContinue }
    Remove-Item $PID_F -Force -ErrorAction SilentlyContinue
}

# Reset state
$blank = @'
{
  "gdd_raw":        "",
  "nodes":          [],
  "selected_node":  "",
  "title":          "",
  "content":        "",
  "sim":            "",
  "response":       "",
  "request":        "",
  "request_ts":     0,
  "sim_issues_ts":  0,
  "generate_ts":    0,
  "gdd_filename":   "",
  "framework_path": "",
  "gdd_section":    "",
  "components":     []
}
'@
Set-Content $STATE $blank -NoNewline

# Write launch timestamp so any running outer monitor can detect a new launch
[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds().ToString() | Set-Content $LAUNCH_F -NoNewline

# Launch window hidden
$wshell = New-Object -ComObject WScript.Shell
$wshell.Run("wscript.exe `"$VBS`" `"$WIN`"", 0, $false)
Write-Output "ValenTech Anvil launched."
