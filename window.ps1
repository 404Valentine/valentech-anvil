Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ROOT         = $PSScriptRoot
$STATE        = Join-Path $ROOT "state.json"
$PID_F        = Join-Path $ROOT "window.pid"
$SIM_ISSUES_F = Join-Path $ROOT "sim_issues.json"
$FEATURES_F   = Join-Path $ROOT "features.json"

$script:SW           = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width
$script:SH           = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height
$script:isFullscreen = $true
$script:simType      = 'waiting_pulse'
$script:simParams    = @{}
$script:simTick      = 0
$script:simIssues    = [System.Collections.Generic.List[string]]::new()

$script:currentNode        = ""
$script:currentTitle       = ""
$script:currentContent     = ""
$script:gddFileName        = ""
$script:lastGenerateTs     = 0
$script:pendingGenerateTs  = 0
$script:lastSyncDiffTs     = 0
$script:lastReimportDataTs = 0
$script:lastGddExportTs    = 0
$script:checkboxes         = [System.Collections.Generic.List[System.Windows.Forms.CheckBox]]::new()
$script:stateLastWrite     = [datetime]::MinValue
$script:nodeSelectedAt     = [datetime]::MinValue

$TREE_W = 320
$GAP    = 8

# ── Palette (Starlink-inspired: monochromatic black/white — system colors are the only hue) ──
$BG       = [System.Drawing.Color]::FromArgb(  0,   0,   0)
$PANEL_BG = [System.Drawing.Color]::FromArgb( 14,  14,  14)
$BAR_BG   = [System.Drawing.Color]::FromArgb( 10,  10,  10)
$CARD_BG  = [System.Drawing.Color]::FromArgb( 22,  22,  22)
$DIVIDER  = [System.Drawing.Color]::FromArgb( 32,  32,  32)
$TEXT_HI  = [System.Drawing.Color]::FromArgb(255, 255, 255)
$TEXT_DIM = [System.Drawing.Color]::FromArgb( 70,  70,  70)
$TEXT_MID = [System.Drawing.Color]::FromArgb(150, 150, 150)
$GREEN    = [System.Drawing.Color]::FromArgb(  0, 210,  80)
$AMBER    = [System.Drawing.Color]::FromArgb(220, 130,   0)
$RED_COL  = [System.Drawing.Color]::FromArgb(210,  30,  30)
# Sim-only colors
$MECH_COL = [System.Drawing.Color]::FromArgb(  0, 200, 255)
$SYS_COL  = [System.Drawing.Color]::FromArgb(180,   0, 255)
$LOOP_COL = [System.Drawing.Color]::FromArgb(  0, 255, 140)
$META_COL = [System.Drawing.Color]::FromArgb(255, 200,   0)

# Cached fonts for sim rendering — created once, disposed on form close
$script:fnt7B = New-Object System.Drawing.Font('Consolas', 7, [System.Drawing.FontStyle]::Bold)
$script:fnt7  = New-Object System.Drawing.Font('Consolas', 7)
$script:fnt8B = New-Object System.Drawing.Font('Consolas', 8, [System.Drawing.FontStyle]::Bold)
$script:fnt8  = New-Object System.Drawing.Font('Consolas', 8)
$script:fnt11 = New-Object System.Drawing.Font('Consolas', 11)

function Get-NodeColor([string]$t) {
    switch ($t) {
        'mechanic' { return $MECH_COL }
        'system'   { return $SYS_COL }
        'loop'     { return $LOOP_COL }
        'meta'     { return $META_COL }
        'concept'  { return [System.Drawing.Color]::FromArgb(255, 120, 80) }
        default    { return $TEXT_DIM }
    }
}

# ── Form ──────────────────────────────────────────────────────────────────────
$form = New-Object System.Windows.Forms.Form
$form.Text            = "ValenTech Anvil"
$form.BackColor       = $BG
$iconFile = Join-Path $ROOT "valentech.ico"
if (Test-Path $iconFile) { $form.Icon = New-Object System.Drawing.Icon($iconFile) }
$form.ForeColor       = $TEXT_HI
$form.FormBorderStyle = 'None'
$form.StartPosition   = 'Manual'
$form.Location        = New-Object System.Drawing.Point(0, 0)
$form.Size            = New-Object System.Drawing.Size($script:SW, $script:SH)
$form.MinimumSize     = New-Object System.Drawing.Size(900, 600)
$form.KeyPreview      = $true
Set-Content $PID_F $PID -NoNewline

function Toggle-Fullscreen {
    if ($script:isFullscreen) {
        $form.FormBorderStyle = 'Sizable'
        $form.Size     = New-Object System.Drawing.Size(1280, 800)
        $form.Location = New-Object System.Drawing.Point(
            [int](($script:SW - 1280) / 2), [int](($script:SH - 800) / 2))
        $script:isFullscreen = $false
    } else {
        $form.FormBorderStyle = 'None'
        $form.Location = New-Object System.Drawing.Point(0, 0)
        $form.Size     = New-Object System.Drawing.Size($script:SW, $script:SH)
        $script:isFullscreen = $true
    }
}

# ── Title bar ─────────────────────────────────────────────────────────────────
$titleBar = New-Object System.Windows.Forms.Panel
$titleBar.Dock      = 'Top'
$titleBar.Height    = 58
$titleBar.BackColor = $BAR_BG
$form.Controls.Add($titleBar)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Dock      = 'Fill'
$lblTitle.Text      = 'VALENTECH ANVIL'
$lblTitle.TextAlign = 'MiddleCenter'
$lblTitle.ForeColor = $TEXT_HI
$lblTitle.Font      = New-Object System.Drawing.Font('Consolas', 14, [System.Drawing.FontStyle]::Bold)
function Make-ChromeBtn([string]$text, [int]$x, [System.Drawing.Color]$hFg, [System.Drawing.Color]$hBg, [scriptblock]$onClick) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text; $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderSize = 0; $b.FlatAppearance.BorderColor = $BAR_BG
    $b.BackColor = $BAR_BG; $b.ForeColor = $TEXT_DIM
    $b.Font = New-Object System.Drawing.Font('Consolas', 10, [System.Drawing.FontStyle]::Bold)
    $b.Size = New-Object System.Drawing.Size(44, 44); $b.Location = New-Object System.Drawing.Point($x, 7)
    $b.Cursor = 'Hand'; $b.Add_Click($onClick)
    $hf = $hFg; $hbk = $hBg
    $b.Add_MouseEnter({ $b.ForeColor = $hf; $b.BackColor = $hbk }.GetNewClosure())
    $b.Add_MouseLeave({ $b.ForeColor = $TEXT_DIM; $b.BackColor = $BAR_BG }.GetNewClosure())
    $b
}

$btnMin   = Make-ChromeBtn '_' 0 $TEXT_HI ([System.Drawing.Color]::FromArgb(22,22,22)) { $form.WindowState = 'Minimized' }
$btnClose = Make-ChromeBtn 'X' 0 $RED_COL ([System.Drawing.Color]::FromArgb(40,10,10)) { $form.Close() }
$btnClose.Anchor = [System.Windows.Forms.AnchorStyles]'Top,Right'
$btnMin.Anchor   = [System.Windows.Forms.AnchorStyles]'Top,Right'

# SAVE and LOAD buttons in title bar (left side)
$btnSave = New-Object System.Windows.Forms.Button
$btnSave.Text = 'SAVE'; $btnSave.FlatStyle = 'Flat'
$btnSave.FlatAppearance.BorderSize = 1; $btnSave.FlatAppearance.BorderColor = $TEXT_MID
$btnSave.BackColor = [System.Drawing.Color]::FromArgb(28,28,28); $btnSave.ForeColor = $TEXT_HI
$btnSave.Font = New-Object System.Drawing.Font('Consolas', 8, [System.Drawing.FontStyle]::Bold)
$btnSave.Size = New-Object System.Drawing.Size(60, 30); $btnSave.Location = New-Object System.Drawing.Point(8, 14)
$btnSave.Cursor = 'Hand'; $btnSave.Add_Click({ Save-Project })

$btnLoad = New-Object System.Windows.Forms.Button
$btnLoad.Text = 'LOAD'; $btnLoad.FlatStyle = 'Flat'
$btnLoad.FlatAppearance.BorderSize = 1; $btnLoad.FlatAppearance.BorderColor = $TEXT_MID
$btnLoad.BackColor = [System.Drawing.Color]::FromArgb(28,28,28); $btnLoad.ForeColor = $TEXT_HI
$btnLoad.Font = New-Object System.Drawing.Font('Consolas', 8, [System.Drawing.FontStyle]::Bold)
$btnLoad.Size = New-Object System.Drawing.Size(60, 30); $btnLoad.Location = New-Object System.Drawing.Point(76, 14)
$btnLoad.Cursor = 'Hand'; $btnLoad.Add_Click({ Open-SavesPanel })

$btnSync = New-Object System.Windows.Forms.Button
$btnSync.Text = 'SYNC'; $btnSync.FlatStyle = 'Flat'
$btnSync.FlatAppearance.BorderSize = 1; $btnSync.FlatAppearance.BorderColor = $TEXT_DIM
$btnSync.BackColor = $BG; $btnSync.ForeColor = $TEXT_DIM
$btnSync.Font = New-Object System.Drawing.Font('Consolas', 8, [System.Drawing.FontStyle]::Bold)
$btnSync.Size = New-Object System.Drawing.Size(60, 30); $btnSync.Location = New-Object System.Drawing.Point(144, 14)
$btnSync.Cursor = 'Hand'

$btnImport = New-Object System.Windows.Forms.Button
$btnImport.Text = 'IMPORT'; $btnImport.FlatStyle = 'Flat'
$btnImport.FlatAppearance.BorderSize = 1; $btnImport.FlatAppearance.BorderColor = $TEXT_DIM
$btnImport.BackColor = $BG; $btnImport.ForeColor = $TEXT_DIM
$btnImport.Font = New-Object System.Drawing.Font('Consolas', 8, [System.Drawing.FontStyle]::Bold)
$btnImport.Size = New-Object System.Drawing.Size(60, 30); $btnImport.Location = New-Object System.Drawing.Point(212, 14)
$btnImport.Cursor = 'Hand'

# Add label LAST so it renders behind buttons (lower z-order = higher Controls index)
$titleBar.Controls.AddRange(@($btnMin, $btnClose, $btnSave, $btnLoad, $btnSync, $btnImport))
$titleBar.Controls.Add($lblTitle)
$titleBar.Add_Resize({
    $btnClose.Location = New-Object System.Drawing.Point(($titleBar.Width - 48), 7)
    $btnMin.Location   = New-Object System.Drawing.Point(($titleBar.Width - 96), 7)
})

# ── Accent line ───────────────────────────────────────────────────────────────
$accentLine = New-Object System.Windows.Forms.Panel
$accentLine.Dock      = 'Top'
$accentLine.Height    = 1
$accentLine.BackColor = $DIVIDER
$form.Controls.Add($accentLine)

# ── Button bar (docked bottom) ────────────────────────────────────────────────
$btnBar = New-Object System.Windows.Forms.Panel
$btnBar.Dock      = 'Bottom'
$btnBar.Height    = 88
$btnBar.BackColor = $BAR_BG
$form.Controls.Add($btnBar)

function Make-Btn([string]$text, [System.Drawing.Color]$fg, [int]$w=190, [int]$h=44) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.Font = New-Object System.Drawing.Font('Consolas', 10, [System.Drawing.FontStyle]::Bold)
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderSize  = 1
    $b.FlatAppearance.BorderColor = $fg
    $b.BackColor = [System.Drawing.Color]::FromArgb(255, [int]($fg.R/6), [int]($fg.G/6), [int]($fg.B/6))
    $b.ForeColor = $fg
    $b.Size    = New-Object System.Drawing.Size($w, $h)
    $b.Cursor  = 'Hand'
    $b.Enabled = $false
    $b
}

$btnConfirm    = Make-Btn 'CONFIRM'     $GREEN
$btnReroll     = Make-Btn 'REROLL'      $AMBER
$btnSimReport  = Make-Btn 'SIM REPORT'  $RED_COL 170 44
$btnUpdateDoc  = Make-Btn 'UPDATE DOC'  $TEXT_MID 150 44

# CHASSIS is the primary CTA — white fill, black text (Starlink "Get Started" style)
$btnChassis = New-Object System.Windows.Forms.Button
$btnChassis.Text = 'GENERATE'
$btnChassis.Font = New-Object System.Drawing.Font('Consolas', 10, [System.Drawing.FontStyle]::Bold)
$btnChassis.FlatStyle = 'Flat'
$btnChassis.FlatAppearance.BorderSize  = 0
$btnChassis.BackColor = $TEXT_HI
$btnChassis.ForeColor = $BG
$btnChassis.Size      = New-Object System.Drawing.Size(170, 44)
$btnChassis.Cursor    = 'Hand'
$btnChassis.Enabled   = $false
$btnConfirm.Location   = New-Object System.Drawing.Point( 24, 14)
$btnReroll.Location    = New-Object System.Drawing.Point(230, 14)
$btnSimReport.Location = New-Object System.Drawing.Point(436, 14)
$btnUpdateDoc.Location = New-Object System.Drawing.Point(622, 14)
$btnChassis.Location   = New-Object System.Drawing.Point(802, 14)
$btnBar.Controls.AddRange(@($btnConfirm, $btnReroll, $btnSimReport, $btnUpdateDoc, $btnChassis))

$legendL = New-Object System.Windows.Forms.Label
$legendL.Text      = 'Right-click to edit/delete  |  F11  ESC'
$legendL.Font      = New-Object System.Drawing.Font('Consolas', 8)
$legendL.ForeColor = $TEXT_DIM
$legendL.AutoSize  = $true
$legendL.Anchor   = [System.Windows.Forms.AnchorStyles]'Right,Top'
$legendL.Location = New-Object System.Drawing.Point(1180, 64)
$btnBar.Controls.Add($legendL)

# ── Body (fills between title and button bar) ─────────────────────────────────
$body = New-Object System.Windows.Forms.Panel
$body.Dock      = 'Fill'
$body.BackColor = $BG
$form.Controls.Add($body)

# ── Left panel ────────────────────────────────────────────────────────────────
$treeOuter = New-Object System.Windows.Forms.Panel
$treeOuter.BackColor = $PANEL_BG
$body.Controls.Add($treeOuter)

$treeTitleL = New-Object System.Windows.Forms.Label
$treeTitleL.Text      = 'CONCEPT TREE'
$treeTitleL.Font      = New-Object System.Drawing.Font('Consolas', 9, [System.Drawing.FontStyle]::Bold)
$treeTitleL.ForeColor = $TEXT_MID
$treeTitleL.SetBounds(10, 8, $TREE_W - 20, 16)
$treeOuter.Controls.Add($treeTitleL)

$fileLabel = New-Object System.Windows.Forms.Label
$fileLabel.Text      = 'No file selected'
$fileLabel.Font      = New-Object System.Drawing.Font('Consolas', 8)
$fileLabel.ForeColor = $TEXT_DIM
$fileLabel.SetBounds(10, 28, $TREE_W - 20, 30)
$treeOuter.Controls.Add($fileLabel)

$browseBtn = New-Object System.Windows.Forms.Button
$browseBtn.Text = 'BROWSE FILE'
$browseBtn.Font = New-Object System.Drawing.Font('Consolas', 9, [System.Drawing.FontStyle]::Bold)
$browseBtn.FlatStyle = 'Flat'
$browseBtn.FlatAppearance.BorderSize  = 1
$browseBtn.FlatAppearance.BorderColor = $TEXT_MID
$browseBtn.BackColor = $BG
$browseBtn.ForeColor = $TEXT_HI
$browseBtn.Cursor    = 'Hand'
$browseBtn.SetBounds(10, 62, $TREE_W - 20, 28)
$treeOuter.Controls.Add($browseBtn)

# COLOR GUIDE button — full width, clearly visible
$colorGuideBtn = New-Object System.Windows.Forms.Button
$colorGuideBtn.Text = 'COLOR GUIDE'
$colorGuideBtn.Font = New-Object System.Drawing.Font('Consolas', 8, [System.Drawing.FontStyle]::Bold)
$colorGuideBtn.FlatStyle = 'Flat'
$colorGuideBtn.FlatAppearance.BorderSize  = 1
$colorGuideBtn.FlatAppearance.BorderColor = $TEXT_DIM
$colorGuideBtn.BackColor = $BG
$colorGuideBtn.ForeColor = $TEXT_MID
$colorGuideBtn.Cursor    = 'Hand'
$colorGuideBtn.SetBounds(10, 94, $TREE_W - 20, 22)
$treeOuter.Controls.Add($colorGuideBtn)

