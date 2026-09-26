#requires -Version 5.1
<#
新装 Windows 与已有 UserSpace 的中文向导。
直接启动：显示菜单，每次实际操作前只确认一次摘要。
-Action Plan / Status：只读输出，不创建目录、不改设置。
核心检查在 UserSpace.Core.psm1，Windows API 在 UserSpace.Native.cs。
#>
[CmdletBinding()]
param(
    [ValidateSet('Wizard','Init','Upgrade','Cleanup','Plan','Status','Verify')]
    [string]$Action = 'Wizard'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Show-USMessage([string]$Text, [string]$Title = 'UserSpace') {
    [void][Windows.Forms.MessageBox]::Show($Text, $Title, 'OK', 'Information')
}
function Confirm-USAction([string]$Text) {
    # 可滚动的确认清单，适合掌机屏幕；默认焦点和回车操作都是取消。
    $form=New-USForm '确认这一步' 550
    $box=New-Object Windows.Forms.TextBox
    $box.SetBounds(22,16,606,460)
    $box.Multiline=$true; $box.ReadOnly=$true; $box.ScrollBars='Vertical'; $box.Text=$Text
    $form.Controls.Add($box)
    $yes=New-Object Windows.Forms.Button
    $yes.SetBounds(328,490,145,40); $yes.Text='确认并执行'; $yes.DialogResult='Yes'
    $no=New-Object Windows.Forms.Button
    $no.SetBounds(483,490,145,40); $no.Text='取消'; $no.DialogResult='No'
    $form.Controls.Add($yes); $form.Controls.Add($no)
    $form.AcceptButton=$no; $form.CancelButton=$no; $form.ActiveControl=$no
    try {$form.ShowDialog() -eq 'Yes'} finally {$form.Dispose()}
}
function Invoke-USSignOut {
    # 初始化/修复的开始确认已包含自动注销警告；仅在完整验收成功后调用。
    # 只注销当前账户，不关机、不重启，也不添加强制关闭程序的参数。
    $process = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\shutdown.exe') -ArgumentList '/l' -WindowStyle Hidden -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "注销请求失败（退出码 $($process.ExitCode)），请从 Windows 开始菜单手动注销。目录设置保持不变。" }
}
function New-USForm([string]$Title, [int]$Height = 360) {
    $form = New-Object Windows.Forms.Form
    $form.Text = $Title
    $form.Font = New-Object Drawing.Font('Microsoft YaHei UI', 10)
    $form.ClientSize = New-Object Drawing.Size(650, $Height)
    $form.AutoScaleMode = 'Font'
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form
}
function Add-USLabel($Form, [string]$Text, [int]$Top, [int]$Height = 45) {
    $label = New-Object Windows.Forms.Label
    $label.SetBounds(22, $Top, 606, $Height)
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
    $form = New-USForm 'UserSpace · 初始化与修复 v4.3' 365
    Add-USLabel $form "当前账户：$($context.User)`r`n$($context.Root)" 16 58
    Add-USButton $form '修复并更新（保留原文件）' 87 { $form.Tag='Upgrade'; $form.Close() }
    Add-USButton $form '初始化 / 完整修复（会搬旧目录内容）' 142 { $form.Tag='Init'; $form.Close() }
    Add-USButton $form '查看状态与兼容性验收（只读）' 197 { $form.Tag='Status'; $form.Close() }
    Add-USButton $form '清理旧空目录（另行确认）' 252 { $form.Tag='Cleanup'; $form.Close() }
    Add-USLabel $form 'OneDrive 保持原样；不处理磁盘挂载或创建目录链接。' 307
    try { [void]$form.ShowDialog(); $form.Tag } finally { $form.Dispose() }
}
function Show-USStatusWindow {
    $text = (Get-USStatus) -join "`r`n"
    $form = New-USForm 'UserSpace · 当前状态（只读，可复制）' 510
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
            $text = "账户：$($plan.Context.User)`r`n目标：$($plan.Context.Root)`r`n`r`n本操作成功后将自动注销，不再二次询问。请先保存你手上的工作并关闭相关软件。`r`n失败或取消不会注销。`r`n`r`n以下是当前地址与目标地址不一致的项目：`r`n$($preview.Text)`r`n`r`n确认后备份设置，修正所列入口，并检查、更新六个目标目录的图标。`r`n不搬用户文件、不整理链接、不创建预设目录、不清理旧目录。旧位置的数据仍留原地；修正入口后，软件可能需要另行导入旧数据。`r`n`r`n全部 44 项验收通过后自动注销。开始修复并更新吗？"
            if (Confirm-USAction $text) {
                Invoke-USUpgrade -ConfirmedSignature $preview.Signature | Out-Null
                Invoke-USSignOut
            }
        }
        'Init' {
            $plan = Get-USInitPlan
            Assert-USFreshPlan $plan
            $text = "账户：$($plan.Context.User)`r`n目标：$($plan.Context.Root)`r`n`r`n本操作成功后将自动注销，不再二次询问。请先保存你手上的工作并关闭相关软件。`r`n失败或取消不会注销。`r`n`r`n把六个系统目录的 11 个常用/Local 入口统一到 UserSpace。`r`n搬入旧目录中的文件；保留新目录已有文件，同名冲突会停止。`r`n备份 desktop.ini，再修复六个目录的系统图标。`r`n系统接口通过检查后，同步旧式 Shell Folders 中不一致的六个常用值。`r`n其余六个自建目录只创建缺失项，不搬内容。`r`n`r`n本步骤不删除旧目录；OneDrive 和其他重定向不接管。`r`n全部 44 项验收通过后自动注销；写死旧路径的软件不保证跟随。`r`n`r`n开始初始化 / 修复吗？"
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
                Show-USMessage ("没有可清理的旧空目录。`r`n" + (($entries | ForEach-Object { "$($_.Name)：$($_.Reason)" }) -join "`r`n"))
                return
            }
            $text = "仅清理下面的旧空目录：`r`n$((@($eligible | ForEach-Object Path)) -join "`r`n")`r`n`r`n若只有已识别的 desktop.ini，会先把它移到记录目录保存。其他文件、子目录或链接会阻止清理。`r`n删除前会重新检查全部系统入口。不会递归删除，也不会删除 UserSpace 中的目录。`r`n用户名视图仍可能显示指向 UserSpace 的入口，请勿再手动删除这些入口。`r`n`r`n确认清理这 $($eligible.Count) 个旧目录吗？"
            if (Confirm-USAction $text) { Show-USMessage (Invoke-USCleanup -Paths @($eligible | ForEach-Object Path)) }
        }
    }
}

