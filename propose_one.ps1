param(
    [string]$Title,
    [string]$Content,
    [string]$Sim,
    [string]$NodeId,
    [string]$RequestTs,
    [string[]]$Components = @(),  # Pass as native PS string array: -Components "A","B","C"
    [string]$ComponentData = '[]' # JSON array: [{"construct":"Manager","fields":[{"name":"x","type":"T"}],"deps":["SysName"]}]
)
$STATE = Join-Path $PSScriptRoot "state.json"

function Write-Atomic([string]$path, [string]$content) {
    $tmp = "$path.tmp"
    for ($i = 0; $i -lt 3; $i++) {
        try {
            Set-Content $tmp $content -NoNewline -Encoding UTF8
            Move-Item $tmp $path -Force
            return
        } catch { Start-Sleep -Milliseconds 50 }
    }
}

$raw = Get-Content $STATE -Raw -ErrorAction SilentlyContinue
if (-not $raw -or $raw.Trim() -eq '') { Write-Output "deny"; return }

try { $obj = $raw | ConvertFrom-Json } catch { Write-Output "deny"; return }

$obj.title         = $Title
$obj.content       = $Content
$obj.selected_node = $NodeId
$obj.response      = ''

try   { $obj.sim = $Sim | ConvertFrom-Json } catch { $obj.sim = $null }

# Unwrap JSON array string if Claude accidentally passed '["A","B"]' instead of "A","B"
if ($Components.Count -eq 1) {
    $s = $Components[0].Trim()
    if ($s.StartsWith('[') -and $s.EndsWith(']') -and $s.Contains('"')) {
        try { $parsed = $s | ConvertFrom-Json; $Components = @($parsed) } catch {}
    }
}

# Build ArrayList so ConvertTo-Json always emits a JSON array (even 1 element)
$compsList = New-Object System.Collections.ArrayList
foreach ($c in $Components) { [void]$compsList.Add([string]$c) }
$obj.components = $compsList

# Write component metadata using ArrayList so ConvertTo-Json always emits a proper JSON array
# (ConvertFrom-Json returns a wrapped PS type that serializes as {"value":[...],"Count":N} — ArrayList fixes this)
$cdList = New-Object System.Collections.ArrayList
try {
    $parsed = $ComponentData | ConvertFrom-Json
    if ($parsed -is [array]) {
        foreach ($item in $parsed) { [void]$cdList.Add($item) }
    } elseif ($null -ne $parsed) {
        [void]$cdList.Add($parsed)
    }
} catch {}
$obj.component_data = $cdList

Write-Atomic $STATE ($obj | ConvertTo-Json -Compress -Depth 6)

$dec = & (Join-Path $PSScriptRoot "get_decision.ps1") -RequestTs $RequestTs
Write-Output $dec
