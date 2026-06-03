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
$script:lastFrameworkPath  = ""
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
    $b.Add_MouseEnter({ $b.ForeColor = $hf; $b.BackColor = $hbk })
    $b.Add_MouseLeave({ $b.ForeColor = $TEXT_DIM; $b.BackColor = $BAR_BG })
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

# Add label LAST so it renders behind buttons (lower z-order = higher Controls index)
$titleBar.Controls.AddRange(@($btnMin, $btnClose, $btnSave, $btnLoad))
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
$btnBar.Height    = 72
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

$btnConfirm   = Make-Btn 'CONFIRM'     $GREEN
$btnReroll    = Make-Btn 'REROLL'      $AMBER
$btnEnd       = Make-Btn 'END SESSION' $RED_COL
$btnSimReport = Make-Btn 'SIM REPORT'  $TEXT_MID 170 44

# FRAMEWORK is the primary CTA — white fill, black text (Starlink "Get Started" style)
$btnFramework = New-Object System.Windows.Forms.Button
$btnFramework.Text = 'GENERATE'
$btnFramework.Font = New-Object System.Drawing.Font('Consolas', 10, [System.Drawing.FontStyle]::Bold)
$btnFramework.FlatStyle = 'Flat'
$btnFramework.FlatAppearance.BorderSize  = 0
$btnFramework.BackColor = $TEXT_HI
$btnFramework.ForeColor = $BG
$btnFramework.Size      = New-Object System.Drawing.Size(170, 44)
$btnFramework.Cursor    = 'Hand'
$btnFramework.Enabled   = $false
$btnConfirm.Location   = New-Object System.Drawing.Point( 24, 14)
$btnReroll.Location    = New-Object System.Drawing.Point(230, 14)
$btnEnd.Location       = New-Object System.Drawing.Point(436, 14)
$btnSimReport.Location = New-Object System.Drawing.Point(642, 14)
$btnFramework.Location = New-Object System.Drawing.Point(828, 14)
$btnBar.Controls.AddRange(@($btnConfirm, $btnReroll, $btnEnd, $btnSimReport, $btnFramework))

$legendL = New-Object System.Windows.Forms.Label
$legendL.Text      = 'Right-click to edit/delete  |  F11  ESC'
$legendL.Font      = New-Object System.Drawing.Font('Consolas', 8)
$legendL.ForeColor = $TEXT_DIM
$legendL.AutoSize  = $true
$legendL.Anchor   = [System.Windows.Forms.AnchorStyles]'Right,Top'
$legendL.Location = New-Object System.Drawing.Point(1060, 28)
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
    if ($_.KeyCode -eq 'Escape' -or ($_.Alt -and $_.KeyCode -eq 'F4')) { $form.Close() }
    if ($_.KeyCode -eq 'F11') { Toggle-Fullscreen; $_.SuppressKeyPress = $true }
})

# ── State helpers ─────────────────────────────────────────────────────────────
function Read-State {
    # Returns a PSCustomObject or $null. Handles concurrent writes gracefully.
    $raw = Get-Content $STATE -Raw -ErrorAction SilentlyContinue
    if (-not $raw -or $raw.Trim() -eq '') { return $null }
    try { return $raw | ConvertFrom-Json } catch { return $null }
}

function Write-StateFields([hashtable]$fields) {
    # Atomic field update: parse → patch → re-serialise. Eliminates all manual regex-replace.
    $obj = Read-State; if (-not $obj) { return }
    foreach ($k in $fields.Keys) { $obj.$k = $fields[$k] }
    try { Set-Content $STATE ($obj | ConvertTo-Json -Compress -Depth 6) -NoNewline -Encoding UTF8 } catch {}
}

function Write-Response([string]$val) {
    Write-StateFields @{ response = $val }
}

function Save-SimIssues {
    if ($script:simIssues.Count -eq 0) { return }
    $script:simIssues | ConvertTo-Json -Compress | Set-Content $SIM_ISSUES_F -NoNewline
}

function Update-FrameworkButton {
    $btnFramework.Enabled = [bool]($script:sections | Where-Object { $_.features.Count -gt 0 })
}

