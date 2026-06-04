param(
    [string]$Content,
    [string]$OutputPath
)
$STATE   = Join-Path $PSScriptRoot "state.json"
$allowed = [System.IO.Path]::GetFullPath([Environment]::GetFolderPath('MyDocuments'))

# SEC-02: Validate output path is within the allowed directory
$resolved = try { [System.IO.Path]::GetFullPath($OutputPath) } catch { "" }
if (-not $resolved -or -not $resolved.StartsWith($allowed + '\')) {
    Write-Output "denied"; return
}

[System.IO.File]::WriteAllText($resolved, $Content, [System.Text.Encoding]::UTF8)

# Signal the window via JSON object update
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
if ($raw -and $raw.Trim() -ne '') {
    try {
        $obj = $raw | ConvertFrom-Json
        $obj.framework_path = $resolved
        Write-Atomic $STATE ($obj | ConvertTo-Json -Compress -Depth 6)
    } catch {}
}

Write-Output "done"
