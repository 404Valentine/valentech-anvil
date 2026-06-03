param(
    [string]$Content,
    [string]$OutputPath
)
$STATE   = Join-Path $PSScriptRoot "state.json"
$allowed = [System.IO.Path]::GetFullPath([Environment]::GetFolderPath('MyDocuments'))

# SEC-02: Validate output path is within the allowed directory
$resolved = try { [System.IO.Path]::GetFullPath($OutputPath) } catch { "" }
if (-not $resolved -or -not $resolved.StartsWith($allowed)) {
    Write-Output "denied"; return
}

[System.IO.File]::WriteAllText($resolved, $Content, [System.Text.Encoding]::UTF8)

# Signal the window via JSON object update
$raw = Get-Content $STATE -Raw -ErrorAction SilentlyContinue
if ($raw -and $raw.Trim() -ne '') {
    try {
        $obj = $raw | ConvertFrom-Json
        $obj.framework_path = $resolved
        Set-Content $STATE ($obj | ConvertTo-Json -Compress -Depth 6) -NoNewline -Encoding UTF8
    } catch {}
}

Write-Output "done"