function Set-Buttons-Waiting {
    $btnConfirm.Enabled   = $true
    $btnReroll.Enabled    = $true
    $btnEnd.Enabled       = $true
    $btnSimReport.Enabled = ($script:simType -ne 'waiting_pulse')
}
function Set-Buttons-Idle {
    $btnConfirm.Enabled   = $false
    $btnReroll.Enabled    = $false
    $btnEnd.Enabled       = $false
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
            foreach ($cb in $checkedItems) {
                $fid = [System.Guid]::NewGuid().ToString('N').Substring(0, 8)
                $sec.features.Add(@{ id=$fid; label=$cb.Text; desc=$script:currentContent; sectionId=$sec.id })
            }
        } else {
            $fid = [System.Guid]::NewGuid().ToString('N').Substring(0, 8)
            $sec.features.Add(@{ id=$fid; label=$script:currentTitle; desc=$script:currentContent; sectionId=$sec.id })
        }
        Save-Features; Rebuild-NodeList; Update-FrameworkButton
    }
})
$btnReroll.Add_Click({ Write-Response "reroll"; Set-Buttons-Idle })
$btnEnd.Add_Click({ Write-Response "deny"; Set-Buttons-Idle; $form.Close() })
$btnSimReport.Add_Click({
    $script:simIssues.Add("sim=$($script:simType) node=$($script:currentNode) title=$($script:currentTitle)")
    Save-SimIssues
    Write-StateFields @{ sim_issues_ts = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() }
    $btnSimReport.Enabled = $false
    [System.Windows.Forms.MessageBox]::Show("Sim issue logged.", "ValenTech", 'OK', 'Information') | Out-Null
})

$btnFramework.Add_Click({
    $btnFramework.Enabled = $false
    $btnFramework.Text = 'GENERATING...'

    $descBox.Text = "Generating framework...`n`nThis may take a moment."
    Write-StateFields @{
        generate_ts  = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        gdd_filename = $script:gddFileName
    }
})

# ── File browser ──────────────────────────────────────────────────────────────
function Read-GDDFile([string]$path) {
    $ext = [System.IO.Path]::GetExtension($path).ToLower()
    if ($ext -eq '.pdf') {
        $pdftotext = "C:\Program Files\Git\mingw64\bin\pdftotext.exe"
        if (-not (Test-Path $pdftotext)) { throw "pdftotext not found. Save the GDD as .txt first." }
        $tmp = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), [System.Guid]::NewGuid().ToString('N') + '.txt')
        try {
            & $pdftotext -layout $path $tmp 2>$null
            if (-not (Test-Path $tmp)) { throw "PDF extraction failed." }
            return [System.IO.File]::ReadAllText($tmp)
        } finally {
            if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
        }
    }
    return [System.IO.File]::ReadAllText($path)
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

$script:sections = [System.Collections.Generic.List[hashtable]]::new()

# ── Feature persistence ───────────────────────────────────────────────────────
function Save-Features {
    $obj = @{}
    foreach ($sec in $script:sections) {
        if ($sec.features.Count -gt 0) {
            $obj[$sec.label] = @($sec.features | ForEach-Object {
                @{ title=$_.label; desc=[string]$_.desc }
            })
        }
    }
    $json = ConvertTo-Json $obj -Depth 4 -Compress
    Set-Content $FEATURES_F $json -NoNewline
}