$colorGuideBtn.Add_Click({
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'Color Guide'; $dlg.Size = New-Object System.Drawing.Size(280, 300)
    $dlg.BackColor = $PANEL_BG; $dlg.ForeColor = $TEXT_HI
    $dlg.FormBorderStyle = 'FixedToolWindow'; $dlg.StartPosition = 'CenterParent'
    $dlg.TopMost = $true
    $cats = @(
        @{l='Combat / Catching';   c=[System.Drawing.Color]::FromArgb(230, 50,  50)},
        @{l='Economy / Trading';   c=[System.Drawing.Color]::FromArgb(220,140,   0)},
        @{l='Progression';         c=[System.Drawing.Color]::FromArgb(220,190,   0)},
        @{l='Plant Systems';       c=[System.Drawing.Color]::FromArgb( 40,200,  80)},
        @{l='Animal + Plant';      c=[System.Drawing.Color]::FromArgb(  0,200, 180)},
        @{l='Exploration / World'; c=[System.Drawing.Color]::FromArgb(  0,200, 230)},
        @{l='Animal / Creature';   c=[System.Drawing.Color]::FromArgb( 60,140, 255)},
        @{l='Social / Community';  c=[System.Drawing.Color]::FromArgb(170, 80, 230)},
        @{l='Building / Mgmt';     c=[System.Drawing.Color]::FromArgb(130,155, 175)},
        @{l='UI / Camera';         c=[System.Drawing.Color]::FromArgb(190,190, 200)},
        @{l='General';             c=[System.Drawing.Color]::FromArgb(160,165, 172)}
    )
    $y = 10
    foreach ($cat in $cats) {
        $sw = New-Object System.Windows.Forms.Panel
        $sw.SetBounds(10, $y+3, 14, 14); $sw.BackColor = $cat.c; $dlg.Controls.Add($sw)
        $lb = New-Object System.Windows.Forms.Label
        $lb.Text = $cat.l; $lb.Font = New-Object System.Drawing.Font('Consolas',9)
        $lb.ForeColor = $cat.c; $lb.SetBounds(32, $y, 220, 20); $dlg.Controls.Add($lb)
        $y += 22
    }
    $dlg.ShowDialog() | Out-Null; $dlg.Dispose()
})

$divL = New-Object System.Windows.Forms.Panel
$divL.SetBounds(0, 120, $TREE_W, 1)
$divL.BackColor = $DIVIDER
$treeOuter.Controls.Add($divL)

$nodeScroll = New-Object System.Windows.Forms.Panel
$nodeScroll.AutoScroll = $true
$nodeScroll.BackColor  = $PANEL_BG
$treeOuter.Controls.Add($nodeScroll)
$script:nodeScrollTop = 122

$nodeFlow = New-Object System.Windows.Forms.FlowLayoutPanel
$nodeFlow.FlowDirection = 'TopDown'
$nodeFlow.WrapContents  = $false
$nodeFlow.AutoSize      = $true
$nodeFlow.Width         = $TREE_W - 12
$nodeScroll.Controls.Add($nodeFlow)

# ── Right: canvas + description ───────────────────────────────────────────────
$canvas = New-Object System.Windows.Forms.PictureBox
$canvas.BackColor = $BG
$canvas.SizeMode  = 'Normal'
$body.Controls.Add($canvas)


# Proposal panel replaces plain descBox — shows title, checkboxes, description
$proposalPanel = New-Object System.Windows.Forms.Panel
$proposalPanel.BackColor  = $CARD_BG
$body.Controls.Add($proposalPanel)

$propTitleL = New-Object System.Windows.Forms.Label
$propTitleL.Text      = ''
$propTitleL.Font      = New-Object System.Drawing.Font('Consolas', 11, [System.Drawing.FontStyle]::Bold)
$propTitleL.ForeColor = $TEXT_HI
$propTitleL.AutoSize  = $false
$propTitleL.SetBounds(12, 10, 800, 22)
$proposalPanel.Controls.Add($propTitleL)

$propDescL = New-Object System.Windows.Forms.Label
$propDescL.Text      = 'Select a system node to begin.'
$propDescL.Font      = New-Object System.Drawing.Font('Consolas', 9)
$propDescL.ForeColor = $TEXT_MID
$propDescL.AutoSize  = $false
$propDescL.SetBounds(12, 36, 800, 70)
$proposalPanel.Controls.Add($propDescL)

# Divider between description and checklist
$checkDivider = New-Object System.Windows.Forms.Panel
$checkDivider.BackColor = $DIVIDER
$checkDivider.SetBounds(12, 110, 800, 1)
$proposalPanel.Controls.Add($checkDivider)

# Outer panel — fixed height, scrolls vertically
$checkOuter = New-Object System.Windows.Forms.Panel
$checkOuter.BackColor  = $CARD_BG
$checkOuter.AutoScroll = $true
$checkOuter.SetBounds(12, 115, 800, 130)
$proposalPanel.Controls.Add($checkOuter)

# Inner panel — grows with checkboxes, never scrolls itself
$checkPanel = New-Object System.Windows.Forms.Panel
$checkPanel.BackColor  = $CARD_BG
$checkPanel.AutoScroll = $false
$checkPanel.SetBounds(0, 0, 780, 0)
$checkOuter.Controls.Add($checkPanel)

# "More" indicator — shown when checklist overflows
$moreLabel = New-Object System.Windows.Forms.Label
$moreLabel.Text      = 'v  scroll for more'
$moreLabel.Font      = New-Object System.Drawing.Font('Consolas', 8)
$moreLabel.ForeColor = [System.Drawing.Color]::FromArgb(80, 80, 80)
$moreLabel.AutoSize  = $false
$moreLabel.TextAlign = 'MiddleCenter'
$moreLabel.SetBounds(12, 247, 800, 16)
$moreLabel.Visible   = $false
$proposalPanel.Controls.Add($moreLabel)

# Keep a stub descBox reference so existing code that sets .Text still works
$descBox = $propDescL

# ── Relayout ──────────────────────────────────────────────────────────────────
function Relayout {
    $W = $body.ClientSize.Width
    $H = $body.ClientSize.Height
    $RIGHT_X  = $TREE_W + $GAP * 2
    $RIGHT_W  = $W - $RIGHT_X - $GAP
    $CANVAS_H = [int]($H * 0.618)
    $DESC_H   = $H - $CANVAS_H - $GAP

    $treeOuter.SetBounds(0, 0, $TREE_W, $H)
    $nodeScroll.SetBounds(0, $script:nodeScrollTop, $TREE_W, $H - $script:nodeScrollTop)
    $nodeFlow.Width = $TREE_W - 12

    $canvas.SetBounds($RIGHT_X, $GAP, $RIGHT_W, $CANVAS_H)
    $proposalPanel.SetBounds($RIGHT_X, ($CANVAS_H + $GAP * 2), $RIGHT_W, $DESC_H)
    $propTitleL.Width    = $RIGHT_W - 24
    $propDescL.Width     = $RIGHT_W - 24
    $propDescL.Height    = 70
    $checkDivider.Width  = $RIGHT_W - 24
    $checkOuter.Width    = $RIGHT_W - 24
    $checkOuter.Top      = 115
    $checkOuter.Height   = 130
    $checkPanel.Width    = $RIGHT_W - 44
    $moreLabel.Width     = $RIGHT_W - 24
    $moreLabel.Top       = $checkOuter.Top + $checkOuter.Height + 2
}

$body.Add_Resize({ Relayout })

# ── Keyboard ──────────────────────────────────────────────────────────────────
$form.Add_KeyDown({
    if ($_.KeyCode -eq 'Escape') { Write-Response "deny"; Set-Buttons-Idle; $form.Close() }
    elseif ($_.Alt -and $_.KeyCode -eq 'F4') { $form.Close() }
    if ($_.KeyCode -eq 'F11') { Toggle-Fullscreen; $_.SuppressKeyPress = $true }
})

# ── State helpers ─────────────────────────────────────────────────────────────
function Read-State {
    # Returns a PSCustomObject or $null. Handles concurrent writes gracefully.
    $raw = Get-Content $STATE -Raw -ErrorAction SilentlyContinue
    if (-not $raw -or $raw.Trim() -eq '') { return $null }
    try { return $raw | ConvertFrom-Json } catch { return $null }
}

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

function Write-StateFields([hashtable]$fields) {
    $obj = Read-State; if (-not $obj) { return }
    foreach ($k in $fields.Keys) { $obj.$k = $fields[$k] }
    Write-Atomic $STATE ($obj | ConvertTo-Json -Compress -Depth 10)
}

function Write-Response([string]$val) {
    Write-StateFields @{ response = $val }
}

function Save-SimIssues {
    if ($script:simIssues.Count -eq 0) { return }
    $script:simIssues | ConvertTo-Json -Compress | Set-Content $SIM_ISSUES_F -NoNewline
}

function Update-ChassisButton {
    $btnChassis.Enabled = [bool]($script:sections | Where-Object { $_.features.Count -gt 0 })
}

function Update-DocButton {
    $btnUpdateDoc.Enabled = [bool]($script:sections | Where-Object { $_.features.Count -gt 0 })
}

function Set-Buttons-Waiting {
    $btnConfirm.Enabled   = $true
    $btnReroll.Enabled    = $true
    $btnSimReport.Enabled = ($script:simType -ne 'waiting_pulse')
}
function Set-Buttons-Idle {
    $btnConfirm.Enabled   = $false
    $btnReroll.Enabled    = $false
    $btnSimReport.Enabled = $false
}

# ── Button handlers ───────────────────────────────────────────────────────────
$btnConfirm.Add_Click({
    Write-Response "confirm"
    Set-Buttons-Idle

    # Save checked components as individual features, or whole proposal if no checklist
    $sec = $script:sections | Where-Object { $_.id -eq $script:currentNode } | Select-Object -First 1
    if ($sec -and $script:currentTitle) {
        if ($script:checkboxes.Count -gt 0) {
            $checkedItems = $script:checkboxes | Where-Object { $_.Checked }
            # Load component metadata so we can store Unity construct info per feature
            $cdRaw   = Get-Content $STATE -Raw -ErrorAction SilentlyContinue
            $cdObj   = try { $cdRaw | ConvertFrom-Json } catch { $null }
            $compData = if ($cdObj -and $cdObj.component_data) { @($cdObj.component_data) } else { @() }
            foreach ($cb in $checkedItems) {
                $fid  = [System.Guid]::NewGuid().ToString('N').Substring(0, 8)
                $idx  = if ($null -ne $cb.Tag) { [int]$cb.Tag } else { -1 }
                $meta = if ($idx -ge 0 -and $compData.Count -gt $idx) { $compData[$idx] } else { $null }
                $sec.features.Add(@{
                    id             = $fid
                    label          = $cb.Text
                    desc           = $script:currentContent
                    sectionId      = $sec.id
                    unityConstruct = if ($meta -and $meta.construct) { [string]$meta.construct } else { '' }
                    dataFields     = if ($meta -and $meta.fields)    { $meta.fields }            else { @() }
                    dependencies   = if ($meta -and $meta.deps)      { $meta.deps }              else { @() }
                })
            }
        } else {
            $fid = [System.Guid]::NewGuid().ToString('N').Substring(0, 8)
            $sec.features.Add(@{ id=$fid; label=$script:currentTitle; desc=$script:currentContent; sectionId=$sec.id; unityConstruct=''; dataFields=@(); dependencies=@() })
        }
        Save-Features; Rebuild-NodeList; Update-ChassisButton; Update-DocButton
    }
})
$btnReroll.Add_Click({
    Write-Response "reroll"
    $propTitleL.Text = "Generating..."
    $propDescL.Text  = ""
    $checkPanel.Controls.Clear()
    $script:checkboxes.Clear()
    Start-SimType 'waiting_pulse' @{}
    Set-Buttons-Idle
})
$btnSimReport.Add_Click({
    $script:simIssues.Add("sim=$($script:simType) node=$($script:currentNode) title=$($script:currentTitle)")
    Save-SimIssues
    Write-StateFields @{ sim_issues_ts = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() }
    $btnSimReport.Enabled = $false
    [System.Windows.Forms.MessageBox]::Show("Sim issue logged.", "ValenTech", 'OK', 'Information') | Out-Null
})

$btnUpdateDoc.Add_Click({
    $sfd = New-Object System.Windows.Forms.SaveFileDialog
    $sfd.Title  = "Save Refined GDD"
    $sfd.Filter = "Markdown (*.md)|*.md|Text (*.txt)|*.txt|All Files (*.*)|*.*"
    $gddDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "GDDs"
    $sfd.InitialDirectory = if (Test-Path $gddDir) { $gddDir } else { [Environment]::GetFolderPath('MyDocuments') }
    $baseName = if ($script:gddFileName) { $script:gddFileName } else { "GDD" }
    $sfd.FileName = "$baseName - Refined.md"
    if ($sfd.ShowDialog() -eq 'OK') {
        $btnUpdateDoc.Enabled = $false
        $btnUpdateDoc.Text = 'UPDATING...'
        $form.Refresh()
        $result = & (Join-Path $ROOT "update_document.ps1") -OutputPath $sfd.FileName
        $btnUpdateDoc.Text = 'UPDATE DOC'
        Update-DocButton
        if ($result -like 'done*') {
            [System.Windows.Forms.MessageBox]::Show(
                "Refined GDD saved to:`n$($sfd.FileName)`n`nOpening now...", "ValenTech", 'OK', 'Information') | Out-Null
            try { Start-Process $sfd.FileName } catch {}
        } else {
            [System.Windows.Forms.MessageBox]::Show(
                "Could not update document.`n$result", "ValenTech", 'OK', 'Warning') | Out-Null
        }
    }
})

$btnChassis.Add_Click({
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'Generate Unity Chassis'; $dlg.Size = New-Object System.Drawing.Size(420, 250)
    $dlg.BackColor = $PANEL_BG; $dlg.ForeColor = $TEXT_HI
    $dlg.FormBorderStyle = 'FixedToolWindow'; $dlg.StartPosition = 'CenterParent'
    $dlg.TopMost = $true

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = 'Output format:'
    $lbl.Font = New-Object System.Drawing.Font('Consolas', 9, [System.Drawing.FontStyle]::Bold)
    $lbl.ForeColor = $TEXT_MID
    $lbl.SetBounds(14, 14, 380, 18)
    $dlg.Controls.Add($lbl)

    $rbScaffold = New-Object System.Windows.Forms.RadioButton
    $rbScaffold.Text = 'Unity project scaffold (Assets/Scripts/<System>/ + .asmdef)'
    $rbScaffold.Font = New-Object System.Drawing.Font('Consolas', 9)
    $rbScaffold.ForeColor = $TEXT_HI
    $rbScaffold.Checked = $true
    $rbScaffold.SetBounds(14, 36, 380, 22)
    $dlg.Controls.Add($rbScaffold)

    $rbFlat = New-Object System.Windows.Forms.RadioButton
    $rbFlat.Text = 'Flat folder (.cs files only)'
    $rbFlat.Font = New-Object System.Drawing.Font('Consolas', 9)
    $rbFlat.ForeColor = $TEXT_HI
    $rbFlat.SetBounds(14, 60, 380, 22)
    $dlg.Controls.Add($rbFlat)

    $div = New-Object System.Windows.Forms.Panel
    $div.BackColor = $DIVIDER
    $div.SetBounds(14, 92, 380, 1)
    $dlg.Controls.Add($div)

    $pathLabel = New-Object System.Windows.Forms.Label
    $pathLabel.Text = 'No folder selected'
    $pathLabel.Font = New-Object System.Drawing.Font('Consolas', 8)
    $pathLabel.ForeColor = $TEXT_DIM
    $pathLabel.AutoEllipsis = $true
    $pathLabel.SetBounds(14, 104, 380, 18)
    $dlg.Controls.Add($pathLabel)

    $chooseBtn = New-Object System.Windows.Forms.Button
    $chooseBtn.Text = 'CHOOSE FOLDER...'
    $chooseBtn.Font = New-Object System.Drawing.Font('Consolas', 9, [System.Drawing.FontStyle]::Bold)
    $chooseBtn.FlatStyle = 'Flat'
    $chooseBtn.FlatAppearance.BorderSize  = 1
    $chooseBtn.FlatAppearance.BorderColor = $TEXT_MID
    $chooseBtn.BackColor = $BG
    $chooseBtn.ForeColor = $TEXT_HI
    $chooseBtn.Cursor    = 'Hand'
    $chooseBtn.SetBounds(14, 128, 150, 30)
    $dlg.Controls.Add($chooseBtn)

    $script:chassisFolder = ''
    $chooseBtn.Add_Click({
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fbd.Description = "Select the output folder for the generated chassis"
        if ($fbd.ShowDialog() -eq 'OK') {
            $script:chassisFolder = $fbd.SelectedPath
            $pathLabel.Text = $script:chassisFolder
            $pathLabel.ForeColor = $TEXT_MID
        }
    })

    $okBtn = New-Object System.Windows.Forms.Button
    $okBtn.Text = 'GENERATE'
    $okBtn.Font = New-Object System.Drawing.Font('Consolas', 10, [System.Drawing.FontStyle]::Bold)
    $okBtn.FlatStyle = 'Flat'
    $okBtn.FlatAppearance.BorderSize = 0
    $okBtn.BackColor = $TEXT_HI
    $okBtn.ForeColor = $BG
    $okBtn.Cursor    = 'Hand'
    $okBtn.SetBounds(14, 174, 150, 36)
    $okBtn.DialogResult = 'OK'
    $dlg.Controls.Add($okBtn)

    $cancelBtn = New-Object System.Windows.Forms.Button
    $cancelBtn.Text = 'CANCEL'
    $cancelBtn.Font = New-Object System.Drawing.Font('Consolas', 10, [System.Drawing.FontStyle]::Bold)
    $cancelBtn.FlatStyle = 'Flat'
    $cancelBtn.FlatAppearance.BorderSize  = 1
    $cancelBtn.FlatAppearance.BorderColor = $TEXT_MID
    $cancelBtn.BackColor = $BG
    $cancelBtn.ForeColor = $TEXT_MID
    $cancelBtn.Cursor    = 'Hand'
    $cancelBtn.SetBounds(180, 174, 110, 36)
    $cancelBtn.DialogResult = 'Cancel'
    $dlg.Controls.Add($cancelBtn)

    $dlg.AcceptButton = $okBtn
    $dlg.CancelButton = $cancelBtn

    $result = $dlg.ShowDialog()
    if ($result -eq 'OK' -and $script:chassisFolder) {
        $format = if ($rbFlat.Checked) { 'flat' } else { 'scaffold' }
        $btnChassis.Enabled = $false
        $btnChassis.Text = 'GENERATING...'
        $descBox.Text = "Generating Unity chassis ($format)...`n`nThis may take a moment."
        $ts = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        $script:pendingGenerateTs = $ts
        Write-StateFields @{
            generate_ts         = $ts
            chassis_format      = $format
            chassis_output_path = $script:chassisFolder
            chassis_path        = ''
        }
    } elseif ($result -eq 'OK' -and -not $script:chassisFolder) {
        [System.Windows.Forms.MessageBox]::Show(
            "No output folder was selected - nothing was generated.`n`nClick GENERATE again and choose a folder first.",
            "ValenTech", 'OK', 'Warning') | Out-Null
    }
    $dlg.Dispose()
})

