#requires -Version 5.1
<#
新装 Windows 与已有 UserSpace 的双语向导。
直接启动：显示菜单，每次实际操作前只确认一次摘要。
-Action Plan / Status：只读输出，不创建目录、不改设置。
核心检查在 UserSpace.Core.psm1，Windows API 在 UserSpace.Native.cs。
#>
[CmdletBinding()]
param(
    [ValidateSet('Wizard','Init','Upgrade','Cleanup','Plan','Status','Verify')]
    [string]$Action = 'Wizard',
    [ValidateSet('Auto','zh-CN','en')]
    [string]$Language = 'Auto'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Show-USMessage([string]$Text, [string]$Title = 'UserSpace') {
    [void][Windows.Forms.MessageBox]::Show($Text, $Title, 'OK', 'Information')
}
function Confirm-USAction([string]$Text) {
    # 可滚动的确认清单，适合掌机屏幕；默认焦点和回车操作都是取消。
    $form=New-USForm (Get-USText 'UI001') 550
    $box=New-Object Windows.Forms.TextBox
    $box.SetBounds(22,16,606,460)
    $box.Multiline=$true; $box.ReadOnly=$true; $box.ScrollBars='Vertical'; $box.Text=$Text
    $form.Controls.Add($box)
    $yes=New-Object Windows.Forms.Button
    $yes.SetBounds(328,490,145,40); $yes.Text=(Get-USText 'UI002'); $yes.DialogResult='Yes'
    $no=New-Object Windows.Forms.Button
    $no.SetBounds(483,490,145,40); $no.Text=(Get-USText 'UI003'); $no.DialogResult='No'
    $form.Controls.Add($yes); $form.Controls.Add($no)
    $form.AcceptButton=$no; $form.CancelButton=$no; $form.ActiveControl=$no
    try {$form.ShowDialog() -eq 'Yes'} finally {$form.Dispose()}
}
function Invoke-USSignOut {
    # 初始化/修复的开始确认已包含自动注销警告；仅在完整验收成功后调用。
    # 只注销当前账户，不关机、不重启，也不添加强制关闭程序的参数。
    $process = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\shutdown.exe') -ArgumentList '/l' -WindowStyle Hidden -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw (Get-USText 'UI004' -Arguments @(($($process.ExitCode)))) }
}
function New-USForm([string]$Title, [int]$Height = 360) {
    $form = New-Object Windows.Forms.Form
    $form.Text = $Title
    $fontName = if ((Get-USLanguage) -eq 'zh-CN') {'Microsoft YaHei UI'} else {'Segoe UI'}
    $form.Font = New-Object Drawing.Font($fontName, 10)
    $form.ClientSize = New-Object Drawing.Size(650, $Height)
    $form.AutoScaleMode = 'Font'
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form
}
function Add-USLabel($Form, [string]$Text, [int]$Top, [int]$Height = 45, [int]$Width = 606) {
    $label = New-Object Windows.Forms.Label
    $label.SetBounds(22, $Top, $Width, $Height)
    $label.Text = $Text
    $Form.Controls.Add($label)
}
function Add-USButton($Form, [string]$Text, [int]$Top, [scriptblock]$Click) {
    $button = New-Object Windows.Forms.Button
    $button.SetBounds(22, $Top, 606, 43)
    $button.Text = $Text
    $button.Add_Click($Click)
    $Form.Controls.Add($button)
}
function Show-USMenu {
    $context = Get-USContext
    $form = New-USForm (Get-USText 'UI005') 410
    Add-USLabel $form (Get-USText 'UI006' -Arguments @(($($context.User)),($($context.Root)))) 16 58
    Add-USButton $form (Get-USText 'UI007') 87 { $form.Tag='Upgrade'; $form.Close() }
    Add-USButton $form (Get-USText 'UI008') 142 { $form.Tag='Init'; $form.Close() }
    Add-USButton $form (Get-USText 'UI009') 197 { $form.Tag='Status'; $form.Close() }
    Add-USButton $form (Get-USText 'UI010') 252 { $form.Tag='Cleanup'; $form.Close() }
    Add-USLabel $form (Get-USText 'UI011') 307
    Add-USLabel $form (Get-USText 'LanguageLabel') 360 30 280
    $selector=New-Object Windows.Forms.ComboBox
    $selector.SetBounds(330,355,298,30)
    $selector.DropDownStyle='DropDownList'
    [void]$selector.Items.AddRange([object[]]@('Auto','简体中文','English'))
    $selector.SelectedIndex=@('Auto','zh-CN','en').IndexOf($script:LanguageChoice)
    $selector.Add_SelectedIndexChanged({
        $script:LanguageChoice=@('Auto','zh-CN','en')[$selector.SelectedIndex]
        Set-USLanguage $script:LanguageChoice
        $form.Tag='LanguageChanged'; $form.Close()
    })
    $form.Controls.Add($selector)
    try { [void]$form.ShowDialog(); $form.Tag } finally { $form.Dispose() }
}
function Show-USStatusWindow {
    $text = (Get-USStatus) -join "`r`n"
    $form = New-USForm (Get-USText 'UI012') 510
    $box = New-Object Windows.Forms.TextBox
    $box.SetBounds(16, 16, 618, 478)
    $box.Multiline = $true; $box.ReadOnly = $true; $box.ScrollBars = 'Both'
    $box.WordWrap = $false; $box.Text = $text
    $form.Controls.Add($box)
    try { [void]$form.ShowDialog() } finally { $form.Dispose() }
}
function Invoke-USWizardStep([string]$Step) {
    switch ($Step) {
        'Upgrade' {
            $plan = Get-USInitPlan
            Assert-USUpgradePlan $plan
            $preview=Get-USRepairPreview $plan
            $text = (Get-USText 'UI013' -Arguments @(($($plan.Context.User)),($($plan.Context.Root)),($($preview.Text))))
            if (Confirm-USAction $text) {
                Invoke-USUpgrade -ConfirmedSignature $preview.Signature | Out-Null
                Invoke-USSignOut
            }
        }
        'Init' {
            $plan = Get-USInitPlan
            Assert-USFreshPlan $plan
            $text = (Get-USText 'UI014' -Arguments @(($($plan.Context.User)),($($plan.Context.Root))))
            if (Confirm-USAction $text) {
                Invoke-USInit | Out-Null
                Invoke-USSignOut
            }
        }
        'Status' { Show-USStatusWindow }
        'Cleanup' {
            $entries = @(Get-USCleanupPlan)
            $eligible = @($entries | Where-Object Eligible)
            if ($eligible.Count -eq 0) {
                Show-USMessage ((Get-USText 'UI015') + (($entries | ForEach-Object { "$($_.Name)：$($_.Reason)" }) -join "`r`n"))
                return
            }
            $text = (Get-USText 'UI016' -Arguments @(($((@($eligible | ForEach-Object Path)) -join "`r`n")),($($eligible.Count))))
            if (Confirm-USAction $text) { Show-USMessage (Invoke-USCleanup -Paths @($eligible | ForEach-Object Path)) }
        }
    }
}

try {
    if ($Action -eq 'Verify') { [Console]::OutputEncoding=[Text.UTF8Encoding]::new($false) }
    # 图形启动时先准备错误提示窗口；即使程序文件缺失，也不把错误藏在后台控制台。
    if ($Action -notin @('Plan','Status','Verify')) { Add-Type -AssemblyName System.Windows.Forms }
    Import-Module (Join-Path $PSScriptRoot 'UserSpace.Core.psm1') -Force
    $script:LanguageChoice=$Language
    Set-USLanguage $Language
    if ($Action -eq 'Verify') {
        # 只读验收子进程。用 Base64 包装 UTF-8，防止不同终端编码损坏中文路径。
        $json = Get-USVerification | ConvertTo-Json -Depth 6 -Compress
        'USV4:' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
        return
    }
    if ($Action -eq 'Plan') {
        $plan = Get-USInitPlan
        (Get-USText 'UI017' -Arguments @(($($plan.Context.User))))
        $plan.Folders | ForEach-Object { $_.Bindings } | Format-Table Name,Kind,Previous,Target -AutoSize
        (Get-USText 'UI018')
        return
    }
    if ($Action -eq 'Status') { Get-USStatus; return }
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [Windows.Forms.Application]::EnableVisualStyles()
    if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
        throw (Get-USText 'UI019')
    }
    if ($Action -ne 'Wizard') { Invoke-USWizardStep $Action; return }
    while ($true) {
        $next = Show-USMenu
        if (-not $next) { break }
        if ($next -eq 'LanguageChanged') {continue}
        try { Invoke-USWizardStep $next }
        catch { Show-USMessage $_.Exception.Message (Get-USText 'UI020') }
    }
}
catch {
    # 资源文件缺失时仍能显示原始错误，不依赖尚未加载的翻译函数。
    if ('Windows.Forms.MessageBox' -as [type]) { Show-USMessage $_.Exception.Message 'UserSpace' }
    else { Write-Error $_.Exception.Message -ErrorAction Continue }
    exit 1
}