function Load-Features {
    # Only used internally during Parse-GDD to restore session cache — NOT called on startup
    if (-not (Test-Path $FEATURES_F)) { return }
    $raw = Get-Content $FEATURES_F -Raw -ErrorAction SilentlyContinue
    if (-not $raw) { return }
    try {
        $obj = $raw | ConvertFrom-Json
        foreach ($prop in $obj.PSObject.Properties) {
            $sec = $script:sections | Where-Object { $_.label -eq $prop.Name } | Select-Object -First 1
            if ($sec) {
                foreach ($item in $prop.Value) {
                    $fid = [System.Guid]::NewGuid().ToString('N').Substring(0,8)
                    if ($item -is [string]) {
                        $sec.features.Add(@{ id=$fid; label=$item; desc=""; sectionId=$sec.id })
                    } else {
                        $sec.features.Add(@{ id=$fid; label=$item.title; desc=$item.desc; sectionId=$sec.id })
                    }
                }
            }
        }
        Update-FrameworkButton
    } catch {}
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
        version     = 1
        projectName = $projectName
        gddFilename = $script:gddFileName
        sections    = @($script:sections | ForEach-Object {
            @{ label=$_.label; category=$_.category; features=@($_.features | ForEach-Object { @{ title=$_.label; desc=$_.desc } }) }
        })
        savedAt     = [DateTime]::UtcNow.ToString('o')
    }
    $data | ConvertTo-Json -Depth 6 -Compress | Set-Content $saveFile -Encoding UTF8
    [System.Windows.Forms.MessageBox]::Show("Saved to:`n$saveFile", "ValenTech", 'OK', 'Information') | Out-Null
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
        $script:gddFileName = $data.gddFilename
        $fileLabel.Text = $data.gddFilename; $fileLabel.ForeColor = $TEXT_MID
        $script:sections.Clear(); $nodeFlow.Controls.Clear()
        foreach ($sec in $data.sections) {
            $cat = if ($sec.category) { $sec.category } else { Get-SystemCategory $sec.label }
            $col = Get-CategoryColor $cat
            $secObj = @{
                id = 'sys_' + [System.Guid]::NewGuid().ToString('N').Substring(0,6)
                label = $sec.label; color = $col; category = $cat
                features = [System.Collections.Generic.List[hashtable]]::new()
                collapsed = $false
            }
            foreach ($feat in $sec.features) {
                $fid = [System.Guid]::NewGuid().ToString('N').Substring(0,8)
                $secObj.features.Add(@{ id=$fid; label=$feat.title; desc=$feat.desc; sectionId=$secObj.id })
            }
            $script:sections.Add($secObj)
        }
        Save-Features
        Rebuild-NodeList
        Update-FrameworkButton
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

    Write-StateFields @{ gdd_raw = $raw }

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

        if ($candidate -match '[^\x00-\x7F]') { continue }
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
            if ($bl.Length -gt 5 -and $bl -notmatch '^[#\d]' -and $bl -notmatch '[^\x00-\x7F]') { $bl }
        }
        $excerpt = (($parts -join ' ') -replace '\s+', ' ').Trim()
        if ($excerpt.Length -gt 600) { $excerpt = $excerpt.Substring(0, 600) }
        $headings[$hi].excerpt = $excerpt
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
        })
    }

    # Sort sections by category in rainbow order
    $sortOrder = @{ combat=0; economy=1; progress=2; plant=3; both=4; explore=5; animal=6; social=7; building=8; ui=9; default=10 }
    $sorted = $script:sections | Sort-Object { $sortOrder[$_.category] }
    $script:sections.Clear()
    foreach ($s in $sorted) { $script:sections.Add($s) }

    Rebuild-NodeList

    $nodesArr = @($script:sections | ForEach-Object {
        @{ id=$_.id; label=$_.label; type='system'; confirmed=$false; sectionId=$_.id }
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
    Write-StateFields @{
        request       = $n.label
        request_ts    = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        selected_node = $n.id
        response      = ''
        gdd_section   = if ($sec -and $sec.excerpt) { $sec.excerpt } else { '' }
    }

    $secLabel = if ($n.sectionId) { ($script:sections | Where-Object { $_.id -eq $n.sectionId } | Select-Object -First 1).label } else { '' }
    $descBox.Text = $(if ($secLabel) { "[ $secLabel ]" } else { "" }) + "  " + $n.label + "`n`nWaiting for proposals..."
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
            if ($gw -le 0 -or $gh -le 0) { $g.Dispose(); return }

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

        'economy_flow' {
            $p      = $script:simParams
            $srcs   = if ($p.sources) { $p.sources } else { @("QUEST","LOOT","CRAFT") }
            $snks   = if ($p.sinks)   { $p.sinks }   else { @("UPGRADE","BUILD","TRADE") }
            $col    = if ($p.color)   { try { [System.Drawing.ColorTranslator]::FromHtml($p.color) } catch { $AMBER } } else { $AMBER }
            $srcX   = [int]($cw*0.2); $snkX=[int]($cw*0.8)
            $bW=70; $bH=26; $pulseT=($t*0.5)%1.0

            $sb  = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(30,0,200,255))
            $sp  = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(180,0,200,255),1)
            $sbr = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(200,0,200,255))
            $lp  = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(40,0,200,255),1)
            $pbr = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(200,0,255,200))
            for ($si=0;$si-lt $srcs.Count;$si++) {
                $sy=[int]($cy-($srcs.Count-1)*30+$si*60)
                $g.FillRectangle($sb,($srcX-$bW/2),($sy-$bH/2),$bW,$bH)
                $g.DrawRectangle($sp,($srcX-$bW/2),($sy-$bH/2),$bW,$bH)
                $ssz=$g.MeasureString($srcs[$si],$script:fnt7B)
                $g.DrawString($srcs[$si],$script:fnt7B,$sbr,($srcX-$ssz.Width/2),($sy-$ssz.Height/2))
                $g.DrawLine($lp,($srcX+$bW/2),$sy,$cx,$cy)
                $px2=[int](($srcX+$bW/2)+($cx-$srcX-$bW/2)*$pulseT)
                $py2=[int]($sy+($cy-$sy)*$pulseT)
                $g.FillEllipse($pbr,($px2-4),($py2-4),8,8)
            }
            $sb.Dispose();$sp.Dispose();$sbr.Dispose();$lp.Dispose();$pbr.Dispose()

            $hb=New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(40,$col.R,$col.G,$col.B))
            $g.FillEllipse($hb,($cx-22),($cy-22),44,44); $hb.Dispose()
            $hp=New-Object System.Drawing.Pen($col,2)
            $g.DrawEllipse($hp,($cx-22),($cy-22),44,44); $hp.Dispose()
            $hbr = New-Object System.Drawing.SolidBrush($col)
            $g.DrawString("HUB",$script:fnt7B,$hbr,($cx-14),($cy-7)); $hbr.Dispose()

            $kb   = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(30,180,0,255))
            $kp   = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(180,180,0,255),1)
            $kbr  = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(200,180,0,255))
            $lp2  = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(40,180,0,255),1)
            $pbr3 = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(200,255,180,0))
            for ($ki=0;$ki-lt $snks.Count;$ki++) {
                $ky=[int]($cy-($snks.Count-1)*30+$ki*60)
                $g.FillRectangle($kb,($snkX-$bW/2),($ky-$bH/2),$bW,$bH)
                $g.DrawRectangle($kp,($snkX-$bW/2),($ky-$bH/2),$bW,$bH)
                $ksz=$g.MeasureString($snks[$ki],$script:fnt7B)
                $g.DrawString($snks[$ki],$script:fnt7B,$kbr,($snkX-$ksz.Width/2),($ky-$ksz.Height/2))
                $g.DrawLine($lp2,$cx,$cy,($snkX-$bW/2),$ky)
                $px3=[int]($cx+($snkX-$bW/2-$cx)*$pulseT)
                $py3=[int]($cy+($ky-$cy)*$pulseT)
                $g.FillEllipse($pbr3,($px3-4),($py3-4),8,8)
            }
            $kb.Dispose();$kp.Dispose();$kbr.Dispose();$lp2.Dispose();$pbr3.Dispose()
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

        'dna_helix' {
            # Double helix — genetics, breeding, biology
            $p    = $script:simParams
            $spd  = if ($p.speed)  { [double]$p.speed  } else { 0.8 }
            $col1 = if ($p.color1) { try { [System.Drawing.ColorTranslator]::FromHtml($p.color1) } catch { $MECH_COL } } else { $MECH_COL }
            $col2 = if ($p.color2) { try { [System.Drawing.ColorTranslator]::FromHtml($p.color2) } catch { $LOOP_COL } } else { $LOOP_COL }
            $helixR = [int]([Math]::Min($cw,$ch) * 0.11)
            $helixH = [int]($ch * 0.72)
            $sy2    = [int](($ch - $helixH) / 2)
            $steps2 = 80
            $pts1 = [System.Collections.Generic.List[System.Drawing.Point]]::new()
            $pts2 = [System.Collections.Generic.List[System.Drawing.Point]]::new()
            for ($si = 0; $si -le $steps2; $si++) {
                $prog2 = $si / $steps2
                $y2    = $sy2 + [int]($prog2 * $helixH)
                $ph2   = $prog2 * [Math]::PI * 3 + $t * $spd
                $pts1.Add([System.Drawing.Point]::new($cx + [int]($helixR * [Math]::Sin($ph2)),                    $y2))
                $pts2.Add([System.Drawing.Point]::new($cx + [int]($helixR * [Math]::Sin($ph2 + [Math]::PI)), $y2))
            }
            $pen1 = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(200,$col1.R,$col1.G,$col1.B),2)
            $pen2 = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(200,$col2.R,$col2.G,$col2.B),2)
            $g.DrawLines($pen1,$pts1.ToArray()); $g.DrawLines($pen2,$pts2.ToArray())
            $pen1.Dispose(); $pen2.Dispose()
            $numRungs2 = 10
            for ($ri = 0; $ri -le $numRungs2; $ri++) {
                $prog2 = $ri / $numRungs2
                $y2    = $sy2 + [int]($prog2 * $helixH)
                $ph2   = $prog2 * [Math]::PI * 3 + $t * $spd
                $rx1   = $cx + [int]($helixR * [Math]::Sin($ph2))
                $rx2   = $cx + [int]($helixR * [Math]::Sin($ph2 + [Math]::PI))
                $depth = [Math]::Sin($ph2)
                $ralpha= [int](80 + 80 * (($depth + 1) / 2))
                $rp2   = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb($ralpha,150,150,150),1)
                $g.DrawLine($rp2,$rx1,$y2,$rx2,$y2); $rp2.Dispose()
                $nr2   = if ($depth -gt 0) { 6 } else { 4 }
                $rb1   = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb($ralpha+55,$col1.R,$col1.G,$col1.B))
                $rb2   = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb($ralpha+55,$col2.R,$col2.G,$col2.B))
                $g.FillEllipse($rb1,($rx1-$nr2),($y2-$nr2),$nr2*2,$nr2*2)
                $g.FillEllipse($rb2,($rx2-$nr2),($y2-$nr2),$nr2*2,$nr2*2)
                $rb1.Dispose(); $rb2.Dispose()
            }
        }

        'particle_swarm' {
            # Particle swarm — catching, creature AI, movement, exploration
            $p     = $script:simParams
            $mode  = if ($p.mode)  { $p.mode  } else { 'orbit' }
            $cnt   = if ($p.count) { [int]$p.count } else { 18 }
            $col   = if ($p.color) { try { [System.Drawing.ColorTranslator]::FromHtml($p.color) } catch { $LOOP_COL } } else { $LOOP_COL }
            $baseR = [int]([Math]::Min($cw,$ch) * 0.26)
            $cb2   = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(200,$col.R,$col.G,$col.B))
            $g.FillEllipse($cb2,($cx-5),($cy-5),10,10); $cb2.Dispose()
            $cp2   = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(60,$col.R,$col.G,$col.B),1)
            $g.DrawEllipse($cp2,($cx-$baseR),($cy-$baseR),$baseR*2,$baseR*2); $cp2.Dispose()
            for ($pi = 0; $pi -lt $cnt; $pi++) {
                $base2 = 2 * [Math]::PI * $pi / $cnt
                $freq2 = 0.25 + ($pi % 5) * 0.08
                switch ($mode) {
                    'flee' {
                        $r3   = $baseR * (0.5 + [Math]::Abs([Math]::Sin($t * $freq2 + $base2 * 1.3)) * 0.7)
                        $ang3 = $base2 + [Math]::Sin($t * $freq2 * 0.4) * 0.6
                    }
                    'seek' {
                        $r3   = $baseR * (0.15 + [Math]::Abs([Math]::Sin($t * $freq2 * 1.2 + $base2)) * 0.5)
                        $ang3 = $base2 + $t * 0.25
                    }
                    default {
                        $r3   = $baseR * (0.7 + [Math]::Sin($t * $freq2 + $base2) * 0.3)
                        $ang3 = $base2 + $t * (0.15 + $freq2 * 0.1)
                    }
                }
                $ppx = $cx + [int]($r3 * [Math]::Cos($ang3))
                $ppy = $cy + [int]($r3 * [Math]::Sin($ang3))
                $palpha = [int](40 + 30 * [Math]::Abs([Math]::Sin($t * $freq2 + $base2)))
                $plp = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb($palpha,$col.R,$col.G,$col.B),1)
                $g.DrawLine($plp,$cx,$cy,$ppx,$ppy); $plp.Dispose()
                $pra = [int](130 + 100 * [Math]::Abs([Math]::Sin($t * $freq2 + $base2)))
                $ppb = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb($pra,$col.R,$col.G,$col.B))
                $g.FillEllipse($ppb,($ppx-4),($ppy-4),8,8); $ppb.Dispose()
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

        'network' {
            # Node network — relationships, social, trading, bonds
            $p    = $script:simParams
            $lbls = if ($p.labels) { $p.labels } else { @("PLAYER","NPC","GUILD","MARKET","RIVAL") }
            $col  = if ($p.color)  { try { [System.Drawing.ColorTranslator]::FromHtml($p.color) } catch { $SYS_COL } } else { $SYS_COL }
            $nn   = [Math]::Min($lbls.Count, 7)
            $nrad = [int]([Math]::Min($cw,$ch) * 0.27)
            $netPts = [System.Drawing.Point[]]($nn)
            $netPts[0] = [System.Drawing.Point]::new($cx,$cy)
            for ($ni = 1; $ni -lt $nn; $ni++) {
                $nang = 2*[Math]::PI*($ni-1)/([Math]::Max($nn-1,1)) - [Math]::PI/2
                $netPts[$ni] = [System.Drawing.Point]::new(
                    [int]($cx + $nrad * [Math]::Cos($nang)),
                    [int]($cy + $nrad * [Math]::Sin($nang))
                )
            }
            $pulseT2 = ($t * 0.35) % 1.0
            $npb = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(190,$col.R,$col.G,$col.B))
            for ($ni = 1; $ni -lt $nn; $ni++) {
                $src2 = $netPts[0]; $dst2 = $netPts[$ni]
                $calpha = [int](25 + 18 * [Math]::Sin($t * 0.3 + $ni))
                $ncp = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb($calpha,$col.R,$col.G,$col.B),1)
                $g.DrawLine($ncp,$src2.X,$src2.Y,$dst2.X,$dst2.Y); $ncp.Dispose()
                $pp3  = ($pulseT2 + $ni * 0.18) % 1.0
                $ppx2 = [int]($src2.X + ($dst2.X-$src2.X)*$pp3)
                $ppy2 = [int]($src2.Y + ($dst2.Y-$src2.Y)*$pp3)
                $g.FillEllipse($npb,($ppx2-3),($ppy2-3),6,6)
            }; $npb.Dispose()
            $nnp = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(180,$col.R,$col.G,$col.B),1)
            $nlb = New-Object System.Drawing.SolidBrush($col)
            for ($ni = 0; $ni -lt $nn; $ni++) {
                $pos2  = $netPts[$ni]
                $nnr   = if ($ni -eq 0) { 20 } else { 14 }
                $nalph = [int](35 + 18 * [Math]::Sin($t * 0.4 + $ni))
                $nnb   = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb($nalph,$col.R,$col.G,$col.B))
                $g.FillEllipse($nnb,($pos2.X-$nnr),($pos2.Y-$nnr),$nnr*2,$nnr*2)
                $g.DrawEllipse($nnp,($pos2.X-$nnr),($pos2.Y-$nnr),$nnr*2,$nnr*2)
                $nnb.Dispose()
                $nlbl2 = if ($lbls[$ni].Length -gt 6) { $lbls[$ni].Substring(0,6) } else { $lbls[$ni] }
                $nsz   = $g.MeasureString($nlbl2,$script:fnt7B)
                $g.DrawString($nlbl2,$script:fnt7B,$nlb,($pos2.X-$nsz.Width/2),($pos2.Y-$nsz.Height/2))
            }; $nnp.Dispose(); $nlb.Dispose()
        }

        'grid_world' {
            # Animated grid — ranch management, placement, world systems
            $p    = $script:simParams
            $gcols = if ($p.cols) { [int]$p.cols } else { 8 }
            $grows = if ($p.rows) { [int]$p.rows } else { 6 }
            $col  = if ($p.color) { try { [System.Drawing.ColorTranslator]::FromHtml($p.color) } catch { $LOOP_COL } } else { $LOOP_COL }
            $cellW2 = [int]($cw * 0.7 / $gcols)
            $cellH2 = [int]($ch * 0.65 / $grows)
            $gw2    = $gcols * $cellW2; $gh2 = $grows * $cellH2
            $gsx    = [int]($cx - $gw2/2); $gsy = [int]($cy - $gh2/2)
            $ggp = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(18,255,255,255),1)
            for ($gr = 0; $gr -le $grows; $gr++) {
                $gy3 = $gsy + $gr * $cellH2
                $g.DrawLine($ggp,$gsx,$gy3,($gsx+$gw2),$gy3)
            }
            for ($gc = 0; $gc -le $gcols; $gc++) {
                $gx3 = $gsx + $gc * $cellW2
                $g.DrawLine($ggp,$gx3,$gsy,$gx3,($gsy+$gh2))
            }; $ggp.Dispose()
            $entCols = @($col,$AMBER,$MECH_COL,$GREEN,$SYS_COL,$LOOP_COL)
            for ($ei2 = 0; $ei2 -lt 6; $ei2++) {
                $period2 = 2.5 + $ei2 * 0.6
                $ecc = [int](($t / $period2 * $gcols) % $gcols)
                $erc = ($ei2 * 2) % $grows
                $eex = $gsx + $ecc * $cellW2 + [int]($cellW2 * 0.15)
                $eey = $gsy + $erc * $cellH2 + [int]($cellH2 * 0.15)
                $eew = [int]($cellW2 * 0.7); $eeh = [int]($cellH2 * 0.7)
                $ec3 = $entCols[$ei2 % $entCols.Count]
                $ealpha = [int](50 + 35 * [Math]::Sin($t * 0.7 + $ei2))
                $eeb = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb($ealpha,$ec3.R,$ec3.G,$ec3.B))
                $eep = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(180,$ec3.R,$ec3.G,$ec3.B),1)
                $g.FillRectangle($eeb,$eex,$eey,$eew,$eeh)
                $g.DrawRectangle($eep,$eex,$eey,$eew,$eeh)
                $eeb.Dispose(); $eep.Dispose()
            }
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

    # Skip if state.json hasn't changed since last read
    $fi = Get-Item $STATE -ErrorAction SilentlyContinue
    if (-not $fi -or $fi.LastWriteTime -le $script:stateLastWrite) { return }
    $script:stateLastWrite = $fi.LastWriteTime
    $obj = Read-State; if (-not $obj) { return }
    $resp    = [string]$obj.response
    $title   = [string]$obj.title
    $content = [string]$obj.content
    $fwPath  = [string]$obj.framework_path

    # Check for completed framework
    if ($fwPath -and $fwPath -ne $script:lastFrameworkPath) {
        $script:lastFrameworkPath = $fwPath
        $btnFramework.Text    = 'FRAMEWORK'
        Update-FrameworkButton
        [System.Windows.Forms.MessageBox]::Show(
            "Framework saved to:`n$fwPath`n`nOpening now...", "ValenTech", 'OK', 'Information') | Out-Null
        Start-Process notepad.exe $fwPath
    }

    if ($title -and $resp -eq '' -and ($title -ne $script:currentTitle -or $content -ne $script:currentContent)) {
        $script:currentTitle   = $title
        $script:currentContent = $content
        # sim is stored as a proper JSON object — parse directly
        try {
            $simObj = $obj.sim
            if ($simObj -and $simObj.type) {
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
            $cy = 0
            foreach ($comp in $comps) {
                $cb = New-Object System.Windows.Forms.CheckBox
                $cb.Text      = [string]$comp
                $cb.Font      = New-Object System.Drawing.Font('Consolas', 9)
                $cb.ForeColor = $TEXT_HI
                $cb.BackColor = $CARD_BG
                $cb.AutoSize  = $false
                $cb.SetBounds(0, $cy, $checkPanel.Width, 26)
                $cb.Checked   = $true
                $checkPanel.Controls.Add($cb)
                $script:checkboxes.Add($cb)
                $cy += 28
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