$btnSync.Add_Click({
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fbd.Description = "Select the Unity project folder to sync against your spec"
    if ($fbd.ShowDialog() -eq 'OK') {
        $ts = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        Write-StateFields @{ sync_path = $fbd.SelectedPath; sync_ts = $ts; sync_diff_ts = 0 }
        $descBox.ForeColor = $TEXT_MID
        $descBox.Text = "Sync requested.`n`nClaude is scanning the Unity project for differences..."
    }
})

$btnImport.Add_Click({
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fbd.Description = "Select the Unity project folder to reconstruct spec from"
    if ($fbd.ShowDialog() -eq 'OK') {
        $ts = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        Write-StateFields @{ reimport_path = $fbd.SelectedPath; reimport_ts = $ts; reimport_data_ts = 0 }
        $descBox.ForeColor = $TEXT_MID
        $descBox.Text = "Import requested.`n`nClaude is reconstructing your spec from the Unity project..."
    }
})

# ── File browser ──────────────────────────────────────────────────────────────
function Read-GDDFile([string]$path) {
    $ext = [System.IO.Path]::GetExtension($path).ToLower()
    if ($ext -eq '.pdf') {
        $cmd = Get-Command pdftotext -ErrorAction SilentlyContinue
        $pdftotext = if ($cmd) { $cmd.Source } else { "C:\Program Files\Git\mingw64\bin\pdftotext.exe" }
        if (-not (Test-Path $pdftotext)) { throw "pdftotext not found. Install Poppler or save the GDD as .txt first." }
        $tmp = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), [System.Guid]::NewGuid().ToString('N') + '.txt')
        try {
            & $pdftotext $path $tmp 2>$null
            if (-not (Test-Path $tmp)) { throw "PDF extraction failed." }
            $sr = [System.IO.StreamReader]::new($tmp, [System.Text.Encoding]::UTF8, $true)
            try { $extracted = $sr.ReadToEnd() } finally { $sr.Dispose() }
            if ($extracted.Trim().Length -lt 200) { throw "PDF appears to be image-based or empty. Save as .txt first." }
            return $extracted
        } finally {
            if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
        }
    }
    $sr = [System.IO.StreamReader]::new($path, [System.Text.Encoding]::UTF8, $true)
    try { return $sr.ReadToEnd() } finally { $sr.Dispose() }
}

$browseBtn.Add_Click({
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Title  = "Select GDD File"
    $ofd.Filter = "All GDD Files (*.pdf;*.txt;*.md;*.markdown)|*.pdf;*.txt;*.md;*.markdown|PDF (*.pdf)|*.pdf|Text & Markdown (*.txt;*.md)|*.txt;*.md|All Files (*.*)|*.*"
    $gddDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "GDDs"
    $ofd.InitialDirectory = if (Test-Path $gddDir) { $gddDir } else { [Environment]::GetFolderPath('MyDocuments') }
    if ($ofd.ShowDialog() -eq 'OK') {
        $path = $ofd.FileName
        $shortName = [System.IO.Path]::GetFileName($path)
        $script:gddFileName = [System.IO.Path]::GetFileNameWithoutExtension($path)
        $fileLabel.Text = $shortName
        $fileLabel.ForeColor = $AMBER
        $descBox.Text = "Reading $shortName..."
        $form.Refresh()
        try {
            $text = Read-GDDFile $path
            $fileLabel.ForeColor = $TEXT_MID
            Parse-GDD $text
            $descBox.Text = "Loaded: $shortName`n`nSelect a concept node to begin expanding."
        } catch {
            $fileLabel.ForeColor = $RED_COL
            [System.Windows.Forms.MessageBox]::Show("Could not read file.`n$_", "ValenTech") | Out-Null
        }
    }
})

# ── Semantic category colors ──────────────────────────────────────────────────
function Get-SystemCategory([string]$name) {
    $n = $name.ToLower()
    # Animal/creature — broad net for genetics, traits, behaviour, breeding
    $isAnimal = $n -match 'creature|animal|beast|pet|species|breed|hatch|tame|fauna|wildlife|morpholog|genetic|trait|dominan|behav|legendary|bond build|bond breed|dna|allel|phenotyp|genotyp'
    # Plant/flora — broad net for vegetation, foraging, ecology
    $isPlant  = $n -match 'plant|flora|herb|tree|flower|crop|garden|harvest|seed|grow|forest|botanc|cultivat|forag|vegetation|shrub|leaf|root|soil|ecology|ecosystem|wild.food|gather'
    if ($isAnimal -and $isPlant) { return 'both' }
    if ($isAnimal) { return 'animal' }
    if ($isPlant)  { return 'plant' }
    # Combat/catching — also covers abilities and skills
    if ($n -match 'combat|battle|fight|attack|defend|catch|capture|hunt|trap|weapon|abilit|skill|pvp') { return 'combat' }
    # Economy/trading — 'trad' covers trade/trading/trader
    if ($n -match 'trad|economy|market|shop|sell|buy|currenc|coin|resource|craft|exchange|monetis|monetiz|price|auction|merchant') { return 'economy' }
    # Building/management — 'facilit' covers facility/facilities
    if ($n -match 'build|ranch|terrarium|construct|upgrade|facilit|pen|enclosure|base|farm|place|habitat|management') { return 'building' }
    # Social/community — 'event' covers community/seasonal events
    if ($n -match 'bond|social|relation|friend|npc|reputation|trust|affin|interact|communit|event|co.op|guild|party|multiplay') { return 'social' }
    # Progression/collection
    if ($n -match 'progress|level|xp|experience|unlock|advance|tier|rank|milestone|season|compendium|collect|reward|achiev') { return 'progress' }
    # Exploration/world
    if ($n -match 'explor|world|map|region|travel|discover|terrain|zone|area|expedition|navigat|roam|biome') { return 'explore' }
    # UI/camera/settings
    if ($n -match 'ui|interface|menu|hud|display|camera|control|input|setting|accessib|person|view|perspect') { return 'ui' }
    return 'default'
}

function Get-CategoryColor([string]$category) {
    switch ($category) {
        'animal'   { return [System.Drawing.Color]::FromArgb( 60, 140, 255) }  # Blue
        'plant'    { return [System.Drawing.Color]::FromArgb( 40, 200,  80) }  # Green
        'both'     { return [System.Drawing.Color]::FromArgb(  0, 200, 180) }  # Teal
        'combat'   { return [System.Drawing.Color]::FromArgb(230,  50,  50) }  # Red
        'economy'  { return [System.Drawing.Color]::FromArgb(220, 140,   0) }  # Orange
        'building' { return [System.Drawing.Color]::FromArgb(130, 155, 175) }  # Steel blue-grey
        'social'   { return [System.Drawing.Color]::FromArgb(170,  80, 230) }  # Purple
        'progress' { return [System.Drawing.Color]::FromArgb(220, 190,   0) }  # Gold
        'explore'  { return [System.Drawing.Color]::FromArgb(  0, 200, 230) }  # Cyan
        'ui'       { return [System.Drawing.Color]::FromArgb(190, 190, 200) }  # Light grey
        default    { return [System.Drawing.Color]::FromArgb(160, 165, 172) }  # Visible neutral grey
    }
}

# ── Sync diff modal ───────────────────────────────────────────────────────────
function Show-SyncDiffModal($diffObj, [string]$syncedPath) {
    $changes = @($diffObj.changes)
    if (-not $changes -or $changes.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "No differences found - your spec matches the Unity project.",
            "ValenTech SYNC", 'OK', 'Information') | Out-Null
        return
    }

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'SYNC - UNITY DIFF'
    $dlg.Size = New-Object System.Drawing.Size(660, 540)
    $dlg.BackColor = $PANEL_BG; $dlg.ForeColor = $TEXT_HI
    $dlg.FormBorderStyle = 'FixedDialog'; $dlg.StartPosition = 'CenterParent'
    $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false; $dlg.TopMost = $true

    $pathL = New-Object System.Windows.Forms.Label
    $pathL.Text = if ($syncedPath) { [System.IO.Path]::GetFileName($syncedPath) } else { 'Unknown path' }
    $pathL.Font = New-Object System.Drawing.Font('Consolas', 8)
    $pathL.ForeColor = $TEXT_DIM; $pathL.AutoEllipsis = $true
    $pathL.SetBounds(10, 10, 500, 18); $dlg.Controls.Add($pathL)

    $countL = New-Object System.Windows.Forms.Label
    $countL.Text = "$($changes.Count) change$(if ($changes.Count -ne 1) { 's' })"
    $countL.Font = New-Object System.Drawing.Font('Consolas', 9, [System.Drawing.FontStyle]::Bold)
    $countL.ForeColor = $AMBER; $countL.SetBounds(530, 8, 110, 20); $dlg.Controls.Add($countL)

    $instrL = New-Object System.Windows.Forms.Label
    $instrL.Text = 'Check items to accept into your spec, then click APPLY.'
    $instrL.Font = New-Object System.Drawing.Font('Consolas', 8)
    $instrL.ForeColor = $TEXT_MID; $instrL.SetBounds(10, 30, 630, 16); $dlg.Controls.Add($instrL)

    $div1 = New-Object System.Windows.Forms.Panel
    $div1.SetBounds(10, 50, 622, 1); $div1.BackColor = $DIVIDER; $dlg.Controls.Add($div1)

    $listPanel = New-Object System.Windows.Forms.Panel
    $listPanel.BackColor = $CARD_BG; $listPanel.AutoScroll = $true
    $listPanel.SetBounds(10, 56, 622, 260); $dlg.Controls.Add($listPanel)

    $detailPanel = New-Object System.Windows.Forms.Panel
    $detailPanel.BackColor = [System.Drawing.Color]::FromArgb(18, 18, 18)
    $detailPanel.SetBounds(10, 322, 622, 110); $dlg.Controls.Add($detailPanel)

    $detailL = New-Object System.Windows.Forms.Label
    $detailL.Text = 'Click a row to see details.'
    $detailL.Font = New-Object System.Drawing.Font('Consolas', 8)
    $detailL.ForeColor = $TEXT_DIM; $detailL.AutoSize = $false
    $detailL.SetBounds(8, 4, 606, 102); $detailPanel.Controls.Add($detailL)

    $div2 = New-Object System.Windows.Forms.Panel
    $div2.SetBounds(10, 438, 622, 1); $div2.BackColor = $DIVIDER; $dlg.Controls.Add($div2)

    $applyBtn = New-Object System.Windows.Forms.Button
    $applyBtn.Text = 'APPLY SELECTED'
    $applyBtn.Font = New-Object System.Drawing.Font('Consolas', 9, [System.Drawing.FontStyle]::Bold)
    $applyBtn.FlatStyle = 'Flat'; $applyBtn.FlatAppearance.BorderSize = 0
    $applyBtn.BackColor = $TEXT_HI; $applyBtn.ForeColor = $BG; $applyBtn.Cursor = 'Hand'
    $applyBtn.SetBounds(10, 448, 160, 34); $applyBtn.DialogResult = 'OK'; $dlg.Controls.Add($applyBtn)

    $cancelBtn = New-Object System.Windows.Forms.Button
    $cancelBtn.Text = 'CANCEL'
    $cancelBtn.Font = New-Object System.Drawing.Font('Consolas', 9, [System.Drawing.FontStyle]::Bold)
    $cancelBtn.FlatStyle = 'Flat'; $cancelBtn.FlatAppearance.BorderSize = 1
    $cancelBtn.FlatAppearance.BorderColor = $TEXT_MID
    $cancelBtn.BackColor = $BG; $cancelBtn.ForeColor = $TEXT_MID; $cancelBtn.Cursor = 'Hand'
    $cancelBtn.SetBounds(188, 448, 100, 34); $cancelBtn.DialogResult = 'Cancel'; $dlg.Controls.Add($cancelBtn)
    $dlg.AcceptButton = $applyBtn; $dlg.CancelButton = $cancelBtn

    $cy = 4
    foreach ($ch in $changes) {
        $sc = [string]$ch.status
        $statusColor = switch ($sc) {
            'new_in_unity'      { $GREEN }
            'fields_changed'    { $AMBER }
            'construct_changed' { $AMBER }
            'missing_in_unity'  { $RED_COL }
            default             { $TEXT_MID }
        }
        $statusIcon = switch ($sc) {
            'new_in_unity'      { '+' }
            'fields_changed'    { '~' }
            'construct_changed' { '!' }
            'missing_in_unity'  { '-' }
            default             { '?' }
        }
        $statusText = switch ($sc) {
            'new_in_unity'      { 'new in Unity' }
            'fields_changed'    { 'fields changed' }
            'construct_changed' { 'construct changed' }
            'missing_in_unity'  { 'missing in Unity' }
            default             { $sc }
        }

        $cb = New-Object System.Windows.Forms.CheckBox
        $cb.Tag = $ch; $cb.Checked = ($sc -ne 'missing_in_unity')
        $cb.SetBounds(4, ($cy + 2), 18, 18); $listPanel.Controls.Add($cb)

        $iconL = New-Object System.Windows.Forms.Label
        $iconL.Text = $statusIcon
        $iconL.Font = New-Object System.Drawing.Font('Consolas', 9, [System.Drawing.FontStyle]::Bold)
        $iconL.ForeColor = $statusColor; $iconL.SetBounds(26, ($cy + 1), 16, 20); $listPanel.Controls.Add($iconL)

        $rowL = New-Object System.Windows.Forms.Label
        $rowL.Text = "$([string]$ch.system)  /  $([string]$ch.className)"
        $rowL.Font = New-Object System.Drawing.Font('Consolas', 9)
        $rowL.ForeColor = $TEXT_HI; $rowL.SetBounds(46, ($cy + 1), 380, 20)
        $rowL.Cursor = 'Hand'; $listPanel.Controls.Add($rowL)

        $statL = New-Object System.Windows.Forms.Label
        $statL.Text = $statusText
        $statL.Font = New-Object System.Drawing.Font('Consolas', 8)
        $statL.ForeColor = $statusColor; $statL.SetBounds(440, ($cy + 3), 170, 16); $listPanel.Controls.Add($statL)

        $detail = [string]$ch.detail
        $rowL.Add_Click({ $detailL.Text = $detail }.GetNewClosure())
        $statL.Add_Click({ $detailL.Text = $detail }.GetNewClosure())
        $iconL.Add_Click({ $detailL.Text = $detail }.GetNewClosure())

        $cy += 28
    }

    if ($dlg.ShowDialog() -eq 'OK') {
        $accepted = @($listPanel.Controls | Where-Object { $_ -is [System.Windows.Forms.CheckBox] -and $_.Checked })
        if ($accepted.Count -gt 0) {
            foreach ($accCb in $accepted) {
                $ch      = $accCb.Tag
                $sysName = [string]$ch.system
                $clsName = [string]$ch.className
                $sc      = [string]$ch.status
                $sec     = $script:sections | Where-Object { $_.label -eq $sysName } | Select-Object -First 1

                if ($sc -eq 'new_in_unity') {
                    if (-not $sec) {
                        $sec = @{
                            id       = [System.Guid]::NewGuid().ToString('N').Substring(0, 8)
                            label    = $sysName
                            category = 'default'
                            excerpt  = ''
                            features = [System.Collections.Generic.List[hashtable]]::new()
                        }
                        $script:sections.Add($sec)
                    }
                    $fid    = [System.Guid]::NewGuid().ToString('N').Substring(0, 8)
                    $newCon = if ($ch.scanned -and $ch.scanned.construct) { [string]$ch.scanned.construct } else { '' }
                    $newFlds = if ($ch.scanned -and $ch.scanned.fields) {
                        [System.Collections.ArrayList]@($ch.scanned.fields | ForEach-Object { @{ name = [string]$_.name; type = [string]$_.type } })
                    } else { [System.Collections.ArrayList]@() }
                    $sec.features.Add(@{
                        id             = $fid
                        label          = "$clsName - imported from Unity"
                        desc           = "Imported via sync."
                        sectionId      = $sec.id
                        unityConstruct = $newCon
                        dataFields     = $newFlds
                        dependencies   = [System.Collections.ArrayList]@()
                    })
                } elseif (($sc -eq 'fields_changed' -or $sc -eq 'construct_changed') -and $sec) {
                    $feat = $sec.features | Where-Object { [string]$_.label -match "^$([regex]::Escape($clsName))\b" } | Select-Object -First 1
                    if ($feat -and $ch.scanned) {
                        if ($ch.scanned.fields) {
                            $feat.dataFields = [System.Collections.ArrayList]@($ch.scanned.fields | ForEach-Object { @{ name = [string]$_.name; type = [string]$_.type } })
                        }
                        if ($ch.scanned.construct) { $feat.unityConstruct = [string]$ch.scanned.construct }
                    }
                } elseif ($sc -eq 'missing_in_unity' -and $sec) {
                    $toRemove = $sec.features | Where-Object { [string]$_.label -match "^$([regex]::Escape($clsName))\b" } | Select-Object -First 1
                    if ($toRemove) { [void]$sec.features.Remove($toRemove) }
                }
            }
            Save-Features; Rebuild-NodeList; Update-ChassisButton; Update-DocButton
            [System.Windows.Forms.MessageBox]::Show(
                "Sync applied: $($accepted.Count) change$(if ($accepted.Count -ne 1) { 's' }) merged.",
                "ValenTech SYNC", 'OK', 'Information') | Out-Null
        }
    }
    $dlg.Dispose()
}

