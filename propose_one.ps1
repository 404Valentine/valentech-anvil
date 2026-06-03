param(
    [string]$Title,
    [string]$Content,
    [string]$Sim,
    [string]$NodeId,
    [string]$RequestTs,
    [string[]]$Components = @()   # Pass as native PS string array: -Components "A","B","C"
)
$STATE = Join-Path $PSScriptRoot "state.json"

$raw = Get-Content $STATE -Raw -ErrorAction SilentlyContinue
if (-not $raw -or $raw.Trim() -eq '') { Write-Output "deny"; return }

try { $obj = $raw | ConvertFrom-Json } catch { Write-Output "deny"; return }

$obj.title         = $Title
$obj.content       = $Content
$obj.selected_node = $NodeId
$obj.response      = ''

try   { $obj.sim = $Sim | ConvertFrom-Json } catch { $obj.sim = $null }

# Build ArrayList so ConvertTo-Json always emits a JSON array (even 1 element)
$compsList = New-Object System.Collections.ArrayList
foreach ($c in $Components) { [void]$compsList.Add([string]$c) }
$obj.components = $compsList

Set-Content $STATE ($obj | ConvertTo-Json -Compress -Depth 6) -NoNewline -Encoding UTF8

$dec = & (Join-Path $PSScriptRoot "get_decision.ps1") -RequestTs $RequestTs
Write-Output $dec
