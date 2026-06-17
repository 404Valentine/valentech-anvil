param(
    [string]$Path
)

if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Container)) {
    '{"error":"path not found"}'; return
}

$rootFull = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')

function Parse-CsFile([string]$filePath) {
    $text = Get-Content $filePath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
    if (-not $text) { return $null }

    $className = ''
    if ($text -match '(?m)public\s+(?:static\s+)?(?:abstract\s+)?(?:partial\s+)?(?:class|interface)\s+(\w+)') {
        $className = $Matches[1]
    }
    if (-not $className) { return $null }

    $construct = 'Unknown'
    if     ($text -match 'public\s+interface\s+\w+')    { $construct = 'Interface' }
    elseif ($text -match ':\s*ScriptableObject\b')      { $construct = 'ScriptableObject' }
    elseif ($text -match ':\s*MonoBehaviour\b') {
        if ($text -match 'public\s+static\s+\w+\s+Instance') { $construct = 'Manager' }
        else { $construct = 'MonoBehaviour' }
    } elseif ($text -match 'public\s+static\s+class\s+\w+') {
        if ($text -match '\bevent\s+Action\b') { $construct = 'EventBus' }
        else { $construct = 'Utility' }
    }

    # Public instance fields — 4-space indent, not static/override/virtual/abstract/const
    $fields = [System.Collections.Generic.List[hashtable]]::new()
    $rFlds  = [regex]::Matches($text, '(?m)^    public\s+(?!static\s|override\s|virtual\s|abstract\s|const\s)([A-Za-z][A-Za-z0-9<>\[\], ?]*?)\s+([a-z][a-zA-Z0-9_]*)\s*;')
    foreach ($m in $rFlds) {
        $ft = $m.Groups[1].Value.Trim()
        $fn = $m.Groups[2].Value.Trim()
        if ($ft -notmatch '^void$') { $fields.Add(@{ name = $fn; type = $ft }) }
    }

    # [SerializeField] dep types
    $deps  = [System.Collections.Generic.List[string]]::new()
    $rDeps = [regex]::Matches($text, '\[SerializeField\]\s*private\s+(\w+)\s+\w+\s*;')
    foreach ($m in $rDeps) { $deps.Add($m.Groups[1].Value) }

    return @{
        className = $className
        construct = $construct
        fields    = @($fields)
        deps      = @($deps)
    }
}

# Detect scaffold (Assets/Scripts/<System>/) vs flat
$assetsPath = Join-Path $rootFull 'Assets\Scripts'
$format = if (Test-Path $assetsPath -PathType Container) { 'scaffold' } else { 'flat' }

$systems = [System.Collections.Generic.List[hashtable]]::new()

if ($format -eq 'scaffold') {
    foreach ($d in (Get-ChildItem $assetsPath -Directory -ErrorAction SilentlyContinue)) {
        $feats = [System.Collections.Generic.List[hashtable]]::new()
        foreach ($cf in (Get-ChildItem $d.FullName -Filter '*.cs' -ErrorAction SilentlyContinue)) {
            $p = Parse-CsFile $cf.FullName
            if ($p) { $feats.Add($p) }
        }
        if ($feats.Count -gt 0) { $systems.Add(@{ name = $d.Name; features = @($feats) }) }
    }
} else {
    $grouped = [ordered]@{}
    foreach ($cf in (Get-ChildItem $rootFull -Filter '*.cs' -Recurse -ErrorAction SilentlyContinue)) {
        $p = Parse-CsFile $cf.FullName
        if (-not $p) { continue }
        $dir     = [System.IO.Path]::GetDirectoryName($cf.FullName)
        $sysName = if ($dir -ne $rootFull) {
            [System.IO.Path]::GetFileName($dir)
        } elseif ($cf.BaseName -match '^([A-Z][a-zA-Z0-9]+)_') {
            $Matches[1]
        } else { 'General' }
        if (-not $grouped.Contains($sysName)) {
            $grouped[$sysName] = [System.Collections.Generic.List[hashtable]]::new()
        }
        $grouped[$sysName].Add($p)
    }
    foreach ($kv in $grouped.GetEnumerator()) {
        $systems.Add(@{ name = $kv.Key; features = @($kv.Value) })
    }
}

@{ format = $format; systems = @($systems) } | ConvertTo-Json -Compress -Depth 10