# ── Re-import confirmation ─────────────────────────────────────────────────────
function Show-ReimportConfirm($reimportObj) {
    $sysCnt  = 0
    $featCnt = 0
    if ($reimportObj.features) {
        $reimportObj.features.PSObject.Properties | ForEach-Object {
            $sysCnt++; $featCnt += @($_.Value).Count
        }
    }

    $answer = [System.Windows.Forms.MessageBox]::Show(
        "Import found $sysCnt system$(if ($sysCnt -ne 1) { 's' }) with $featCnt feature$(if ($featCnt -ne 1) { 's' }).`n`nThis replaces all features in your current spec.`n`nContinue?",
        "ValenTech IMPORT", [System.Windows.Forms.MessageBoxButtons]::YesNo, 'Warning')
    if ($answer -ne 'Yes') { return }

    $existingMap = @{}
    foreach ($sec in $script:sections) { $existingMap[$sec.label] = $sec; $sec.features.Clear() }

    if ($reimportObj.features) {
        foreach ($prop in $reimportObj.features.PSObject.Properties) {
            $sysName = $prop.Name
            $sec = if ($existingMap.ContainsKey($sysName)) { $existingMap[$sysName] } else {
                $newSec = @{
                    id       = [System.Guid]::NewGuid().ToString('N').Substring(0, 8)
                    label    = $sysName
                    category = 'default'
                    excerpt  = ''
                    features = [System.Collections.Generic.List[hashtable]]::new()
                }
                $script:sections.Add($newSec); $newSec
            }
            foreach ($f in @($prop.Value)) {
                $fid = [System.Guid]::NewGuid().ToString('N').Substring(0, 8)
                $sec.features.Add(@{
                    id             = $fid
                    label          = [string]$f.title
                    desc           = [string]$f.desc
                    sectionId      = $sec.id
                    unityConstruct = [string]$f.unityConstruct
                    dataFields     = [System.Collections.ArrayList]@(if ($f.dataFields) { @($f.dataFields) | ForEach-Object { @{ name = [string]$_.name; type = [string]$_.type } } } else { @() })
                    dependencies   = [System.Collections.ArrayList]@(if ($f.dependencies) { @($f.dependencies) | ForEach-Object { [string]$_ } } else { @() })
                })
            }
        }
    }

    Save-Features; Rebuild-NodeList; Update-ChassisButton; Update-DocButton
    [System.Windows.Forms.MessageBox]::Show(
        "Spec imported: $sysCnt system$(if ($sysCnt -ne 1) { 's' }), $featCnt feature$(if ($featCnt -ne 1) { 's' }).",
        "ValenTech IMPORT", 'OK', 'Information') | Out-Null

    $exportQ = [System.Windows.Forms.MessageBox]::Show(
        "Generate a GDD document from the imported spec?",
        "ValenTech IMPORT", [System.Windows.Forms.MessageBoxButtons]::YesNo, 'Question')
    if ($exportQ -ne 'Yes') { return }

    $sfd = New-Object System.Windows.Forms.SaveFileDialog
    $sfd.Title = "Save GDD Document"
    $sfd.Filter = "Markdown (*.md)|*.md|Text (*.txt)|*.txt|All Files (*.*)|*.*"
    $sfd.FileName = "Imported_GDD.md"
    $sfd.InitialDirectory = [Environment]::GetFolderPath('MyDocuments')
    if ($sfd.ShowDialog() -eq 'OK') {
        $ts = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        Write-StateFields @{ gdd_export_path = $sfd.FileName; gdd_export_ts = $ts }
        $descBox.ForeColor = $TEXT_MID
        $descBox.Text = "GDD export requested.`n`nClaude is writing your GDD document..."
    }
}

$script:sections = [System.Collections.Generic.List[hashtable]]::new()

# ── Feature persistence ───────────────────────────────────────────────────────
function Save-Features {
    $obj = @{}
    foreach ($sec in $script:sections) {
        if ($sec.features.Count -gt 0) {
            $obj[$sec.label] = @($sec.features | ForEach-Object {
                @{
                    title          = $_.label
                    desc           = [string]$_.desc
                    unityConstruct = if ($_.unityConstruct) { [string]$_.unityConstruct } else { '' }
                    # FIX (single-element-array collapse): ConvertTo-Json collapses a
                    # 1-element Object[] nested two levels deep (hashtable inside this
                    # array inside $obj) to a bare scalar, and an empty Object[] to
                    # {}, producing e.g. "dependencies":"Player Marketplace" or
                    # "dataFields":{} instead of ["Player Marketplace"]/[] in
                    # features.json. ArrayList is exempt from both collapses.
                    dataFields     = [System.Collections.ArrayList]@(if ($_.dataFields)   { $_.dataFields }   else { @() })
                    dependencies   = [System.Collections.ArrayList]@(if ($_.dependencies) { $_.dependencies } else { @() })
                }
            })
        }
    }
    $json = ConvertTo-Json $obj -Depth 6 -Compress
    # FIX (consistency): features.json is read externally by Claude when generating
    # the chassis (CLAUDE.md's GENERATE_CHASSIS step). Use the same atomic
    # tmp+Move-Item pattern as state.json (Write-Atomic, window.ps1:419) instead of
    # a plain truncate-then-write Set-Content, so an external read can never observe
    # a partially-written file.
    Write-Atomic $FEATURES_F $json
}

function Save-Project {
    $savesDir = Join-Path $ROOT "saves"
    if (-not (Test-Path $savesDir)) { New-Item -ItemType Directory $savesDir -Force | Out-Null }
    $name = if ($script:gddFileName) { $script:gddFileName } else { "Project" }
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Save Project"; $dlg.Size = New-Object System.Drawing.Size(400, 110)
    $dlg.BackColor = $PANEL_BG; $dlg.ForeColor = $TEXT_HI
    $dlg.StartPosition = 'CenterParent'; $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false
    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Text = $name; $tb.Font = New-Object System.Drawing.Font("Consolas", 10)
    $tb.BackColor = $CARD_BG; $tb.ForeColor = $TEXT_HI; $tb.SetBounds(10, 10, 362, 24)
    $dlg.Controls.Add($tb)
    $okBtn = New-Object System.Windows.Forms.Button
    $okBtn.Text = "SAVE"; $okBtn.SetBounds(10, 44, 80, 26)
    $okBtn.BackColor = $TEXT_HI; $okBtn.ForeColor = $BG
    $okBtn.FlatStyle = 'Flat'; $okBtn.FlatAppearance.BorderSize = 0
    $okBtn.DialogResult = 'OK'; $dlg.Controls.Add($okBtn); $dlg.AcceptButton = $okBtn
    if ($dlg.ShowDialog() -ne 'OK' -or -not $tb.Text.Trim()) { $dlg.Dispose(); return }
    $projectName = $tb.Text.Trim(); $dlg.Dispose()
    $saveFile = Join-Path $savesDir (($projectName -replace '[\\/:*?"<>|]', '_') + ".json")
    $data = @{
        version     = 2
        projectName = $projectName
        gddFilename = $script:gddFileName
        sections    = @($script:sections | ForEach-Object {
            @{ label=$_.label; category=$_.category; excerpt=$_.excerpt; features=@($_.features | ForEach-Object {
                @{
                    title          = $_.label
                    desc           = $_.desc
                    unityConstruct = if ($_.unityConstruct) { [string]$_.unityConstruct } else { '' }
                    # FIX (same single-element/empty array collapse as Save-Features) —
                    # keep saves/*.json's dataFields/dependencies as proper JSON arrays.
                    dataFields     = [System.Collections.ArrayList]@(if ($_.dataFields)   { $_.dataFields }   else { @() })
                    dependencies   = [System.Collections.ArrayList]@(if ($_.dependencies) { $_.dependencies } else { @() })
                }
            }) }
        })
        savedAt     = [DateTime]::UtcNow.ToString('o')
    }
    $data | ConvertTo-Json -Depth 6 -Compress | Set-Content $saveFile -Encoding UTF8
    [System.Windows.Forms.MessageBox]::Show("Saved to:`n$saveFile", "ValenTech", 'OK', 'Information') | Out-Null
}

function Migrate-Save([string]$filePath, $data) {
    # Upgrades pre-v2 save files in place. Adds unityConstruct, dataFields, dependencies to any
    # feature missing them, bumps version to 2, and rewrites the file. Returns the updated data.
    if ($data.sections) {
        foreach ($sec in $data.sections) {
            if ($sec.features) {
                foreach ($feat in $sec.features) {
                    if ($null -eq $feat.unityConstruct) { $feat | Add-Member -NotePropertyName 'unityConstruct' -NotePropertyValue ''   -Force }
                    if ($null -eq $feat.dataFields)     { $feat | Add-Member -NotePropertyName 'dataFields'     -NotePropertyValue @()  -Force }
                    if ($null -eq $feat.dependencies)   { $feat | Add-Member -NotePropertyName 'dependencies'   -NotePropertyValue @()  -Force }
                }
            }
        }
    }
    $data | Add-Member -NotePropertyName 'version' -NotePropertyValue 2 -Force
    try { $data | ConvertTo-Json -Depth 6 -Compress | Set-Content $filePath -Encoding UTF8 } catch {}
    return $data
}