try {
    if ($Action -eq 'Verify') { [Console]::OutputEncoding=[Text.UTF8Encoding]::new($false) }
    # 图形启动时先准备错误提示窗口；即使程序文件缺失，也不把错误藏在后台控制台。
    if ($Action -notin @('Plan','Status','Verify')) { Add-Type -AssemblyName System.Windows.Forms }
    Import-Module (Join-Path $PSScriptRoot 'UserSpace.Core.psm1') -Force
    if ($Action -eq 'Verify') {
        # 只读验收子进程。用 Base64 包装 UTF-8，防止不同终端编码损坏中文路径。
        $json = Get-USVerification | ConvertTo-Json -Depth 6 -Compress
        'USV4:' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
        return
    }
    if ($Action -eq 'Plan') {
        $plan = Get-USInitPlan
        "当前账户：$($plan.Context.User)"
        $plan.Folders | ForEach-Object { $_.Bindings } | Format-Table Name,Kind,Previous,Target -AutoSize
        '以上只是路径预览；真正初始化前还会检查移动范围和同名冲突。未修改任何设置。'
        return
    }
    if ($Action -eq 'Status') { Get-USStatus; return }
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [Windows.Forms.Application]::EnableVisualStyles()
    if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
        throw '请关闭这个窗口，双击解压文件夹中的“启动.cmd”打开向导。'
    }
    if ($Action -ne 'Wizard') { Invoke-USWizardStep $Action; return }
    while ($true) {
        $next = Show-USMenu
        if (-not $next) { break }
        try { Invoke-USWizardStep $next }
        catch { Show-USMessage $_.Exception.Message '这一步未完成' }
    }
}
catch {
    if ('Windows.Forms.MessageBox' -as [type]) { Show-USMessage $_.Exception.Message 'UserSpace 未完成' }
    else { Write-Error $_.Exception.Message -ErrorAction Continue }
    exit 1
}