function Open-SavesPanel {
    $savesDir = Join-Path $ROOT "saves"
    if (-not (Test-Path $savesDir)) { New-Item -ItemType Directory $savesDir -Force | Out-Null }
    $saves = Get-ChildItem $savesDir -Filter "*.json" | Sort-Object LastWriteTime -Descending
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Open Project"; $dlg.Size = New-Object System.Drawing.Size(500, 400)
    $dlg.BackColor = $BG; $dlg.ForeColor = $TEXT_HI
    $dlg.StartPosition = 'CenterParent'; $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "Select a saved project:"; $lbl.Font = New-Object System.Drawing.Font("Consolas", 9)
    $lbl.ForeColor = $TEXT_MID; $lbl.SetBounds(10, 8, 460, 18); $dlg.Controls.Add($lbl)
    $list = New-Object System.Windows.Forms.ListBox
    $list.SetBounds(10, 30, 460, 300)
    $list.BackColor = $CARD_BG; $list.ForeColor = $TEXT_HI
    $list.Font = New-Object System.Drawing.Font("Consolas", 10); $list.BorderStyle = 'None'
    foreach ($f in $saves) { $list.Items.Add($f.BaseName) | Out-Null }
    $dlg.Controls.Add($list)
    $openBtn = New-Object System.Windows.Forms.Button
    $openBtn.Text = "OPEN"; $openBtn.SetBounds(10, 338, 100, 28)
    $openBtn.BackColor = $TEXT_HI; $openBtn.ForeColor = $BG
    $openBtn.FlatStyle = 'Flat'; $openBtn.FlatAppearance.BorderSize = 0
    $openBtn.DialogResult = 'OK'; $dlg.Controls.Add($openBtn); $dlg.AcceptButton = $openBtn
    $list.Add_DoubleClick({ $dlg.DialogResult = 'OK'; $dlg.Close() })
    if ($dlg.ShowDialog() -ne 'OK' -or $list.SelectedIndex -lt 0) { $dlg.Dispose(); return }
    $selected = @($saves)[$list.SelectedIndex]
    $dlg.Dispose()
    try {
        $data = Get-Content $selected.FullName -Raw | ConvertFrom-Json
        $saveVersion = if ($null -ne $data.version) { [int]$data.version } else { 0 }
        if ($saveVersion -lt 2) { $data = Migrate-Save $selected.FullName $data }
        $script:gddFileName = if ($data.gddFilename) { [string]$data.gddFilename } else { '' }
        $fileLabel.Text = $script:gddFileName; $fileLabel.ForeColor = $TEXT_MID
        $script:sections.Clear(); $nodeFlow.Controls.Clear()
        foreach ($sec in $data.sections) {
            $secLabel = if ($sec.label)    { [string]$sec.label }    else { 'Unknown' }
            $cat      = if ($sec.category) { [string]$sec.category } else { Get-SystemCategory $secLabel }
            $col = Get-CategoryColor $cat
            $secObj = @{
                id = 'sys_' + [System.Guid]::NewGuid().ToString('N').Substring(0,6)
                label = $secLabel; color = $col; category = $cat
                excerpt = if ($sec.excerpt) { [string]$sec.excerpt } else { '' }
                features = [System.Collections.Generic.List[hashtable]]::new()
                collapsed = $false
            }
            foreach ($feat in $sec.features) {
                $fid = [System.Guid]::NewGuid().ToString('N').Substring(0,8)
                $secObj.features.Add(@{
                    id             = $fid
                    label          = [string]$feat.title
                    desc           = [string]$feat.desc
                    sectionId      = $secObj.id
                    unityConstruct = if ($feat.unityConstruct) { [string]$feat.unityConstruct } else { '' }
                    dataFields     = if ($feat.dataFields)     { $feat.dataFields }             else { @() }
                    dependencies   = if ($feat.dependencies)   { $feat.dependencies }           else { @() }
                })
            }
            $script:sections.Add($secObj)
        }
        Save-Features
        Rebuild-NodeList
        Update-ChassisButton
        Update-DocButton
        $propTitleL.Text = ''; $propDescL.Text = ''
        $checkPanel.Controls.Clear(); $script:checkboxes.Clear()
        $script:currentTitle = ''; $script:currentContent = ''
        $script:nodeSelectedAt = [datetime]::MinValue
        # FIX (consistency): Parse-GDD resets the canvas to 'waiting_pulse' when
        # switching GDDs (window.ps1:907) — loading a saved project is the same
        # kind of context switch but was missing this, so the previous project's
        # last sim (e.g. creature_chase, gene_pool) kept animating behind the
        # freshly-cleared "Select a concept node to continue" proposal panel.
        Start-SimType 'waiting_pulse' @{}
        Set-Buttons-Idle
        $nodesArr = @($script:sections | ForEach-Object {
            @{ id=$_.id; label=$_.label; type='system'; confirmed=$false; sectionId=$_.id }
        })
        Write-StateFields @{ title = ''; content = ''; response = ''; gdd_raw = ''; nodes = $nodesArr }
        $descBox.Text = "Loaded: $($data.projectName)`n`nSelect a concept node to continue."
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Could not load save.`n$_", "ValenTech") | Out-Null
    }
}

# ── GDD Parser ────────────────────────────────────────────────────────────────
# Derives short system names directly from GDD headings and sub-headings.
# Each system is a standalone clickable node. Confirmed proposals grow child features under it.

function Parse-GDD([string]$raw) {
    $script:sections.Clear()
    $nodeFlow.Controls.Clear()

    # Clear stale proposal panel from previous GDD
    $propTitleL.Text = ''; $propDescL.Text = ''
    $checkPanel.Controls.Clear(); $script:checkboxes.Clear()
    $script:currentTitle = ''; $script:currentContent = ''
    $script:nodeSelectedAt = [datetime]::MinValue
    Start-SimType 'waiting_pulse' @{}; Set-Buttons-Idle

    Write-StateFields @{ gdd_raw = $raw; title = ''; content = ''; response = '' }

    $stripWords = @('system','overview','design','details','mechanic','feature','rules','structure',
                    'description','notes','examples','example','function','functions','types','type',
                    'ones','list','open','questions','question','how','work','works','earn','expand',
                    'evaluate','adjust','adjustment','adjustments','reward','rewards',
                    'the','a','an','and','or','of','with','for','in','to','at','by','its','their')

    $seen  = [System.Collections.Generic.HashSet[string]]::new()
    $lines = $raw -split "`n"

    # Phase 1 — identify headings with line index
    $headings = [System.Collections.Generic.List[hashtable]]::new()

    for ($li = 0; $li -lt $lines.Count; $li++) {
        $l = $lines[$li].Trim()
        if ($l.Length -lt 3) { continue }

        $candidate = $null
        if    ($l -match '^\s*\d+[\d.]*\s+(.+)$') { $candidate = $matches[1].Trim() }
        elseif ($l -match '^#{1,3}\s+(.+)$')       { $candidate = $matches[1].Trim() }
        if (-not $candidate) { continue }

        if ($candidate -match '[\x00-\x08\x0B\x0C\x0E-\x1F]') { continue }
        if ($candidate -match '^\d+$') { continue }
        if ($candidate.Length -lt 3 -or $candidate.Length -gt 50) { continue }

        $words    = ($candidate -replace '[&\-\(\)\|/]',' ' -split '\s+') | Where-Object { $_.Length -gt 1 }
        $keyWords = $words | Where-Object { $w = $_.ToLower(); $stripWords -notcontains $w -and $w -cmatch '^[A-Za-z]' }
        if (-not @($keyWords)) { continue }

        $nameWords = @($keyWords) | Select-Object -First 3
        $name = ($nameWords | ForEach-Object { $_.Substring(0,1).ToUpper() + $_.Substring(1).ToLower() }) -join ' '
        if ($name.Length -lt 4) { continue }
        if (@($nameWords).Count -lt 2 -and $name.Length -lt 6) { continue }

        $name = ($name -split ' ' | Select-Object -Unique) -join ' '
        $namePartsClean = ($name -split ' ') | Where-Object { @('Physical','Co','Ai','Uncertainty','Ones','Gold','Creature','Function') -notcontains $_ }
        if (-not @($namePartsClean)) { continue }
        $name = $namePartsClean -join ' '
        if ($name.Length -lt 4) { continue }

        $name = $name -replace '\bCo Op\b','Co-op' -replace '\bRanch Tycoon\b','Ranch Management' `
                      -replace '\bAdventure Exploration\b','Exploration' -replace '\bCore Pillars\b','Core Loop' `
                      -replace '\bBuilding Bond\b','Bond Building' -replace '\bPerspective Camera\b','Camera System' `
                      -replace '\bCreature Behaviour\b','Creature AI' -replace '\bBond Breeding\b','Breeding Bonds'

        if (-not $seen.Add($name.ToLower())) { continue }
        $headings.Add(@{ idx=$li; name=$name })
    }

    # Phase 2 — extract GDD body excerpt for each heading (text between this heading and the next)
    for ($hi = 0; $hi -lt $headings.Count; $hi++) {
        $start  = $headings[$hi].idx + 1
        $end    = if ($hi + 1 -lt $headings.Count) { $headings[$hi+1].idx } else { [Math]::Min($lines.Count, $start + 40) }
        $parts  = for ($bi = $start; $bi -lt $end; $bi++) {
            $bl = $lines[$bi].Trim()
            if ($bl.Length -gt 5 -and $bl -notmatch '^[#\d]' -and $bl -notmatch '[\x00-\x08\x0B\x0C\x0E-\x1F]') { $bl }
        }
        $excerpt = (($parts -join ' ') -replace '\s+', ' ').Trim()
        if ($excerpt.Length -gt 600) { $excerpt = $excerpt.Substring(0, 600) }
        $headings[$hi].excerpt   = $excerpt
        # True (uncapped) section bounds, used by update_document.ps1 to splice
        # confirmed-implementation notes back into gdd_raw at the right spot.
        $headings[$hi].lineStart = $headings[$hi].idx
        $headings[$hi].lineEnd   = if ($hi + 1 -lt $headings.Count) { $headings[$hi+1].idx } else { $lines.Count }
    }

    # FIX (empty gdd_section for divider headings): a heading immediately
    # followed by its first sub-heading (e.g. "7. Online -- Trading & Co-op"
    # directly followed by "7.1 Player Marketplace") has zero body lines of its
    # own, so $excerpt above comes out empty -- Claude then gets gdd_section=""
    # for that node and has nothing to tailor a proposal from. Walk backwards so
    # a chain of empty headings each borrow from the next (already-fixed) one.
    for ($hi = $headings.Count - 2; $hi -ge 0; $hi--) {
        if (-not $headings[$hi].excerpt) {
            $headings[$hi].excerpt = $headings[$hi+1].excerpt
        }
    }

    # Phase 3 — build section objects with category colors and GDD excerpt
    foreach ($h in $headings) {
        $cat = Get-SystemCategory $h.name
        $col = Get-CategoryColor $cat
        $script:sections.Add(@{
            id        = 'sys_' + [System.Guid]::NewGuid().ToString('N').Substring(0,6)
            label     = $h.name
            excerpt   = $h.excerpt
            color     = $col
            category  = $cat
            features  = [System.Collections.Generic.List[hashtable]]::new()
            collapsed = $false
            lineStart = $h.lineStart
            lineEnd   = $h.lineEnd
        })
    }

    # Sort sections by category in rainbow order
    $sortOrder = @{ combat=0; economy=1; progress=2; plant=3; both=4; explore=5; animal=6; social=7; building=8; ui=9; default=10 }
    $sorted = $script:sections | Sort-Object { $sortOrder[$_.category] }
    $script:sections.Clear()
    foreach ($s in $sorted) { $script:sections.Add($s) }

    Rebuild-NodeList
    Update-ChassisButton
    Update-DocButton

    $nodesArr = @($script:sections | ForEach-Object {
        @{ id=$_.id; label=$_.label; type='system'; confirmed=$false; sectionId=$_.id; lineStart=$_.lineStart; lineEnd=$_.lineEnd }
    })
    Write-StateFields @{ nodes = $nodesArr }
}


function Show-EditDialog([string]$current) {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Edit Feature"
    $dlg.Size = New-Object System.Drawing.Size(400, 110)
    $dlg.BackColor = $PANEL_BG
    $dlg.ForeColor = $TEXT_HI
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false
    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Text = $current
    $tb.Font = New-Object System.Drawing.Font("Consolas", 10)
    $tb.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 40)
    $tb.ForeColor = $TEXT_HI
    $tb.SetBounds(10, 10, 362, 24)
    $dlg.Controls.Add($tb)
    $okBtn = New-Object System.Windows.Forms.Button
    $okBtn.Text = "OK"
    $okBtn.SetBounds(10, 44, 80, 26)
    $okBtn.BackColor = [System.Drawing.Color]::FromArgb(0, 30, 15)
    $okBtn.ForeColor = $GREEN
    $okBtn.FlatStyle = 'Flat'
    $okBtn.FlatAppearance.BorderColor = $GREEN
    $okBtn.DialogResult = 'OK'
    $dlg.Controls.Add($okBtn)
    $dlg.AcceptButton = $okBtn
    $result = $dlg.ShowDialog()
    $val = $tb.Text.Trim()
    $dlg.Dispose()
    if ($result -eq 'OK' -and $val) { return $val } else { return $null }
}

function Rebuild-NodeList {
    $nodeFlow.Controls.Clear()

    foreach ($sec in $script:sections) {
        $col = $sec.color

        # Section header row
        $hdr = New-Object System.Windows.Forms.Panel
        $hdr.Width  = $TREE_W - 12
        $hdr.Height = 28
        $hdr.Margin = New-Object System.Windows.Forms.Padding(0, 2, 0, 0)
        $hdr.BackColor = [System.Drawing.Color]::FromArgb(255, [int](14 + $col.R*0.06), [int](14 + $col.G*0.06), [int](14 + $col.B*0.06))
        $hdr.Tag    = $sec
        $hdr.Cursor = [System.Windows.Forms.Cursors]::Hand

        $bar = New-Object System.Windows.Forms.Panel
        $bar.SetBounds(0, 0, 4, 28)
        $bar.BackColor = $col
        $hdr.Controls.Add($bar)

        $hdrLbl = New-Object System.Windows.Forms.Label
        $countStr = if ($sec.features.Count -gt 0) { "  (" + $sec.features.Count + ")" } else { "" }
        $hdrLbl.Text = $sec.label + $countStr
        $hdrLbl.Font = New-Object System.Drawing.Font("Consolas", 9, [System.Drawing.FontStyle]::Bold)
        $hdrLbl.ForeColor = $col
        $hdrLbl.SetBounds(10, 5, $TREE_W - 46, 18)
        $hdr.Controls.Add($hdrLbl)

        # Collapse toggle
        $collapseBtn = New-Object System.Windows.Forms.Label
        $collapseBtn.Text = if ($sec.collapsed) { if ($sec.features.Count -gt 0) { "[" + $sec.features.Count + "]" } else { ">" } } else { "v" }
        $collapseBtn.Font = New-Object System.Drawing.Font("Consolas", 8, [System.Drawing.FontStyle]::Bold)
        $collapseBtn.ForeColor = [System.Drawing.Color]::FromArgb(160, $col.R, $col.G, $col.B)
        $collapseBtn.SetBounds($TREE_W - 38, 7, 16, 14)
        $collapseBtn.Cursor = [System.Windows.Forms.Cursors]::Hand
        $collapseBtn.Tag = $sec
        $collapseBtn.Add_Click({
            param($s,$e)
            $targetSec = $s.Tag
            $targetSec.collapsed = -not $targetSec.collapsed
            Rebuild-NodeList
        })
        $hdr.Controls.Add($collapseBtn)

        $hdr.Add_Click({ param($s,$e) Select-Node $s.Tag })
        $hdrLbl.Add_Click({ param($s,$e) Select-Node $s.Parent.Tag })
        $nodeFlow.Controls.Add($hdr)

        # Confirmed features (hidden when collapsed)
        if (-not $sec.collapsed) {
            foreach ($feat in $sec.features) {
                $frow = New-Object System.Windows.Forms.Panel
                $frow.Width  = $TREE_W - 12
                $frow.Height = 24
                $frow.Margin = [System.Windows.Forms.Padding]::Empty
                $frow.BackColor = $CARD_BG
                $frow.Tag    = $feat
                $frow.Cursor = [System.Windows.Forms.Cursors]::Hand

                $fstripe = New-Object System.Windows.Forms.Panel
                $fstripe.SetBounds(0, 0, 4, 24)
                $fstripe.BackColor = [System.Drawing.Color]::FromArgb(80, $col.R, $col.G, $col.B)
                $frow.Controls.Add($fstripe)

                $fcheck = New-Object System.Windows.Forms.Label
                $fcheck.Text = "+"
                $fcheck.Font = New-Object System.Drawing.Font("Consolas", 7, [System.Drawing.FontStyle]::Bold)
                $fcheck.ForeColor = $GREEN
                $fcheck.SetBounds(8, 4, 10, 14)
                $frow.Controls.Add($fcheck)

                $flbl = New-Object System.Windows.Forms.Label
                $flbl.Text = $feat.label
                $flbl.Font = New-Object System.Drawing.Font("Consolas", 7)
                $flbl.ForeColor = $GREEN
                $flbl.SetBounds(20, 4, $TREE_W - 30, 14)
                $frow.Controls.Add($flbl)

                # Right-click context menu: Edit / Delete
                $cms = New-Object System.Windows.Forms.ContextMenuStrip
                $cms.BackColor = $PANEL_BG
                $cms.ForeColor = $TEXT_HI
                $cms.RenderMode = 'System'

                $editItem = New-Object System.Windows.Forms.ToolStripMenuItem("Edit")
                $editItem.ForeColor = $AMBER
                $editItem.Tag = @{ feat = $feat; lbl = $flbl }
                $editItem.Add_Click({
                    param($s,$e)
                    $d = $s.Tag
                    $newText = Show-EditDialog $d.feat.label
                    if ($newText) { $d.feat.label = $newText; $d.lbl.Text = $newText; Save-Features; Rebuild-NodeList }
                })

                $deleteItem = New-Object System.Windows.Forms.ToolStripMenuItem("Delete")
                $deleteItem.ForeColor = $RED_COL
                $deleteItem.Tag = @{ feat = $feat; sec = $sec }
                $deleteItem.Add_Click({
                    param($s,$e)
                    $d = $s.Tag
                    $d.sec.features.Remove($d.feat) | Out-Null
                    Save-Features
                    Rebuild-NodeList
                    # FIX (stale enabled-state): Update-ChassisButton re-evaluates
                    # "does any section have features" — called after Confirm (window.ps1:493),
                    # Load (:872), and Parse (:995), all of which can make this true. Delete
                    # is the inverse mutation (can make it false, e.g. deleting the very last
                    # confirmed feature) and was the only path that skipped it, leaving
                    # GENERATE clickable with an empty features.json.
                    Update-ChassisButton
                    Update-DocButton
                })

                $cms.Items.Add($editItem)  | Out-Null
                $cms.Items.Add($deleteItem) | Out-Null

                $frow.ContextMenuStrip   = $cms
                $fcheck.ContextMenuStrip = $cms
                $flbl.ContextMenuStrip   = $cms

                $nodeFlow.Controls.Add($frow)
            }
        }
    }
}

function Select-Node([hashtable]$n) {
    if (-not $n) { return }
    $script:currentNode = $n.id

    # Highlight selected system row — single pass
    foreach ($ctrl in $nodeFlow.Controls) {
        if (-not ($ctrl.Tag -and $ctrl.Tag.color)) { continue }
        $c = $ctrl.Tag.color
        $ctrl.BackColor = if ($ctrl.Tag.id -eq $n.id) {
            [System.Drawing.Color]::FromArgb(0, 40, 60)
        } else {
            [System.Drawing.Color]::FromArgb(20, $c.R, $c.G, $c.B)
        }
    }

    $sec = $script:sections | Where-Object { $_.id -eq $n.id } | Select-Object -First 1
    # FIX (real root cause of the lingering-old-proposal display): this write sets
    # selected_node to the NEW node, but title/content/sim/components in state.json
    # still hold the PREVIOUS proposal — propose_one.ps1 hasn't run yet. The display
    # gate below only checks `selected_node -eq currentNode` + non-empty title, so
    # for one tick it sees "new node" + "old (non-empty) title" and redisplays the
    # stale proposal under the new node — clobbering the "Generating..." text set
    # below. Clear title/content/sim/components in THE SAME atomic write so the
    # gate can never observe a matching selected_node alongside stale proposal text.
    Write-StateFields @{
        request         = $n.label
        request_ts      = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        selected_node   = $n.id
        response        = ''
        gdd_section     = if ($sec -and $sec.excerpt) { $sec.excerpt } else { '' }
        title           = ''
        content         = ''
        sim             = ''
        components      = @()
        component_data  = @()
    }

    # Clear any stale proposal from a previously selected node — title/desc/
    # checkboxes must not linger on screen while we wait for the new proposal
    # to arrive. Mirrors $btnReroll.Add_Click (window.ps1:497-505): show
    # "Generating..." instead of leaving the old proposal's title AND
    # description visible (previously only the title was cleared here).
    $propTitleL.Text = "Generating..."
    $propDescL.Text  = ""
    $checkPanel.Controls.Clear()
    $script:checkboxes.Clear()
    $script:currentTitle   = ''
    $script:currentContent = ''

    $descBox.Text = "  " + $n.label + "`n`nWaiting for proposals..."
    $script:nodeSelectedAt = [datetime]::UtcNow
    Set-Buttons-Idle
    Start-SimType 'waiting_pulse' @{}
}

# ── Sim engine ────────────────────────────────────────────────────────────────
function Start-SimType([string]$type, [hashtable]$params) {
    $script:simType   = $type
    $script:simParams = $params
    $script:simTick   = 0
}

function Draw-Sim {
    $cw = $canvas.Width; $ch = $canvas.Height
    if ($cw -le 4 -or $ch -le 4) { return }
    $bmp = New-Object System.Drawing.Bitmap($cw, $ch)
    $g   = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear($BG)
    $t  = $script:simTick * 0.03
    $cx = [int]($cw / 2); $cy = [int]($ch / 2)

    switch ($script:simType) {

        'waiting_pulse' {
            $r     = [int](18 + [Math]::Sin($t * 2) * 6)
            $alpha = [int](80 + [Math]::Sin($t * 1.5) * 60)
            $pen   = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb($alpha, 0, 180, 255), 2)
            $g.DrawEllipse($pen, ($cx-$r), ($cy-$r), $r*2, $r*2)
            $pen.Dispose()
            $r2   = [int]($r * 1.6)
            $pen2 = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb([int]($alpha*0.5), 180, 0, 255), 1)
            $g.DrawEllipse($pen2, ($cx-$r2), ($cy-$r2), $r2*2, $r2*2)
            $pen2.Dispose()
            $br  = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(100, 0, 200, 255))
            $sz  = $g.MeasureString("SELECT A NODE", $script:fnt11)
            $g.DrawString("SELECT A NODE", $script:fnt11, $br, ($cx - $sz.Width/2), ($cy + $r + 14))
            $br.Dispose()
        }

        'loop_diagram' {
            $p        = $script:simParams
            $labels   = if ($p.labels)    { $p.labels }    else { @("INPUT","PROCESS","OUTPUT","FEEDBACK") }
            $count    = $labels.Count
            $radius   = [int]([Math]::Min($cw,$ch) * 0.3)
            $dotR     = 22
            $speed    = if ($p.speed)     { [double]$p.speed } else { 0.4 }
            $pulsePos = ($t * $speed) % 1.0

            $ep = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(50,0,200,255),1)
            $pb = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(220,0,255,180))
            for ($i = 0; $i -lt $count; $i++) {
                $angle = 2*[Math]::PI*$i/$count - [Math]::PI/2
                $nx  = [int]($cx + $radius*[Math]::Cos($angle))
                $ny  = [int]($cy + $radius*[Math]::Sin($angle))
                $ni  = ($i+1)%$count
                $na  = 2*[Math]::PI*$ni/$count - [Math]::PI/2
                $nx2 = [int]($cx + $radius*[Math]::Cos($na))
                $ny2 = [int]($cy + $radius*[Math]::Sin($na))

                $g.DrawLine($ep,$nx,$ny,$nx2,$ny2)

                $px = [int]($nx + ($nx2-$nx)*$pulsePos)
                $py = [int]($ny + ($ny2-$ny)*$pulsePos)
                $g.FillEllipse($pb,($px-5),($py-5),10,10)

                $col = if ($p.nodeTypes -and $p.nodeTypes[$i]) { Get-NodeColor $p.nodeTypes[$i] } else { $MECH_COL }
                $nb  = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(30,$col.R,$col.G,$col.B))
                $np  = New-Object System.Drawing.Pen($col,2)
                $g.FillEllipse($nb,($nx-$dotR),($ny-$dotR),$dotR*2,$dotR*2)
                $g.DrawEllipse($np,($nx-$dotR),($ny-$dotR),$dotR*2,$dotR*2)
                $nb.Dispose(); $np.Dispose()

                $lb   = New-Object System.Drawing.SolidBrush($col)
                $lstr = if ($labels[$i]) { $labels[$i] } else { "NODE" }
                $sz   = $g.MeasureString($lstr,$script:fnt7B)
                $g.DrawString($lstr,$script:fnt7B,$lb,($nx-$sz.Width/2),($ny-$sz.Height/2))
                $lb.Dispose()
            }
            $ep.Dispose(); $pb.Dispose()
        }

        'progression_curve' {
            $p    = $script:simParams
            $mils = if ($p.milestones) { [int[]]$p.milestones } else { @(1,5,10,20,50) }
            $curv = if ($p.curve) { $p.curve } else { 'exponential' }
            $col  = if ($p.color) { try { [System.Drawing.ColorTranslator]::FromHtml($p.color) } catch { $LOOP_COL } } else { $LOOP_COL }
            $pad  = 40; $gw = $cw-$pad*2; $gh = $ch-$pad*2
            if ($gw -le 0 -or $gh -le 0) { $g.Dispose(); $bmp.Dispose(); return }

            $gp = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(25,255,255,255),1)
            for ($gi=0;$gi-le 4;$gi++) {
                $gx2=[int]($pad+$gw*$gi/4); $gy2=[int]($pad+$gh*$gi/4)
                $g.DrawLine($gp,$gx2,$pad,$gx2,$pad+$gh)
                $g.DrawLine($gp,$pad,$gy2,$pad+$gw,$gy2)
            }; $gp.Dispose()
            $ap = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(80,255,255,255),1)
            $g.DrawLine($ap,$pad,$pad,$pad,$pad+$gh)
            $g.DrawLine($ap,$pad,$pad+$gh,$pad+$gw,$pad+$gh); $ap.Dispose()

            $prog = [Math]::Min(1.0,$t/4.0)
            $pts  = [System.Collections.Generic.List[System.Drawing.Point]]::new()
            $steps = [int]($gw*$prog)
            for ($xi=0;$xi-le $steps;$xi++) {
                $xn = $xi/$gw
                $yn = switch($curv) {
                    'exponential' { [Math]::Pow($xn,2.2) }
                    'logarithmic' { if($xn-eq 0){0}else{[Math]::Log($xn*9+1)/[Math]::Log(10)} }
                    'linear'      { $xn }
                    default       { [Math]::Pow($xn,1.5) }
                }
                $py2 = [int]([Math]::Max($pad,[Math]::Min($pad+$gh,$pad+$gh-$yn*$gh)))
                $pts.Add([System.Drawing.Point]::new($pad+$xi,$py2))
            }
            if ($pts.Count -ge 2) {
                $cp = New-Object System.Drawing.Pen($col,2); $g.DrawLines($cp,$pts.ToArray()); $cp.Dispose()
                $hp = $pts[$pts.Count-1]
                $hb = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(200,$col.R,$col.G,$col.B))
                $g.FillEllipse($hb,($hp.X-4),($hp.Y-4),8,8); $hb.Dispose()
            }
            $maxM = $mils[$mils.Count-1]
            $mp = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(120,255,200,0),1)
            $mb = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(200,255,200,0))
            foreach ($m in $mils) {
                $xn=$m/$maxM; if($xn-gt $prog){continue}
                $mx=$pad+[int]($xn*$gw)
                $g.DrawLine($mp,$mx,$pad,$mx,$pad+$gh)
                $g.DrawString([string]$m,$script:fnt7,$mb,($mx+2),($pad+4))
            }; $mp.Dispose(); $mb.Dispose()
            $lb = New-Object System.Drawing.SolidBrush($TEXT_DIM)
            $g.DrawString("LEVEL",$script:fnt8,$lb,($pad+$gw/2-20),($pad+$gh+14))
            $g.DrawString("XP",$script:fnt8,$lb,4,($pad+$gh/2-8))
            $lb.Dispose()
        }

        'feature_tree' {
            $p        = $script:simParams
            $rootLbl  = if ($p.root)     { $p.root }     else { "CORE" }
            $children = if ($p.children) { $p.children } else { @("Feature A","Feature B","Feature C") }
            $col      = if ($p.color)    { try { [System.Drawing.ColorTranslator]::FromHtml($p.color) } catch { $SYS_COL } } else { $SYS_COL }
            $prog     = [Math]::Min(1.0,$t/3.0)
            $rootY    = [int]($ch*0.18); $childY=[int]($ch*0.5)

            $rb=New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(40,$col.R,$col.G,$col.B))
            $g.FillEllipse($rb,($cx-28),($rootY-14),56,28); $rb.Dispose()
            $rp=New-Object System.Drawing.Pen($col,2)
            $g.DrawEllipse($rp,($cx-28),($rootY-14),56,28); $rp.Dispose()
            $rbr = New-Object System.Drawing.SolidBrush($col)
            $rsz = $g.MeasureString($rootLbl,$script:fnt8B)
            $g.DrawString($rootLbl,$script:fnt8B,$rbr,($cx-$rsz.Width/2),($rootY-$rsz.Height/2))
            $rbr.Dispose()

            if ($prog -ge 0.01) {
                $count=$children.Count
                for ($ci=0;$ci-lt $count;$ci++) {
                    $chx=[int]($cw*(($ci+1.0)/($count+1)))
                    $alpha=[int]([Math]::Min(1.0,$prog/0.5)*220)
                    $lp=New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb([int]($alpha*0.4),$col.R,$col.G,$col.B),1)
                    $g.DrawLine($lp,$cx,$rootY+14,$chx,$childY-14); $lp.Dispose()
                    $cb=New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb([int]($alpha*0.15),$MECH_COL.R,$MECH_COL.G,$MECH_COL.B))
                    $g.FillEllipse($cb,($chx-28),($childY-14),56,28); $cb.Dispose()
                    $cp2=New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb($alpha,$MECH_COL.R,$MECH_COL.G,$MECH_COL.B),1)
                    $g.DrawEllipse($cp2,($chx-28),($childY-14),56,28); $cp2.Dispose()
                    $cbr=New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb($alpha,$MECH_COL.R,$MECH_COL.G,$MECH_COL.B))
                    $clbl=if($children[$ci].Length -gt 8){$children[$ci].Substring(0,8)}else{$children[$ci]}
                    $csz=$g.MeasureString($clbl,$script:fnt7)
                    $g.DrawString($clbl,$script:fnt7,$cbr,($chx-$csz.Width/2),($childY-$csz.Height/2))
                    $cbr.Dispose()
                }
            }
        }

        'stat_radar' {
            # Radar/spider chart — stats, attributes, balance, character builds
            $p    = $script:simParams
            $lbls = if ($p.labels) { $p.labels } else { @("SPEED","POWER","RANGE","SKILL","LUCK") }
            $vals = if ($p.values) { [double[]]$p.values } else { @(0.7,0.5,0.8,0.6,0.4) }
            $col  = if ($p.color)  { try { [System.Drawing.ColorTranslator]::FromHtml($p.color) } catch { $AMBER } } else { $AMBER }
            $nv   = $lbls.Count
            $rad2 = [int]([Math]::Min($cw,$ch) * 0.30)
            $labR = $rad2 + 22
            $rgp = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(18,255,255,255),1)
            for ($ring2 = 1; $ring2 -le 3; $ring2++) {
                $rr2 = [int]($rad2 * $ring2 / 3)
                $g.DrawEllipse($rgp,($cx-$rr2),($cy-$rr2),$rr2*2,$rr2*2)
            }; $rgp.Dispose()
            $aap = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(22,255,255,255),1)
            $llb = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(160,$col.R,$col.G,$col.B))
            for ($ai = 0; $ai -lt $nv; $ai++) {
                $ang4 = 2*[Math]::PI*$ai/$nv - [Math]::PI/2
                $aax  = [int]($cx + $rad2 * [Math]::Cos($ang4))
                $aay  = [int]($cy + $rad2 * [Math]::Sin($ang4))
                $g.DrawLine($aap,$cx,$cy,$aax,$aay)
                $llx  = [int]($cx + $labR * [Math]::Cos($ang4))
                $lly  = [int]($cy + $labR * [Math]::Sin($ang4))
                $lsz  = $g.MeasureString($lbls[$ai],$script:fnt7B)
                $g.DrawString($lbls[$ai],$script:fnt7B,$llb,($llx-$lsz.Width/2),($lly-$lsz.Height/2))
            }; $aap.Dispose(); $llb.Dispose()
            $pulse2 = 0.85 + [Math]::Sin($t * 0.5) * 0.15
            $polyList = [System.Collections.Generic.List[System.Drawing.Point]]::new()
            for ($vi = 0; $vi -lt $nv; $vi++) {
                $ang4 = 2*[Math]::PI*$vi/$nv - [Math]::PI/2
                $vv   = if ($vi -lt $vals.Count) { [double]$vals[$vi] } else { 0.5 }
                $polyList.Add([System.Drawing.Point]::new(
                    [int]($cx + $rad2 * $vv * $pulse2 * [Math]::Cos($ang4)),
                    [int]($cy + $rad2 * $vv * $pulse2 * [Math]::Sin($ang4))
                ))
            }
            if ($polyList.Count -ge 3) {
                $polyArr = $polyList.ToArray()
                $pfb = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(28,$col.R,$col.G,$col.B))
                $ppp = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(200,$col.R,$col.G,$col.B),2)
                $g.FillPolygon($pfb,$polyArr); $g.DrawPolygon($ppp,$polyArr)
                $pfb.Dispose(); $ppp.Dispose()
                $db2 = New-Object System.Drawing.SolidBrush($col)
                foreach ($pt2 in $polyArr) { $g.FillEllipse($db2,($pt2.X-4),($pt2.Y-4),8,8) }
                $db2.Dispose()
            }
        }

        'creature_chase' {
            # Combat — all GDI objects created once, reused, disposed at end
            $p    = $script:simParams
            $col  = if ($p.color)  { try { [System.Drawing.ColorTranslator]::FromHtml($p.color)  } catch { $RED_COL  } } else { $RED_COL  }
            $col2 = if ($p.color2) { try { [System.Drawing.ColorTranslator]::FromHtml($p.color2) } catch { $MECH_COL } } else { $MECH_COL }
            $crX  = [int]($cx + [Math]::Sin($t*0.5)*$cw*0.28);   $crY = [int]($cy - $ch*0.12)
            $huX  = [int]($cx + [Math]::Sin($t*0.5-1.1)*$cw*0.28); $huY = [int]($cy + $ch*0.14)
            $dx   = $crX-$huX; $dy = $crY-$huY
            $ang  = [Math]::Atan2($dy,$dx); $cLen=80; $cHalf=[Math]::PI/6.5
            $penRed = New-Object System.Drawing.Pen($col,2)
            $brRed  = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(40,$col.R,$col.G,$col.B))
            $penCyn = New-Object System.Drawing.Pen($col2,2)
            $brCyn  = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(25,$col2.R,$col2.G,$col2.B))
            $brTxt  = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(160,$col.R,$col.G,$col.B))
            # Single pulsing noise ring (reuse $penRed)
            $rr = [int]((($t*1.1)%1.0)*55)+5
            $g.DrawEllipse($penRed,($crX-$rr),($crY-$rr),$rr*2,$rr*2)
            # Stealth cone (reuse $brCyn/$penCyn)
            $cpt1=[System.Drawing.Point]::new($huX,$huY)
            $cpt2=[System.Drawing.Point]::new([int]($huX+$cLen*[Math]::Cos($ang+$cHalf)),[int]($huY+$cLen*[Math]::Sin($ang+$cHalf)))
            $cpt3=[System.Drawing.Point]::new([int]($huX+$cLen*[Math]::Cos($ang-$cHalf)),[int]($huY+$cLen*[Math]::Sin($ang-$cHalf)))
            $g.FillPolygon($brCyn,@($cpt1,$cpt2,$cpt3))
            $g.DrawLine($penCyn,$cpt1,$cpt2); $g.DrawLine($penCyn,$cpt1,$cpt3)
            # Creature diamond (reuse $brRed/$penRed)
            $dm=@([System.Drawing.Point]::new($crX,$crY-14),[System.Drawing.Point]::new($crX+10,$crY),[System.Drawing.Point]::new($crX,$crY+14),[System.Drawing.Point]::new($crX-10,$crY))
            $g.FillPolygon($brRed,$dm); $g.DrawPolygon($penRed,$dm)
            # Hunter circle (reuse $brCyn/$penCyn)
            $g.FillEllipse($brCyn,($huX-11),($huY-11),22,22); $g.DrawEllipse($penCyn,($huX-11),($huY-11),22,22)
            # Labels (reuse $brTxt)
            $tgt=[string]$(if($p.target){$p.target}else{"PREY"}); $hnt=[string]$(if($p.hunter){$p.hunter}else{"HUNTER"})
            $s1=$g.MeasureString($tgt,$script:fnt7B); $g.DrawString($tgt,$script:fnt7B,$brTxt,($crX-$s1.Width/2),($crY+18))
            $s2=$g.MeasureString($hnt,$script:fnt7B); $g.DrawString($hnt,$script:fnt7B,$brTxt,($huX-$s2.Width/2),($huY-28))
            $penRed.Dispose();$brRed.Dispose();$penCyn.Dispose();$brCyn.Dispose();$brTxt.Dispose()
        }

        'gene_pool' {
            # Genetics — all GDI objects created once, reused, disposed at end
            $p     = $script:simParams
            $col1  = if ($p.color1){try{[System.Drawing.ColorTranslator]::FromHtml($p.color1)}catch{$MECH_COL}}else{$MECH_COL}
            $col2  = if ($p.color2){try{[System.Drawing.ColorTranslator]::FromHtml($p.color2)}catch{$SYS_COL}}else{$SYS_COL}
            $pAL   = [string]$(if($p.parentA){$p.parentA}else{"PARENT A"})
            $pBL   = [string]$(if($p.parentB){$p.parentB}else{"PARENT B"})
            $offL  = [string]$(if($p.offspring){$p.offspring}else{"OFFSPRING"})
            $aX=[int]($cx-$cw*0.22); $aY=[int]($cy-$ch*0.18)
            $bX=[int]($cx+$cw*0.22); $bY=$aY; $oX=$cx; $oY=[int]($cy+$ch*0.18)
            $pp   = ($t*0.55)%1.0; $fromA=([int]($t*0.55)%2 -eq 0)
            $pc   = if($fromA){$col1}else{$col2}; $fx=if($fromA){$aX}else{$bX}
            $tpx  = [int]($fx+($oX-$fx)*$pp); $tpy=[int]($aY+($oY-$aY)*$pp)
            $penA  = New-Object System.Drawing.Pen($col1,2)
            $brA   = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(30,$col1.R,$col1.G,$col1.B))
            $penB  = New-Object System.Drawing.Pen($col2,2)
            $brB   = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(30,$col2.R,$col2.G,$col2.B))
            $penFt = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(18,200,200,200),1)
            $penOf = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(180,220,220,220),2)
            $brOf  = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(22,200,200,200))
            $brPt  = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(210,$pc.R,$pc.G,$pc.B))
            $brLA  = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(160,$col1.R,$col1.G,$col1.B))
            $brLB  = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(160,$col2.R,$col2.G,$col2.B))
            $brLO  = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(200,200,200,200))
            $g.DrawLine($penFt,$aX,$aY,$oX,$oY); $g.DrawLine($penFt,$bX,$bY,$oX,$oY)
            $g.FillEllipse($brPt,($tpx-6),($tpy-6),12,12)
            $g.FillEllipse($brA,($aX-22),($aY-22),44,44); $g.DrawEllipse($penA,($aX-22),($aY-22),44,44)
            $g.FillEllipse($brB,($bX-22),($bY-22),44,44); $g.DrawEllipse($penB,($bX-22),($bY-22),44,44)
            $g.FillEllipse($brOf,($oX-18),($oY-18),36,36); $g.DrawEllipse($penOf,($oX-18),($oY-18),36,36)
            $sA=$g.MeasureString($pAL,$script:fnt7B); $g.DrawString($pAL,$script:fnt7B,$brLA,($aX-$sA.Width/2),($aY+26))
            $sB=$g.MeasureString($pBL,$script:fnt7B); $g.DrawString($pBL,$script:fnt7B,$brLB,($bX-$sB.Width/2),($bY+26))
            $sO=$g.MeasureString($offL,$script:fnt7B); $g.DrawString($offL,$script:fnt7B,$brLO,($oX-$sO.Width/2),($oY+22))
            $penA.Dispose();$brA.Dispose();$penB.Dispose();$brB.Dispose()
            $penFt.Dispose();$penOf.Dispose();$brOf.Dispose();$brPt.Dispose()
            $brLA.Dispose();$brLB.Dispose();$brLO.Dispose()
        }

        'bond_grow' {
            # Social — all GDI objects created once, reused, disposed at end
            $p   = $script:simParams
            $col = if($p.color){try{[System.Drawing.ColorTranslator]::FromHtml($p.color)}catch{$SYS_COL}}else{$SYS_COL}
            $pL  = [string]$(if($p.player){$p.player}else{"PLAYER"})
            $cL  = [string]$(if($p.creature){$p.creature}else{"CREATURE"})
            $plX=[int]($cx-$cw*0.28); $plY=$cy; $crX3=[int]($cx+$cw*0.28); $crY3=$cy
            $tr  = ($t%4.5)/4.5
            $bpX = [int]($plX+($crX3-$plX)*(($t*0.8)%1.0))
            $barW=[int]($cw*0.45); $barX=[int]($cx-$barW/2); $barY=[int]($cy+$ch*0.15)
            $penCo = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb([int](30+$tr*140),$col.R,$col.G,$col.B),[float](1.0+$tr*3.5))
            $penCy = New-Object System.Drawing.Pen($MECH_COL,2)
            $brCy  = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(35,$MECH_COL.R,$MECH_COL.G,$MECH_COL.B))
            $penCl = New-Object System.Drawing.Pen($col,2)
            $brCl  = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(35,$col.R,$col.G,$col.B))
            $brBar = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(200,$col.R,$col.G,$col.B))
            $brBg  = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(30,255,255,255))
            $brTxt = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(140,$col.R,$col.G,$col.B))
            $brCyT = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(160,$MECH_COL.R,$MECH_COL.G,$MECH_COL.B))
            $g.DrawLine($penCo,$plX,$plY,$crX3,$crY3)
            $g.FillEllipse($brCl,($bpX-4),($plY-4),8,8)
            $g.FillEllipse($brCy,($plX-14),($plY-14),28,28);  $g.DrawEllipse($penCy,($plX-14),($plY-14),28,28)
            $g.FillEllipse($brCl,($crX3-14),($crY3-14),28,28); $g.DrawEllipse($penCl,($crX3-14),($crY3-14),28,28)
            $g.FillRectangle($brBg,$barX,$barY,$barW,8)
            $fw=[int]($barW*$tr); if($fw-gt 0){$g.FillRectangle($brBar,$barX,$barY,$fw,8)}
            $tl="TRUST  "+[int]($tr*100)+"%"; $ts=$g.MeasureString($tl,$script:fnt7B)
            $g.DrawString($tl,$script:fnt7B,$brTxt,($cx-$ts.Width/2),($barY+12))
            $s1=$g.MeasureString($pL,$script:fnt7B); $g.DrawString($pL,$script:fnt7B,$brCyT,($plX-$s1.Width/2),($plY-30))
            $s2=$g.MeasureString($cL,$script:fnt7B); $g.DrawString($cL,$script:fnt7B,$brTxt,($crX3-$s2.Width/2),($crY3-30))
            $penCo.Dispose();$penCy.Dispose();$brCy.Dispose();$penCl.Dispose();$brCl.Dispose()
            $brBar.Dispose();$brBg.Dispose();$brTxt.Dispose();$brCyT.Dispose()
        }

        'market_flow' {
            # Economy — all GDI objects created once, reused, disposed at end
            $p    = $script:simParams
            $col  = if($p.color){try{[System.Drawing.ColorTranslator]::FromHtml($p.color)}catch{$AMBER}}else{$AMBER}
            $item = [string]$(if($p.item){$p.item}else{"ITEM"})
            $prce = [string]$(if($p.price){$p.price}else{"50G"})
            $pL   = [string]$(if($p.player){$p.player}else{"PLAYER"})
            $mL   = [string]$(if($p.merchant){$p.merchant}else{"MERCHANT"})
            $plX4=[int]($cx-$cw*0.30); $plY4=$cy; $mrX4=[int]($cx+$cw*0.30); $mrY4=$cy
            $iPh=($t*0.55)%1.0; $gPh=($t*0.55+0.5)%1.0
            $ipx=[int]($mrX4+($plX4-$mrX4)*$iPh); $ipy=[int]($mrY4+[Math]::Sin($iPh*[Math]::PI)*(-32))
            $gpx=[int]($plX4+($mrX4-$plX4)*$gPh); $gpy=[int]($plY4+[Math]::Sin($gPh*[Math]::PI)*(-26))
            $penAm = New-Object System.Drawing.Pen($col,1)
            $brAmD = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(20,$col.R,$col.G,$col.B))
            $brAm  = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(200,$col.R,$col.G,$col.B))
            $penCy = New-Object System.Drawing.Pen($MECH_COL,2)
            $brCy  = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(35,$MECH_COL.R,$MECH_COL.G,$MECH_COL.B))
            $brItm = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(200,$MECH_COL.R,$MECH_COL.G,$MECH_COL.B))
            $brCyT = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(140,$MECH_COL.R,$MECH_COL.G,$MECH_COL.B))
            $g.FillRectangle($brAmD,($mrX4-25),($mrY4-20),50,40); $g.DrawRectangle($penAm,($mrX4-25),($mrY4-20),50,40)
            $g.DrawLine($penAm,($mrX4-30),($mrY4-20),($mrX4+30),($mrY4-20))
            $g.FillRectangle($brItm,($ipx-5),($ipy-5),10,10)
            $g.DrawString($item,$script:fnt7,$brItm,($ipx-10),($ipy-17))
            $g.FillEllipse($brAm,($gpx-5),($gpy-5),10,10)
            if($gPh-gt 0.2-and $gPh-lt 0.8){$g.DrawString($prce,$script:fnt7,$brAm,($gpx-10),($gpy-16))}
            $g.FillEllipse($brCy,($plX4-14),($plY4-14),28,28); $g.DrawEllipse($penCy,($plX4-14),($plY4-14),28,28)
            $s1=$g.MeasureString($pL,$script:fnt7B); $g.DrawString($pL,$script:fnt7B,$brCyT,($plX4-$s1.Width/2),($plY4+18))
            $s2=$g.MeasureString($mL,$script:fnt7B); $g.DrawString($mL,$script:fnt7B,$brAm,($mrX4-$s2.Width/2),($mrY4+26))
            $penAm.Dispose();$brAmD.Dispose();$brAm.Dispose();$penCy.Dispose();$brCy.Dispose();$brItm.Dispose();$brCyT.Dispose()
        }

        'world_discover' {
            # Exploration — shared GDI objects created once outside loop
            $p     = $script:simParams
            $col   = if($p.color){try{[System.Drawing.ColorTranslator]::FromHtml($p.color)}catch{$MECH_COL}}else{$MECH_COL}
            $gcols = if($p.cols){[int]$p.cols}else{5}; $grows=if($p.rows){[int]$p.rows}else{4}
            $numC  = $gcols*$grows
            $cellW = [int]($cw*0.68/$gcols); $cellH=[int]($ch*0.62/$grows)
            $gW    = $gcols*$cellW; $gH=$grows*$cellH
            $gsx   = [int]($cx-$gW/2); $gsy=[int]($cy-$gH/2)
            $rev   = [Math]::Min($numC,($t*0.28)%($numC+2))
            $penGr = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(22,255,255,255),1)
            $brFog = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(18,255,255,255))
            $brRev = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(38,$col.R,$col.G,$col.B))
            $brDot = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(160,$col.R,$col.G,$col.B))
            $brTxt = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(120,$col.R,$col.G,$col.B))
            for ($ci = 0; $ci -lt $numC; $ci++) {
                $gr=[int]($ci/$gcols); $gc=$ci%$gcols
                $cx2=$gsx+$gc*$cellW; $cy2=$gsy+$gr*$cellH
                if ($ci -lt [int]$rev) {
                    $g.FillRectangle($brRev,($cx2+1),($cy2+1),($cellW-2),($cellH-2))
                    $g.FillEllipse($brDot,($cx2+[int]($cellW*0.5)-4),($cy2+[int]($cellH*0.5)-4),8,8)
                } else {
                    $g.FillRectangle($brFog,($cx2+1),($cy2+1),($cellW-2),($cellH-2))
                }
                $g.DrawRectangle($penGr,$cx2,$cy2,$cellW,$cellH)
            }
            $eLbl=[string]$(if($p.label){$p.label}else{"EXPLORE"})
            $esz=$g.MeasureString($eLbl,$script:fnt8B); $g.DrawString($eLbl,$script:fnt8B,$brTxt,($cx-$esz.Width/2),($gsy+$gH+8))
            $penGr.Dispose();$brFog.Dispose();$brRev.Dispose();$brDot.Dispose();$brTxt.Dispose()
        }

        'ranch_build' {
            # Building — shared GDI objects created once outside loops
            $p     = $script:simParams
            $col   = if($p.color){try{[System.Drawing.ColorTranslator]::FromHtml($p.color)}catch{$MECH_COL}}else{$MECH_COL}
            $nEnc  = if($p.enclosures){[int]$p.enclosures}else{3}
            $labels= if($p.labels){$p.labels}else{@()}
            $encW  = [int]($cw*0.18); $encH=[int]($ch*0.26)
            $gap   = [int]($cw*0.06)
            $stX   = [int]($cx-($nEnc*$encW+($nEnc-1)*$gap)/2); $encY=[int]($cy-$encH/2-16)
            $penE  = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(140,$col.R,$col.G,$col.B),1)
            $brE   = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(18,$col.R,$col.G,$col.B))
            $brDot = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(200,$col.R,$col.G,$col.B))
            $brBar = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(180,$col.R,$col.G,$col.B))
            $brBg  = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(25,255,255,255))
            $brTxt = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(140,$col.R,$col.G,$col.B))
            for ($ei = 0; $ei -lt $nEnc; $ei++) {
                $ex = $stX+$ei*($encW+$gap)
                $g.FillRectangle($brE,$ex,$encY,$encW,$encH); $g.DrawRectangle($penE,$ex,$encY,$encW,$encH)
                $nD = [int]((($t*0.25+$ei*0.55)%1.0)*9)+1
                for ($di = 0; $di -lt [Math]::Min($nD,9); $di++) {
                    $dcx=$ex+10+($di%3)*[int](($encW-20)/3)
                    $dcy=$encY+12+[int]($di/3)*[int](($encH-24)/3)
                    $g.FillEllipse($brDot,($dcx-4),($dcy-4),9,9)
                }
                $upY=[int]($encY+$encH+6); $upF=[int]($encW*(($t*0.18+$ei*0.88)%1.0))
                $g.FillRectangle($brBg,$ex,$upY,$encW,7)
                if($upF-gt 0){$g.FillRectangle($brBar,$ex,$upY,$upF,7)}
                $lbl=[string]$(if($ei-lt $labels.Count){$labels[$ei]}else{"PEN "+[string][char](65+$ei)})
                $lsz=$g.MeasureString($lbl,$script:fnt7B); $g.DrawString($lbl,$script:fnt7B,$brTxt,($ex+$encW/2-$lsz.Width/2),($upY+10))
            }
            $penE.Dispose();$brE.Dispose();$brDot.Dispose();$brBar.Dispose();$brBg.Dispose();$brTxt.Dispose()
        }

        'garden_cycle' {
            # Plants — shared GDI objects created once outside plant loop
            $p     = $script:simParams
            $col   = if($p.color){try{[System.Drawing.ColorTranslator]::FromHtml($p.color)}catch{$GREEN}}else{$GREEN}
            $nP    = if($p.count){[int]$p.count}else{5}
            $per   = if($p.period){[double]$p.period}else{3.8}
            $labels= if($p.labels){$p.labels}else{@()}
            $gY    = [int]($cy+$ch*0.12)
            $totW  = [int]($cw*0.72); $spc=[int]($totW/[Math]::Max($nP,2))
            $stX   = [int]($cx-$totW/2+$spc/2)
            $penSt = New-Object System.Drawing.Pen($col,2)
            $brLf  = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(160,$col.R,$col.G,$col.B))
            $brFl  = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(230,$META_COL.R,$META_COL.G,$META_COL.B))
            $brTxt = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(100,$col.R,$col.G,$col.B))
            $penGl = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(30,255,255,255),1)
            $g.DrawLine($penGl,($cx-$totW/2),$gY,($cx+$totW/2),$gY)
            for ($pi = 0; $pi -lt $nP; $pi++) {
                $px = $stX+$pi*$spc
                $ph = (($t/$per+$pi*0.22)%1.0)
                if ($ph -lt 0.25) {
                    $stH=[int](($ph/0.25)*18)
                    $g.DrawLine($penSt,$px,$gY,$px,($gY-$stH))
                    if($stH-gt 3){$g.FillEllipse($brLf,($px-4),($gY-$stH-4),8,8)}
                } elseif ($ph -lt 0.60) {
                    $stH=[int](18+(($ph-0.25)/0.35)*22); $lfW=[int]((($ph-0.25)/0.35)*12)
                    $g.DrawLine($penSt,$px,$gY,$px,($gY-$stH))
                    if($lfW-gt 2){$g.FillEllipse($brLf,($px-$lfW-4),($gY-$stH/2-5),$lfW,8);$g.FillEllipse($brLf,($px+4),($gY-$stH/2-5),$lfW,8)}
                    $g.FillEllipse($brLf,($px-5),($gY-$stH-5),10,10)
                } elseif ($ph -lt 0.84) {
                    $g.DrawLine($penSt,$px,$gY,$px,($gY-40))
                    $g.FillEllipse($brLf,($px-18),($gY-26),14,10);$g.FillEllipse($brLf,($px+4),($gY-26),14,10)
                    $g.FillEllipse($brFl,($px-7),($gY-47),14,14)
                } else {
                    $g.DrawLine($penSt,$px,$gY,$px,($gY-44))
                    $g.FillEllipse($brFl,($px-9),($gY-53),18,18)
                }
                if($pi-lt $labels.Count){$sz=$g.MeasureString([string]$labels[$pi],$script:fnt7);$g.DrawString([string]$labels[$pi],$script:fnt7,$brTxt,($px-$sz.Width/2),($gY+6))}
            }
            $penSt.Dispose();$brLf.Dispose();$brFl.Dispose();$brTxt.Dispose();$penGl.Dispose()
        }

        'season_turn' {
            # Seasons — two shared pen/brush sets (active vs dim) created before loop
            $p      = $script:simParams
            $labels = if($p.labels){$p.labels}else{@("SPRING","SUMMER","AUTUMN","WINTER")}
            $sCol   = @($GREEN,$META_COL,$AMBER,$MECH_COL)
            $seaPh  = ($t*0.12)%4.0; $act=[int]$seaPh
            $pad    = 6; $qW=[int](($cw-$pad*3)/2); $qH=[int](($ch-$pad*3)/2)
            $actC   = $sCol[$act]
            $penDim = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(40,255,255,255),1)
            $brDim  = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(10,255,255,255))
            $brTDim = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(60,255,255,255))
            $penAct = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(210,$actC.R,$actC.G,$actC.B),2)
            $brAct  = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb([int](38+18*[Math]::Sin($t*1.5)),$actC.R,$actC.G,$actC.B))
            $brTAct = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(220,$actC.R,$actC.G,$actC.B))
            $brDot  = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(220,$actC.R,$actC.G,$actC.B))
            for ($si = 0; $si -lt 4; $si++) {
                if($si-eq 0){$qx=$pad;$qy=$pad}
                elseif($si-eq 1){$qx=$pad*2+$qW;$qy=$pad}
                elseif($si-eq 2){$qx=$pad*2+$qW;$qy=$pad*2+$qH}
                else{$qx=$pad;$qy=$pad*2+$qH}
                $isA=($si-eq $act)
                if($isA){$g.FillRectangle($brAct,$qx,$qy,$qW,$qH);$g.DrawRectangle($penAct,$qx,$qy,$qW,$qH)}
                else    {$g.FillRectangle($brDim,$qx,$qy,$qW,$qH);$g.DrawRectangle($penDim,$qx,$qy,$qW,$qH)}
                $lbl=[string]$(if($si-lt $labels.Count){$labels[$si]}else{""})
                $sz=$g.MeasureString($lbl,$script:fnt8B)
                if($isA){$g.DrawString($lbl,$script:fnt8B,$brTAct,($qx+$qW/2-$sz.Width/2),($qy+$qH/2-$sz.Height/2))}
                else    {$g.DrawString($lbl,$script:fnt8B,$brTDim,($qx+$qW/2-$sz.Width/2),($qy+$qH/2-$sz.Height/2))}
            }
            # Migration dot from active to next (clockwise)
            $nxt=($act+1)%4
            if($act-eq 0){$fx=$pad+$qW/2;$fy=$pad+$qH/2}elseif($act-eq 1){$fx=$pad*2+$qW+$qW/2;$fy=$pad+$qH/2}elseif($act-eq 2){$fx=$pad*2+$qW+$qW/2;$fy=$pad*2+$qH+$qH/2}else{$fx=$pad+$qW/2;$fy=$pad*2+$qH+$qH/2}
            if($nxt-eq 0){$tx=$pad+$qW/2;$ty=$pad+$qH/2}elseif($nxt-eq 1){$tx=$pad*2+$qW+$qW/2;$ty=$pad+$qH/2}elseif($nxt-eq 2){$tx=$pad*2+$qW+$qW/2;$ty=$pad*2+$qH+$qH/2}else{$tx=$pad+$qW/2;$ty=$pad*2+$qH+$qH/2}
            $ph=($t*0.5)%1.0; $mpx=[int]($fx+($tx-$fx)*$ph); $mpy=[int]($fy+($ty-$fy)*$ph)
            $g.DrawLine($penAct,[int]$fx,[int]$fy,[int]$tx,[int]$ty)
            $g.FillEllipse($brDot,($mpx-5),($mpy-5),10,10)
            $penDim.Dispose();$brDim.Dispose();$brTDim.Dispose();$penAct.Dispose();$brAct.Dispose();$brTAct.Dispose();$brDot.Dispose()
        }

        default {
            $r2  = [int](12 + [Math]::Sin($t)*4)
            $p3  = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(60,0,180,255),1)
            $g.DrawEllipse($p3,($cx-$r2),($cy-$r2),$r2*2,$r2*2); $p3.Dispose()
        }
    }

    $old = $canvas.Image
    $canvas.Image = $bmp
    $g.Dispose()
    if ($old) { $old.Dispose() }
}

# ── State poll ────────────────────────────────────────────────────────────────
$stateTimer = New-Object System.Windows.Forms.Timer
$stateTimer.Interval = 300
$stateTimer.Add_Tick({
    # Show monitor warning if a node has been waiting >10s with no proposal
    if ($script:nodeSelectedAt -ne [datetime]::MinValue -and
        -not $script:currentTitle -and
        ([datetime]::UtcNow - $script:nodeSelectedAt).TotalSeconds -gt 10) {
        $descBox.ForeColor = $AMBER
        $descBox.Text = "Monitor not running.`n`nTell Claude: `"start the ValenTech Anvil monitor`""
        $script:nodeSelectedAt = [datetime]::MinValue
    }

    # Timeout recovery: if Claude never calls generate_chassis.ps1 -Finalize
    # (e.g. it hit a `denied:` on the first file and stopped, or crashed),
    # chassis_path never gets set and the completion check below never fires —
    # leaving GENERATE permanently stuck on "GENERATING..." with no escape but
    # a full app relaunch. This check runs every tick (not gated on state.json
    # changing) since a stuck Claude may never write to state.json again.
    if ($btnChassis.Text -eq 'GENERATING...' -and $script:pendingGenerateTs -ne 0 -and
        ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - $script:pendingGenerateTs) -gt 300000) {
        $script:lastGenerateTs    = $script:pendingGenerateTs
        $script:pendingGenerateTs = 0
        $btnChassis.Text = 'GENERATE'
        Update-ChassisButton
        [System.Windows.Forms.MessageBox]::Show(
            "Chassis generation timed out after 5 minutes with no response.`n`nCheck Claude's output for errors, then try GENERATE again.",
            "ValenTech", 'OK', 'Warning') | Out-Null
        $descBox.ForeColor = $TEXT_MID
        $descBox.Text = "Chassis generation timed out.`n`nSelect a concept node to continue."
    }

    # Skip if state.json hasn't changed since last read
    $fi = Get-Item $STATE -ErrorAction SilentlyContinue
    if (-not $fi -or $fi.LastWriteTime -le $script:stateLastWrite) { return }
    $script:stateLastWrite = $fi.LastWriteTime
    $obj = Read-State; if (-not $obj) { return }
    $resp    = [string]$obj.response
    $title   = [string]$obj.title
    $content = [string]$obj.content
    $chassisPath = [string]$obj.chassis_path
    $genTs   = [int64]0
    [int64]::TryParse([string]$obj.generate_ts, [ref]$genTs) | Out-Null

    # Detect completion via generate_ts (set at GENERATE-click time, see the
    # btnChassis click handler) combined with chassis_path (written only by
    # generate_chassis.ps1's -Finalize call). Regenerating into the SAME folder
    # produces an identical chassis_path, so comparing generate_ts (not the path)
    # ensures the button reliably leaves "GENERATING..." and the folder reopens
    # on a regenerate.
    if ($chassisPath -and $genTs -ne 0 -and $genTs -ne $script:lastGenerateTs) {
        $script:lastGenerateTs    = $genTs
        $script:pendingGenerateTs = 0
        $btnChassis.Text      = 'GENERATE'
        Update-ChassisButton
        [System.Windows.Forms.MessageBox]::Show(
            "Chassis generated in:`n$chassisPath`n`nOpening now...", "ValenTech", 'OK', 'Information') | Out-Null
        Start-Process explorer.exe $chassisPath
        $descBox.ForeColor = $TEXT_MID
        $descBox.Text = "Chassis generated in:`n$chassisPath`n`nSelect a concept node to continue."
    }

    # Sync diff ready - show diff modal
    $syncDiffTs = [int64]0
    [int64]::TryParse([string]$obj.sync_diff_ts, [ref]$syncDiffTs) | Out-Null
    if ($syncDiffTs -ne 0 -and $syncDiffTs -ne $script:lastSyncDiffTs -and $obj.sync_diff) {
        $script:lastSyncDiffTs = $syncDiffTs
        Show-SyncDiffModal $obj.sync_diff ([string]$obj.sync_path)
    }

    # Re-import data ready - show confirmation
    $reimportDataTs = [int64]0
    [int64]::TryParse([string]$obj.reimport_data_ts, [ref]$reimportDataTs) | Out-Null
    if ($reimportDataTs -ne 0 -and $reimportDataTs -ne $script:lastReimportDataTs -and $obj.reimport_data) {
        $script:lastReimportDataTs = $reimportDataTs
        Show-ReimportConfirm $obj.reimport_data
    }

    # GDD export done - notify
    $gddExportDoneTs = [int64]0
    [int64]::TryParse([string]$obj.gdd_export_done_ts, [ref]$gddExportDoneTs) | Out-Null
    if ($gddExportDoneTs -ne 0 -and $gddExportDoneTs -ne $script:lastGddExportTs) {
        $script:lastGddExportTs = $gddExportDoneTs
        $exportPath = [string]$obj.gdd_export_path
        [System.Windows.Forms.MessageBox]::Show(
            "GDD document saved to:`n$exportPath`n`nOpening now...",
            "ValenTech", 'OK', 'Information') | Out-Null
        try { Start-Process $exportPath } catch {}
    }

    # FIX (stale-proposal / wrong-node attribution race): propose_one.ps1 writes
    # `selected_node = $NodeId` from Claude's (possibly stale) read — if the user
    # clicked a different node while Claude was generating, that overwrite can
    # leave selected_node pointing at the OLD node while request/request_ts
    # already reflect the NEW selection (propose_one.ps1 never touches those).
    # get_decision.ps1 self-corrects for Claude via request_ts, but nothing here
    # verified the incoming proposal actually belongs to the node the user is
    # currently looking at — so a stale proposal could be displayed AND, if
    # confirmed, saved under $script:currentNode (the new node), mis-attributing
    # the feature to the wrong system. Require selected_node to match before
    # ever showing/accepting a proposal.
    $propNode = [string]$obj.selected_node
    if ($title -and $resp -eq '' -and $propNode -eq $script:currentNode -and
        ($title -ne $script:currentTitle -or $content -ne $script:currentContent)) {
        $script:currentTitle   = $title
        $script:currentContent = $content
        # sim is stored as a proper JSON object — parse directly
        try {
            $simObj    = $obj.sim
            # FIX (dead code / doc drift): this whitelist must mirror exactly the
            # 12 types in CLAUDE.md's "Sim type guide" table (the only menu Claude
            # picks -Sim from) AND the Draw-Sim switch cases below. It previously
            # also listed economy_flow/dna_helix/particle_swarm/network/grid_world —
            # five abstract-diagram sim types that commit 10d6ad7 deliberately
            # retired in favour of "game-preview" replacements covering the same
            # GDD categories (dna_helix->gene_pool, particle_swarm->creature_chase,
            # network->bond_grow/market_flow, grid_world->ranch_build/world_discover,
            # economy_flow->market_flow). Their Draw-Sim cases were dead — Claude can
            # never propose a type CLAUDE.md doesn't mention, and nothing else ever
            # sets $script:simType dynamically (grep confirms). Removed both the
            # whitelist entries and their ~215 lines of unreachable case bodies.
            # Order below now matches CLAUDE.md's table top-to-bottom for easy diffing.
            $validSims = @('creature_chase','gene_pool','bond_grow','market_flow',
                           'world_discover','ranch_build','garden_cycle','season_turn',
                           'progression_curve','stat_radar','loop_diagram','feature_tree')
            if ($simObj -and $simObj.type -and $validSims -contains $simObj.type) {
                $params = @{}
                $simObj.PSObject.Properties | Where-Object { $_.Name -ne 'type' } | ForEach-Object { $params[$_.Name] = $_.Value }
                Start-SimType $simObj.type $params
            } else { Start-SimType 'waiting_pulse' @{} }
        } catch { Start-SimType 'waiting_pulse' @{} }

        # Build checklist
        $script:nodeSelectedAt = [datetime]::MinValue
        $propTitleL.Text   = $title
        $propDescL.ForeColor = $TEXT_MID
        $propDescL.Text    = $content
        $checkPanel.Controls.Clear()
        $script:checkboxes.Clear()
        $comps = @($obj.components)
        if ($comps -and $comps.Count -gt 0) {
            $cy = 0; $i = 0
            foreach ($comp in $comps) {
                $cb = New-Object System.Windows.Forms.CheckBox
                $cb.Text      = [string]$comp
                $cb.Font      = New-Object System.Drawing.Font('Consolas', 9)
                $cb.ForeColor = $TEXT_HI
                $cb.BackColor = $CARD_BG
                $cb.AutoSize  = $false
                $cb.SetBounds(0, $cy, $checkPanel.Width, 26)
                $cb.Checked   = $true
                $cb.Tag       = $i  # index into component_data metadata array
                $checkPanel.Controls.Add($cb)
                $script:checkboxes.Add($cb)
                $cy += 28; $i++
            }
            $checkPanel.Height = $cy
            $moreLabel.Visible = ($cy -gt $checkOuter.Height)
        } else {
            $checkPanel.Height = 0
            $moreLabel.Visible = $false
        }
        Set-Buttons-Waiting
    }
})
$stateTimer.Start()

# ── Anim timer ────────────────────────────────────────────────────────────────
$animTimer = New-Object System.Windows.Forms.Timer
$animTimer.Interval = 33
$animTimer.Add_Tick({ $script:simTick++; Draw-Sim })
$animTimer.Start()

# ── Cleanup ───────────────────────────────────────────────────────────────────
$form.Add_FormClosing({
    $animTimer.Stop(); $stateTimer.Stop()
    Save-SimIssues
    $script:fnt7B.Dispose(); $script:fnt7.Dispose()
    $script:fnt8B.Dispose(); $script:fnt8.Dispose()
    $script:fnt11.Dispose()
    if (Test-Path $PID_F) { Remove-Item $PID_F -Force -ErrorAction SilentlyContinue }
})

$form.Add_Shown({ $form.Activate(); Relayout; Start-SimType 'waiting_pulse' @{} })
[System.Windows.Forms.Application]::Run($form)
