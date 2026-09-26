#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:NL = [Environment]::NewLine
if (-not ('UserSpaceInitV4.Native' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'UserSpace.Native.cs') }
$script:Presets = @('Assets','Desktop','Documents','Downloads','Games','Music','Pictures','Projects','Resources','Utils','Videos','VSTPlugins')
# 六个常用入口、五个 Local 入口；桌面没有另加不存在的 LocalDesktop。
$script:Folders = @(
    @{Name='Desktop'; Id='B4BFCC3A-DB2C-424C-B029-7FE99A87C641'; LocalId=''; Reg='Desktop'; Legacy=16; Net='DesktopDirectory'},
    @{Name='Documents'; Id='FDD39AD0-238F-46AF-ADB4-6C85480369C7'; LocalId='F42EE2D3-909F-4907-8871-4C22FC0BF756'; Reg='Personal'; Legacy=5; Net='MyDocuments'},
    @{Name='Downloads'; Id='374DE290-123F-4565-9164-39C4925E467B'; LocalId='7D83EE9B-2244-4E70-B1F5-5393042AF1E4'; Reg='{374DE290-123F-4565-9164-39C4925E467B}'; Legacy=-1; Net=''},
    @{Name='Music'; Id='4BD8D571-6D19-48D3-BE97-422220080E43'; LocalId='A0C69A99-21C8-4671-8703-7934162FCF1D'; Reg='My Music'; Legacy=13; Net='MyMusic'},
    @{Name='Pictures'; Id='33E28130-4E1E-4676-835A-98395C3BC3BB'; LocalId='0DDD015D-B06C-45D5-8C4C-F59713854639'; Reg='My Pictures'; Legacy=39; Net='MyPictures'},
    @{Name='Videos'; Id='18989B1D-99B5-455B-841C-AB7C74E4DDFC'; LocalId='35286A68-3C57-41A1-BBB1-0EAE73D76C95'; Reg='My Video'; Legacy=14; Net='MyVideos'}
)
$script:RunnerHashes = @{}
foreach ($file in @('UserSpace.ps1','UserSpace.Core.psm1','UserSpace.Native.cs')) {
    $script:RunnerHashes[$file] = (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $file) -Algorithm SHA256).Hash
}
function Get-USKnownPath([string]$Id, [switch]$Default) { [UserSpaceInitV4.Native]::KnownPath($Id, $Default.IsPresent) }
function Set-USKnownPath([string]$Id, [string]$Path) { [UserSpaceInitV4.Native]::SetKnownPath($Id, $Path) }
function Get-USLegacyPath([int]$Id) { [UserSpaceInitV4.Native]::LegacyPath($Id) }
function Get-USNetPath([string]$Name) { [Environment]::GetFolderPath([Environment+SpecialFolder]$Name, [Environment+SpecialFolderOption]::DoNotVerify) }
function Send-USFolderNotice([string]$Path) { [UserSpaceInitV4.Native]::NotifyFolder($Path) }
function Get-USContext {
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    $profilePath=Get-USKnownPath '5E6C858F-0E22-4760-9AFE-EA3317B67173'
    [pscustomobject]@{User=$identity.Name; Sid=$identity.User.Value; Profile=$profilePath; Root=(Join-Path $profilePath 'UserSpace'); StateRoot=(Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'UserSpaceBootstrap')}
}

function ConvertTo-USPath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -notmatch '^[A-Za-z]:\\') {
        throw "需要本地绝对路径：$Path"
    }
    $full = [IO.Path]::GetFullPath($Path)
    if ($full.Length -gt 3) { $full = $full.TrimEnd('\') }
    $full
}
function Test-USSamePath([string]$First, [string]$Second) {
    [string]::Equals($First.TrimEnd('\'), $Second.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)
}
function Assert-USPlainPath([string]$Path) {
    # 逐级检查已有父目录，防止通过祖先 junction/symlink 写到意料外的位置。
    $full = ConvertTo-USPath $Path
    $walk = [IO.Path]::GetPathRoot($full)
    $parts = $full.Substring($walk.Length).Split('\', [StringSplitOptions]::RemoveEmptyEntries)
    foreach ($part in @('') + $parts) {
        if ($part) { $walk = Join-Path $walk $part }
        $entry = [UserSpaceInitV4.Native]::Inspect($walk)
        if ($entry.Exists -and (-not $entry.Directory -or $entry.Reparse)) {
            throw "这里需要普通目录，但发现文件或重解析点：$walk"
        }
    }
}
function Assert-USMovePaths([string]$Source, [string]$Target, [string]$SourceRoot, [string]$TargetRoot) {
    # 只允许移动明确选中的系统目录的直接子项，目标也必须是对应 UserSpace 目录的直接子项。
    $sourceFull = ConvertTo-USPath $Source
    $targetFull = ConvertTo-USPath $Target
    $sourceBase = ConvertTo-USPath $SourceRoot
    $targetBase = ConvertTo-USPath $TargetRoot
    Assert-USPlainPath $sourceBase
    Assert-USPlainPath $targetBase
    if (-not (Test-USSamePath (Split-Path -Parent $sourceFull) $sourceBase) -or
        -not (Test-USSamePath (Split-Path -Parent $targetFull) $targetBase) -or
        [IO.Path]::GetFileName($sourceFull) -ine [IO.Path]::GetFileName($targetFull)) {
        throw '移动范围不是已确认的系统目录和对应目标目录。'
    }
    if ([IO.Path]::GetPathRoot($sourceFull) -ine [IO.Path]::GetPathRoot($targetFull)) {
        throw '本版只处理同一卷内的初始化，不进行跨盘搬迁。'
    }
    if (-not ([UserSpaceInitV4.Native]::Inspect($sourceFull)).Exists) { throw "待移动项目已不存在：$sourceFull" }
    if (([UserSpaceInitV4.Native]::Inspect($targetFull)).Exists) {
        throw "同名冲突，未覆盖：$targetFull。请先检查两边的项目。"
    }
}


function Move-USItem([string]$Source, [string]$Target) { [UserSpaceInitV4.Native]::MoveEntry($Source, $Target) }
function Get-USIconDefinition([string]$Id) {
    $key=Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FolderDescriptions\{$Id}"
    if (-not $key.Icon) { throw "系统目录缺少图标定义：$Id" }
    [pscustomobject]@{Icon=[string]$key.Icon; Label=[string]$key.LocalizedName}
}
function Get-USIniSnapshot([string]$Directory) {
    Assert-USPlainPath $Directory
    $path=Join-Path $Directory 'desktop.ini'
    $entry=[UserSpaceInitV4.Native]::Inspect($path)
    if (-not $entry.Exists) { return [pscustomobject]@{Path=$path; Exists=$false; Bytes=''; Text=''; Attributes=0; Recognized=$false} }
    if ($entry.Directory -or $entry.Reparse) { throw "desktop.ini 不是普通文件：$path" }
    if ((Get-Item -LiteralPath $path -Force).Length -gt 65536) { throw "desktop.ini 大小异常：$path" }
    $bytes=[IO.File]::ReadAllBytes($path)
    $text=[IO.File]::ReadAllText($path)
    [pscustomobject]@{Path=$path; Exists=$true; Bytes=[Convert]::ToBase64String($bytes); Text=$text; Attributes=[int][IO.File]::GetAttributes($path); Recognized=($text -match '(?im)^\s*\[\.ShellClassInfo\]\s*$')}
}
function Set-USIniValues([string]$Text, $Values) {
    $lines=[Collections.Generic.List[string]]::new()
    foreach ($line in ($Text -split '\r?\n')) { $lines.Add($line) }
    $start=-1
    for ($i=0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*\[\.ShellClassInfo\]\s*$') {
            if ($start -ge 0) { throw 'desktop.ini 包含重复的 ShellClassInfo 段。' }
            $start=$i
        }
    }
    if ($start -lt 0) { $start=$lines.Count; $lines.Add('[.ShellClassInfo]') }
    $end=$start+1
    while ($end -lt $lines.Count -and $lines[$end] -notmatch '^\s*\[') { $end++ }
    foreach ($name in $Values.Keys) {
        $found=$false
        for ($i=$start+1; $i -lt $end; $i++) {
            if ($lines[$i] -match ('^\s*'+[regex]::Escape($name)+'\s*=')) { $lines[$i]="$name=$($Values[$name])"; $found=$true }
        }
        if (-not $found) { $lines.Insert($end,"$name=$($Values[$name])"); $end++ }
    }
    ($lines -join $script:NL).TrimEnd([char[]]@(13,10)) + $script:NL
}
function Get-USInitPlan {
    $context=Get-USContext
    $rows=foreach ($definition in $script:Folders) {
        $old=Join-Path $context.Profile $definition.Name
        $target=Join-Path $context.Root $definition.Name
        $bindings=foreach ($id in @($definition.Id,$definition.LocalId)) {
            if (-not $id) { continue }
            $regName=if ($id -eq $definition.Id) {$definition.Reg} else {'{'+$id+'}'}
            [pscustomobject]@{Id=$id; Name=$definition.Name; Kind=$(if ($id -eq $definition.Id) {'常用'} else {'Local'}); Previous=(Get-USKnownPath $id); Target=$target; RegistryName=$regName; RegistryPrevious=(Get-USRegistryValue 'User Shell Folders' $regName); Attempted=$false}
        }
        [pscustomobject]@{Name=$definition.Name; Id=$definition.Id; OldPath=$old; TargetPath=$target; Bindings=@($bindings); Moves=@(); Metadata=$null}
    }
    [pscustomobject]@{Context=$context; Folders=@($rows); Presets=$script:Presets}
}
function Get-USFolderMoves($Folder) {
    # 已经改好常用入口的机器也要检查旧目录，不能提前返回“已完成”。
    Assert-USPlainPath $Folder.OldPath
    Assert-USPlainPath $Folder.TargetPath
    if (-not [IO.Directory]::Exists($Folder.OldPath)) { return }
    $ini=Get-USIniSnapshot $Folder.OldPath
    foreach ($child in Get-ChildItem -LiteralPath $Folder.OldPath -Force | Sort-Object Name) {
        if ($child.Name -ieq 'desktop.ini' -and $ini.Recognized) { continue }
        $target=Join-Path $Folder.TargetPath $child.Name
        Assert-USMovePaths $child.FullName $target $Folder.OldPath $Folder.TargetPath
        [pscustomobject]@{Source=$child.FullName; Target=$target; Attempted=$false; Moved=$false}
    }
}
function Assert-USNoUserContents([string]$Path) {
    Assert-USPlainPath $Path
    if (-not [IO.Directory]::Exists($Path)) { return }
    $ini=Get-USIniSnapshot $Path
    foreach ($child in Get-ChildItem -LiteralPath $Path -Force) {
        if ($child.Name -ieq 'desktop.ini' -and $ini.Recognized) { continue }
        throw "旧目录还有内容：$($child.FullName)。请关闭使用目录的程序并保留两边内容。"
    }
}
function Assert-USFreshPlan($Plan) {
    Assert-USPlainPath $Plan.Context.Profile
    Assert-USPlainPath $Plan.Context.Root
    if (-not [IO.Directory]::Exists($Plan.Context.Profile)) { throw '请在日用账户登录后运行。' }
    foreach ($folder in $Plan.Folders) {
        foreach ($binding in $folder.Bindings) {
            Assert-USBindingRegistry $binding $folder.OldPath
            if (-not (Test-USSamePath $binding.Previous $folder.OldPath) -and -not (Test-USSamePath $binding.Previous $folder.TargetPath)) {
                throw "$($binding.Name) / $($binding.Kind) 指向其他位置：$($binding.Previous)。本工具不接管 OneDrive 或其他重定向。"
            }
        }
        Assert-USPlainPath $folder.OldPath
        Assert-USPlainPath $folder.TargetPath
        $folder.Moves=@(Get-USFolderMoves $folder)
        $oldIni=Get-USIniSnapshot $folder.OldPath
        $newIni=Get-USIniSnapshot $folder.TargetPath
        if (($newIni.Exists -and -not $newIni.Recognized) -or ($oldIni.Exists -and -not $oldIni.Recognized)) { throw "发现无法识别的 desktop.ini：$($folder.Name)，未覆盖。" }
        $icon=Get-USIconDefinition $folder.Id
        $seed=if ($newIni.Exists) {$newIni.Text} else {$oldIni.Text}
        $values=[ordered]@{IconResource=$icon.Icon}
        if ($icon.Label) {$values['LocalizedResourceName']=$icon.Label}
        $folder.Metadata=[pscustomobject]@{OldIni=$oldIni; NewIni=$newIni; Content=(Set-USIniValues $seed $values); TargetAttributes=$(if ([IO.Directory]::Exists($folder.TargetPath)) {[int][IO.File]::GetAttributes($folder.TargetPath)} else {0}); Attempted=$false}
    }
    foreach ($name in $Plan.Presets) { Assert-USPlainPath (Join-Path $Plan.Context.Root $name) }
}
function Assert-USUpgradePlan($Plan) {
    # 修复已有结构：允许常用/Local 入口仍在默认位置，但目标目录必须已经存在。
    # 不调用搬迁预检，不列出旧目录内容，也不要求其他自建目录是普通目录。
    Assert-USPlainPath $Plan.Context.Profile
    Assert-USPlainPath $Plan.Context.Root
    foreach ($folder in $Plan.Folders) {
        Assert-USPlainPath $folder.TargetPath
        if (-not [IO.Directory]::Exists($folder.TargetPath)) {throw "升级要求目标目录已经存在：$($folder.TargetPath)。未创建或搬迁任何目录。"}
        foreach ($binding in $folder.Bindings) {
            Assert-USBindingRegistry $binding $folder.OldPath
            if (-not (Test-USSamePath $binding.Previous $folder.OldPath) -and -not (Test-USSamePath $binding.Previous $folder.TargetPath)) {
                throw "$($folder.Name) / $($binding.Kind) 指向其他位置：$($binding.Previous)。本模式不接管 OneDrive 或其他重定向。"
            }
        }
        $ini=Get-USIniSnapshot $folder.TargetPath
        if ($ini.Exists -and -not $ini.Recognized) {throw "发现无法识别的 desktop.ini：$($folder.Name)，未覆盖。"}
        $icon=Get-USIconDefinition $folder.Id
        $values=[ordered]@{IconResource=$icon.Icon}
        if ($icon.Label) {$values['LocalizedResourceName']=$icon.Label}
        $folder.Metadata=[pscustomobject]@{OldIni=$null; NewIni=$ini; Content=(Set-USIniValues $ini.Text $values); TargetAttributes=[int][IO.File]::GetAttributes($folder.TargetPath); Attempted=$false}
    }
}
function Assert-USBindingRegistry($Binding,[string]$OldPath) {
    $value=$Binding.RegistryPrevious
    if ($value.Exists -and -not (Test-USSamePath $value.Expanded $OldPath) -and -not (Test-USSamePath $value.Expanded $Binding.Target)) {
        throw "$($Binding.Name) / $($Binding.Kind) 的 User Shell Folders 指向其他位置：$($value.Expanded)。不接管 OneDrive 或其他重定向。"
    }
}
function Test-USBindingNeedsUpdate($Binding,[string]$Current) {
    $value=Get-USRegistryValue 'User Shell Folders' $Binding.RegistryName
    (-not (Test-USSamePath $Current $Binding.Target)) -or (-not $value.Exists) -or (-not (Test-USSamePath $value.Expanded $Binding.Target))
}
function Assert-USBindingRegistryUnchanged($Binding) {
    $value=Get-USRegistryValue 'User Shell Folders' $Binding.RegistryName
    $before=$Binding.RegistryPrevious
    if ($value.Exists -ne $before.Exists -or $value.Kind -cne $before.Kind -or $value.Raw -cne $before.Raw) {
        if (-not $value.Exists -or -not (Test-USSamePath $value.Expanded $Binding.Target)) {throw "$($Binding.Name) 的 User Shell Folders 在操作中变化，已停止。"}
    }
}
function Get-USRepairPreview($Plan) {
    # 只读清单包含全部 11 个 API 入口、11 个 User Shell 值和六个旧兼容值。
    $rows=@(foreach ($folder in $Plan.Folders) {
        foreach ($binding in $folder.Bindings) {
            $via=if ($binding.Kind -eq 'Local') {'Local Known Folder'} else {'Known Folder'}
            [pscustomobject]@{Folder=$folder.Name; Via=$via; Current=$binding.Previous; Target=$folder.TargetPath; Exists=$true; Kind='API'; Raw=$binding.Previous}
            $value=$binding.RegistryPrevious
            $via=if ($binding.Kind -eq 'Local') {'Local / User Shell Folders'} else {'User Shell Folders'}
            [pscustomobject]@{Folder=$folder.Name; Via=$via; Current=$value.Expanded; Target=$folder.TargetPath; Exists=$value.Exists; Kind=$value.Kind; Raw=$value.Raw}
        }
        $definition=@($script:Folders | Where-Object Name -eq $folder.Name)[0]
        $value=Get-USRegistryValue 'Shell Folders' $definition.Reg
        [pscustomobject]@{Folder=$folder.Name; Via='Shell Folders'; Current=$value.Expanded; Target=$folder.TargetPath; Exists=$value.Exists; Kind=$value.Kind; Raw=$value.Raw}
    })
    $changes=@($rows | Where-Object {-not $_.Exists -or -not (Test-USSamePath $_.Current $_.Target)})
    $text=if ($changes.Count -eq 0) {'地址均与目标一致，无需改写路径；仍会检查并更新图标。'} else {
        (@($changes | ForEach-Object {
            $current=if ($_.Exists) {$_.Current} else {'（未设置）'}
            "$($_.Folder) / $($_.Via)$($script:NL)  当前：$current$($script:NL)  目标：$($_.Target)"
        })) -join ($script:NL+$script:NL)
    }
    # 确认期间设置若改变，重新显示清单，不沿用旧授权继续修正新发现的差异。
    $hash=[Security.Cryptography.SHA256]::Create()
    try {$signature=[Convert]::ToBase64String($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes(($rows | ConvertTo-Json -Depth 4 -Compress))))} finally {$hash.Dispose()}
    [pscustomobject]@{Text=$text; Signature=$signature; Changes=$changes}
}
function Get-USRegistryValue([string]$Key,[string]$Name) {
    $registry=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Software\Microsoft\Windows\CurrentVersion\Explorer\$Key",$false)
    try {
        if ($null -eq $registry -or $registry.GetValueNames() -notcontains $Name) { return [pscustomobject]@{Key=$Key; Name=$Name; Exists=$false; Kind=''; Raw=''; Expanded=''} }
        $raw=[string]$registry.GetValue($Name,'',[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        [pscustomobject]@{Key=$Key; Name=$Name; Exists=$true; Kind=[string]$registry.GetValueKind($Name); Raw=$raw; Expanded=[Environment]::ExpandEnvironmentVariables($raw)}
    } finally {if ($registry) {$registry.Dispose()}}
}
function Get-USRegistrySnapshot {
    foreach ($definition in $script:Folders) {
        foreach ($key in @('User Shell Folders','Shell Folders')) {
            Get-USRegistryValue $key $definition.Reg
            if ($definition.LocalId) {Get-USRegistryValue $key ('{'+$definition.LocalId+'}')}
        }
    }
}
function Set-USShellFolderValue([string]$Name, [string]$Path) {
    # 仅写旧软件兼容键的六个常用值；真实重定向仍由 Known Folder API 管理。
    $definitions=@($script:Folders | Where-Object Reg -eq $Name)
    if ($definitions.Count -ne 1) {throw "拒绝写入范围外的 Shell Folders 值：$Name"}
    $expected=Join-Path (Get-USContext).Root $definitions[0].Name
    if (-not (Test-USSamePath $Path $expected)) {throw '拒绝写入非 UserSpace 的兼容路径。'}
    $registry=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders')
    try {$registry.SetValue($Name,$expected,[Microsoft.Win32.RegistryValueKind]::String)}
    finally {if ($registry) {$registry.Dispose()}}
}
function Sync-USShellFolderCache($Journal) {
    # v4.3：API 正确不表示旧兼容键已刷新。先验收其他 38 项，再同步这个键。
    # 状态查询仍完全只读；仅已确认的初始化/升级能调用本步骤。
    $verification=Invoke-USFreshVerification
    $failed=@($verification.Checks | Where-Object {-not $_.Pass -and $_.Via -ne 'Shell Folders'})
    if ($failed.Count -gt 0) {
        $Journal.State.Details.Verification=$verification
        throw ("系统入口或图标验收未通过，未同步兼容值："+$script:NL+((@($failed | ForEach-Object {"$($_.Folder)/$($_.Via): $($_.Actual) $($_.Error)"})) -join $script:NL))
    }
    $context=Get-USContext
    $rows=@(foreach ($definition in $script:Folders) {
        $target=Join-Path $context.Root $definition.Name
        $before=Get-USRegistryValue 'Shell Folders' $definition.Reg
        if ($before.Exists -and (Test-USSamePath $before.Expanded $target)) {continue}
        [pscustomobject]@{Folder=$definition.Name; Name=$definition.Reg; Before=$before; Target=$target; Attempted=$false; Updated=$false}
    })
    $Journal.State.Details.CompatibilityUpdates=$rows
    if ($rows.Count -eq 0) {return}
    $Journal.State.Status='SyncingShellFolders'
    Save-USState $Journal.State $Journal.Path
    foreach ($row in $rows) {
        $definition=@($script:Folders | Where-Object Reg -eq $row.Name)[0]
        # 写前再次确认权威位置与目标目录，避免把其他程序刚改的重定向盖回去。
        foreach ($id in @($definition.Id,$definition.LocalId)) {
            if ($id -and -not (Test-USSamePath (Get-USKnownPath $id) $row.Target)) {throw "$($row.Folder) 的系统入口已变化，停止同步兼容值。"}
        }
        if (-not (Test-USSamePath (Get-USRegistryValue 'User Shell Folders' $row.Name).Expanded $row.Target)) {throw "$($row.Folder) 的 User Shell Folders 已变化，停止同步兼容值。"}
        Assert-USPlainPath $row.Target
        if (-not [IO.Directory]::Exists($row.Target)) {throw "目标目录已消失：$($row.Target)"}
        $current=Get-USRegistryValue 'Shell Folders' $row.Name
        if ($current.Exists -ne $row.Before.Exists -or $current.Kind -cne $row.Before.Kind -or $current.Raw -cne $row.Before.Raw) {throw "$($row.Folder) 的兼容值在操作中变化，已停止。"}
        $row.Attempted=$true
        Save-USState $Journal.State $Journal.Path
        Set-USShellFolderValue $row.Name $row.Target
        $after=Get-USRegistryValue 'Shell Folders' $row.Name
        if (-not $after.Exists -or $after.Kind -ne 'String' -or -not (Test-USSamePath $after.Raw $row.Target)) {throw "$($row.Folder) 的 Shell Folders 写入后回读不一致。"}
        $row.Updated=$true
        Save-USState $Journal.State $Journal.Path
    }
}
function Write-USFolderMetadata($Folder) {
    Assert-USPlainPath $Folder.TargetPath
    $meta=$Folder.Metadata
    $current=Get-USIniSnapshot $Folder.TargetPath
    if ($current.Exists -ne $meta.NewIni.Exists -or $current.Bytes -cne $meta.NewIni.Bytes) {throw "desktop.ini 在预检后变化，已停止：$($current.Path)"}
    $path=$current.Path
    $temporary=Join-Path $Folder.TargetPath ('.userspace-'+[guid]::NewGuid().ToString('N')+'.tmp')
    $encoding=[Text.UnicodeEncoding]::new($false,$true)
    [byte[]]$bytes=$encoding.GetPreamble()+$encoding.GetBytes($meta.Content)
    $stream=[IO.File]::Open($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try {$stream.Write($bytes,0,$bytes.Length); $stream.Flush($true)} finally {$stream.Dispose()}
    if ($current.Exists) {
        [IO.File]::SetAttributes($path,([IO.FileAttributes]$current.Attributes -band (-bnot [IO.FileAttributes]::ReadOnly)))
        try {[IO.File]::Replace($temporary,$path,[NullString]::Value)} catch {
            [IO.File]::SetAttributes($path,[IO.FileAttributes]$current.Attributes)
            throw
        }
    } else {[IO.File]::Move($temporary,$path)}
    [IO.File]::SetAttributes($path,([IO.FileAttributes]$current.Attributes -bor [IO.FileAttributes]::Hidden -bor [IO.FileAttributes]::System))
    # 只设目录自身的 ReadOnly 位以启用图标；不把目录内文件设为只读。
    [IO.File]::SetAttributes($Folder.TargetPath,([IO.File]::GetAttributes($Folder.TargetPath) -bor [IO.FileAttributes]::ReadOnly))
    Send-USFolderNotice $Folder.TargetPath
}


function Get-USVerification {
    $context=Get-USContext
    $checks=[Collections.Generic.List[object]]::new()
    foreach ($definition in $script:Folders) {
        $expected=Join-Path $context.Root $definition.Name
        $probes=[ordered]@{KnownFolder=$definition.Id}
        if ($definition.LocalId) {$probes['LocalKnownFolder']=$definition.LocalId}
        foreach ($probe in $probes.GetEnumerator()) {
            $actual=''; $errorText=''
            try {$actual=Get-USKnownPath $probe.Value} catch {$errorText=$_.Exception.Message}
            $checks.Add([pscustomobject]@{Folder=$definition.Name; Via=$probe.Key; Expected=$expected; Actual=$actual; Pass=(!$errorText -and (Test-USSamePath $actual $expected)); Error=$errorText})
        }
        foreach ($key in @('User Shell Folders','Shell Folders')) {
            $actual=''; $errorText=''
            try {$actual=(Get-USRegistryValue $key $definition.Reg).Expanded} catch {$errorText=$_.Exception.Message}
            $checks.Add([pscustomobject]@{Folder=$definition.Name; Via=$key; Expected=$expected; Actual=$actual; Pass=(!$errorText -and (Test-USSamePath $actual $expected)); Error=$errorText})
        }
        if ($definition.LocalId) {
            $actual=''; $errorText=''
            try {$actual=(Get-USRegistryValue 'User Shell Folders' ('{'+$definition.LocalId+'}')).Expanded} catch {$errorText=$_.Exception.Message}
            $checks.Add([pscustomobject]@{Folder=$definition.Name; Via='Local User Shell Folders'; Expected=$expected; Actual=$actual; Pass=(!$errorText -and (Test-USSamePath $actual $expected)); Error=$errorText})
        }
        if ($definition.Legacy -ge 0) {
            foreach ($via in @('LegacyAPI','.NET')) {
                $actual=''; $errorText=''
                try {$actual=if ($via -eq 'LegacyAPI') {Get-USLegacyPath $definition.Legacy} else {Get-USNetPath $definition.Net}} catch {$errorText=$_.Exception.Message}
                $checks.Add([pscustomobject]@{Folder=$definition.Name; Via=$via; Expected=$expected; Actual=$actual; Pass=(!$errorText -and (Test-USSamePath $actual $expected)); Error=$errorText})
            }
        }
        $ok=$false; $errorText=''
        try {
            Assert-USPlainPath $expected
            $ini=Get-USIniSnapshot $expected
            $icon=Get-USIconDefinition $definition.Id
            $ok=[IO.Directory]::Exists($expected) -and $ini.Recognized -and
                (([IO.File]::GetAttributes($expected) -band [IO.FileAttributes]::ReadOnly) -ne 0) -and
                (($ini.Attributes -band 6) -eq 6) -and
                ($ini.Text -match ('(?im)^\s*IconResource\s*=\s*'+[regex]::Escape($icon.Icon)+'\s*$'))
        } catch {$errorText=$_.Exception.Message}
        $checks.Add([pscustomobject]@{Folder=$definition.Name; Via='IconMetadata'; Expected=$expected; Actual=$expected; Pass=$ok; Error=$errorText})
    }
    [pscustomobject]@{Version=4; Sid=$context.Sid; User=$context.User; Profile=$context.Profile; ProcessId=$PID; Checks=@($checks.ToArray()); Passed=(@($checks.ToArray() | Where-Object {-not $_.Pass}).Count -eq 0)}
}
function Get-USRunnerPath {
    $context=Get-USContext
    $candidate=$PSScriptRoot
    if (-not [IO.Directory]::Exists($candidate)) {
        # 工具本身可能随 Downloads 一起移入 UserSpace。
        foreach ($definition in $script:Folders) {
            $old=(Join-Path $context.Profile $definition.Name).TrimEnd('\')+'\'
            if ($PSScriptRoot.StartsWith($old,[StringComparison]::OrdinalIgnoreCase)) {
                $candidate=Join-Path (Join-Path $context.Root $definition.Name) $PSScriptRoot.Substring($old.Length)
                break
            }
        }
    }
    Assert-USPlainPath $candidate
    foreach ($name in $script:RunnerHashes.Keys) {
        $path=Join-Path $candidate $name
        $entry=[UserSpaceInitV4.Native]::Inspect($path)
        if (-not $entry.Exists -or $entry.Reparse -or $entry.Directory -or
            (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne $script:RunnerHashes[$name]) {
            throw '找不到本次运行对应的完整程序。请从 UserSpace 中重新打开本工具并查看状态。'
        }
    }
    Join-Path $candidate 'UserSpace.ps1'
}
function Invoke-USFreshVerification {
    $runner=Get-USRunnerPath
    $engine=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $start=[Diagnostics.ProcessStartInfo]::new()
    $start.FileName=$engine
    $start.Arguments='-NoLogo -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "'+$runner+'" -Action Verify'
    $start.UseShellExecute=$false; $start.CreateNoWindow=$true
    $start.RedirectStandardOutput=$true; $start.RedirectStandardError=$true
    # 从 PowerShell 7 启动 Windows PowerShell 时，不继承前者的模块搜索目录。
    # 验收只用系统自带模块；这项设置仅作用于子进程，不修改用户环境变量。
    $start.EnvironmentVariables['PSModulePath']=Join-Path (Split-Path $engine -Parent) 'Modules'
    $start.StandardOutputEncoding=[Text.UTF8Encoding]::new($false)
    $start.StandardErrorEncoding=[Text.UTF8Encoding]::new($false)
    $start.WorkingDirectory=$env:TEMP
    $process=[Diagnostics.Process]::new(); $process.StartInfo=$start
    try {
        if (-not $process.Start()) {throw '无法启动验收进程。'}
        $stdout=$process.StandardOutput.ReadToEndAsync()
        $stderr=$process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(30000)) {
            $process.Kill()
            throw '验收进程超过 30 秒，已停止该验收进程。目录内容保留，请重开工具查看状态。'
        }
        $output=@($stdout.GetAwaiter().GetResult() -split '\r?\n')
        $errors=$stderr.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) {throw "新进程验收未运行成功：$errors $($output -join ' ')"}
    } finally {$process.Dispose()}
    $messages=@($output | Where-Object {$_ -is [string] -and $_.StartsWith('USV4:')})
    if ($messages.Count -ne 1) {throw '新进程没有返回完整的验收结果。'}
    $json=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($messages[0].Substring(5)))
    $result=$json | ConvertFrom-Json
    $context=Get-USContext
    if ($result.Version -ne 4 -or $result.Sid -ne $context.Sid -or $result.ProcessId -eq $PID -or
        -not (Test-USSamePath $result.Profile $context.Profile) -or @($result.Checks).Count -ne 44) {
        throw '验收进程的账户、版本或检查数量不一致。'
    }
    $result
}

function Save-USState($State, [string]$Path) {
    # 小型操作记录；先写新文件再替换。上一份完整记录留在 .previous。
    Assert-USPlainPath (Split-Path -Parent $Path)
    foreach ($item in @($Path, "$Path.previous")) {
        $entry = [UserSpaceInitV4.Native]::Inspect($item)
        if ($entry.Exists -and ($entry.Directory -or $entry.Reparse)) { throw "状态文件位置异常：$item" }
    }
    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    $encoding = [Text.UTF8Encoding]::new($true)
    [byte[]]$bytes = $encoding.GetPreamble() + $encoding.GetBytes(($State | ConvertTo-Json -Depth 8))
    $stream = [IO.File]::Open($temporary, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
    if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temporary, $Path, "$Path.previous", $true) }
    else { [IO.File]::Move($temporary, $Path) }
}
function New-USState([string]$Operation, $Details) {
    $context = Get-USContext
    Assert-USPlainPath $context.StateRoot
    [void][IO.Directory]::CreateDirectory($context.StateRoot)
    $path = Join-Path $context.StateRoot ("{0}-{1}-{2}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $Operation, [guid]::NewGuid().ToString('N'))
    $state = [pscustomobject]@{
        SchemaVersion=4; Operation=$Operation; Sid=$context.Sid; User=$context.User
        CreatedAt=(Get-Date).ToString('o'); Status='Prepared'; Details=$Details; Error=$null
    }
    Save-USState $state $path
    [pscustomobject]@{ Path=$path; State=$state }
}


function Invoke-USInit {
    $plan=Get-USInitPlan
    Assert-USFreshPlan $plan
    $details=[pscustomobject]@{Folders=$plan.Folders; RegistryBefore=@(Get-USRegistrySnapshot); CompatibilityUpdates=@(); Verification=$null}
    $journal=New-USState 'Repair' $details
    try {
        foreach ($name in $plan.Presets) {
            $path=Join-Path $plan.Context.Root $name
            Assert-USPlainPath $path
            [void][IO.Directory]::CreateDirectory($path)
        }
        foreach ($folder in $plan.Folders) {
            foreach ($binding in $folder.Bindings) {
                if (-not (Test-USSamePath (Get-USKnownPath $binding.Id) $binding.Previous)) {throw "$($folder.Name) 的设置在操作中发生变化。"}
            }
            foreach ($move in $folder.Moves) {
                Assert-USMovePaths $move.Source $move.Target $folder.OldPath $folder.TargetPath
                $move.Attempted=$true; $journal.State.Status='MovingContents'
                Save-USState $journal.State $journal.Path
                Move-USItem $move.Source $move.Target
                if (([UserSpaceInitV4.Native]::Inspect($move.Source)).Exists -or -not ([UserSpaceInitV4.Native]::Inspect($move.Target)).Exists) {throw '移动后的检查失败。'}
                $move.Moved=$true
                Save-USState $journal.State $journal.Path
            }
            Assert-USNoUserContents $folder.OldPath
        }
        foreach ($folder in $plan.Folders) {
            Assert-USNoUserContents $folder.OldPath
            foreach ($binding in $folder.Bindings) {
                $current=Get-USKnownPath $binding.Id
                if (-not (Test-USBindingNeedsUpdate $binding $current)) {continue}
                Assert-USBindingRegistryUnchanged $binding
                if (-not (Test-USSamePath $current $binding.Previous)) {throw "$($folder.Name) 的位置被其他程序修改，已停止。"}
                $binding.Attempted=$true; $journal.State.Status='SettingKnownFolders'
                Save-USState $journal.State $journal.Path
                Set-USKnownPath $binding.Id $binding.Target
                if (Test-USBindingNeedsUpdate $binding (Get-USKnownPath $binding.Id)) {throw "$($folder.Name) / $($binding.Kind) 回读不一致。"}
            }
            $folder.Metadata.Attempted=$true; $journal.State.Status='SettingIcons'
            Save-USState $journal.State $journal.Path
            Write-USFolderMetadata $folder
        }
        Sync-USShellFolderCache $journal
        $journal.State.Status='Verifying'
        Save-USState $journal.State $journal.Path
        $result=Invoke-USFreshVerification
        $journal.State.Details.Verification=$result
        if (-not $result.Passed) {
            $failed=@($result.Checks | Where-Object {-not $_.Pass} | ForEach-Object {"$($_.Folder)/$($_.Via): $($_.Actual) $($_.Error)"})
            throw ("入口或图标验收未通过："+$script:NL+($failed -join $script:NL))
        }
        $journal.State.Status='Verified'
        Save-USState $journal.State $journal.Path
    } catch {
        $failure=$_.Exception.Message
        $journal.State.Status='NeedsAttention'; $journal.State.Error=$failure
        try {Save-USState $journal.State $journal.Path} catch {Write-Warning '记录更新失败，请保留已有记录。'}
        # 部分文件已移动时不盲目搬回，避免覆盖其他程序新写入的数据。
        throw "操作未完整完成：$failure$($script:NL)请保留新旧目录。已移动文件留在新位置，尚未移动文件留在旧位置。$($script:NL)记录：$($journal.Path)"
    }
    $note=''
    $shortcutPath=Join-Path $plan.Context.Root 'Desktop\UserSpace.lnk'
    try {
        if (-not ([UserSpaceInitV4.Native]::Inspect($shortcutPath)).Exists) {
            $shell=New-Object -ComObject WScript.Shell
            try {
                $shortcut=$shell.CreateShortcut($shortcutPath)
                $shortcut.TargetPath=$plan.Context.Root; $shortcut.WorkingDirectory=$plan.Context.Root; $shortcut.Save()
            } finally {[void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell)}
        }
    } catch {$note="$($script:NL)快捷方式未创建：$($_.Exception.Message)"}
    "系统入口与图标元数据通过新进程的 44 项检查。请注销后重新登录，再打开游戏等程序。$($script:NL)旧目录尚未清理，可另点『清理旧空目录』。$($script:NL)记录：$($journal.Path)$note"
}
function Invoke-USUpgrade([string]$ConfirmedSignature='') {
    $plan=Get-USInitPlan
    Assert-USUpgradePlan $plan
    if ($ConfirmedSignature -and (Get-USRepairPreview $plan).Signature -cne $ConfirmedSignature) {throw '目录设置在确认期间发生变化。请重新打开修复并更新，核对新的差异清单。尚未修改设置。'}
    # RegistryBefore 的 Exists 字段保留“这个值原本不存在”的信息。
    $details=[pscustomobject]@{Folders=$plan.Folders; RegistryBefore=@(Get-USRegistrySnapshot); CompatibilityUpdates=@(); Verification=$null}
    $journal=New-USState 'Upgrade' $details
    try {
        foreach ($folder in $plan.Folders) {
            Assert-USPlainPath $folder.TargetPath
            if (-not [IO.Directory]::Exists($folder.TargetPath)) {throw "目标目录在操作中消失：$($folder.TargetPath)"}
            foreach ($binding in $folder.Bindings) {
                $current=Get-USKnownPath $binding.Id
                if (-not (Test-USSamePath $current $binding.Previous)) {throw "$($folder.Name) 的位置被其他程序修改，已停止。"}
                if (-not (Test-USBindingNeedsUpdate $binding $current)) {continue}
                Assert-USBindingRegistryUnchanged $binding
                $binding.Attempted=$true; $journal.State.Status='SettingKnownFolders'
                Save-USState $journal.State $journal.Path
                Set-USKnownPath $binding.Id $binding.Target
                if (Test-USBindingNeedsUpdate $binding (Get-USKnownPath $binding.Id)) {throw "$($folder.Name) / $($binding.Kind) 回读不一致。"}
            }
            $folder.Metadata.Attempted=$true; $journal.State.Status='SettingIcons'
            Save-USState $journal.State $journal.Path
            Write-USFolderMetadata $folder
        }
        Sync-USShellFolderCache $journal
        $journal.State.Status='Verifying'; Save-USState $journal.State $journal.Path
        $result=Invoke-USFreshVerification
        $journal.State.Details.Verification=$result
        if (-not $result.Passed) {
            $failed=@($result.Checks | Where-Object {-not $_.Pass} | ForEach-Object {"$($_.Folder)/$($_.Via): $($_.Actual) $($_.Error)"})
            throw ("入口或图标验收未通过："+$script:NL+($failed -join $script:NL))
        }
        $journal.State.Status='Verified'; Save-USState $journal.State $journal.Path
    } catch {
        $failure=$_.Exception.Message
        $journal.State.Status='NeedsAttention'; $journal.State.Error=$failure
        try {Save-USState $journal.State $journal.Path} catch {Write-Warning '记录更新失败，请保留已有记录。'}
        throw "升级未完整完成：$failure$($script:NL)本模式没有搬动用户文件或清理旧目录；部分入口或图标可能已经更新。请保留记录并查看状态。$($script:NL)记录：$($journal.Path)"
    }
    "UserSpace 的系统入口与图标通过新进程的 44 项检查。$($script:NL)用户文件、目录内链接及旧目录均保留原位。修正入口后软件会读取新位置，旧位置的数据没有自动搬入。$($script:NL)请注销后重新登录，再检查常用软件。$($script:NL)记录：$($journal.Path)"
}
function Get-USCleanupPlan {
    $context=Get-USContext
    foreach ($definition in $script:Folders) {
        $path=Join-Path $context.Profile $definition.Name
        $eligible=$false; $reason=''
        try {
            Assert-USPlainPath $path
            if (-not [IO.Directory]::Exists($path)) {$reason='不存在，无需清理'}
            else {Assert-USNoUserContents $path; $eligible=$true; $reason='空目录或仅含已识别的 desktop.ini'}
        } catch {$reason=$_.Exception.Message}
        [pscustomobject]@{Name=$definition.Name; Path=$path; Eligible=$eligible; Reason=$reason}
    }
}
function Invoke-USCleanup([string[]]$Paths) {
    if (-not $Paths -or $Paths.Count -eq 0) {return '没有需要清理的目录。'}
    $context=Get-USContext
    $allowed=@($script:Folders | ForEach-Object {Join-Path $context.Profile $_.Name})
    $selected=@($Paths | ForEach-Object {ConvertTo-USPath $_} | Select-Object -Unique)
    foreach ($path in $selected) {
        if ($allowed -notcontains (ConvertTo-USPath $path)) {throw "拒绝清理范围外路径：$path"}
        Assert-USNoUserContents $path
    }
    $verification=Invoke-USFreshVerification
    if (-not $verification.Passed) {throw '系统入口/图标尚未全部通过检查，不能清理旧目录。'}
    $rows=@($selected | ForEach-Object {[pscustomobject]@{Path=$_; Ini=$null; IniArchive=''; OriginalAttributes=0; Attempted=$false; Removed=$false}})
    $journal=New-USState 'Cleanup' $rows
    try {
        foreach ($row in $rows) {
            # 删除前核验绝对路径、入口类型及内容；只调用非递归的空目录删除。
            if ($allowed -notcontains (ConvertTo-USPath $row.Path)) {throw '清理目标不在已批准列表。'}
            Assert-USNoUserContents $row.Path
            if (-not [IO.Directory]::Exists($row.Path)) {continue}
            $row.Ini=Get-USIniSnapshot $row.Path
            $row.OriginalAttributes=[int][IO.File]::GetAttributes($row.Path)
            $row.Attempted=$true
            if ($row.Ini.Exists) {$row.IniArchive=$journal.Path+'.'+(Split-Path $row.Path -Leaf)+'.desktop.ini'}
            Save-USState $journal.State $journal.Path
            if ($row.Ini.Exists) {
                # 把元数据原文件移到记录旁，保留恢复所需内容。
                Assert-USPlainPath (Split-Path $row.IniArchive -Parent)
                Move-USItem $row.Ini.Path $row.IniArchive
            }
            Assert-USPlainPath $row.Path
            [IO.File]::SetAttributes($row.Path,([IO.File]::GetAttributes($row.Path) -band (-bnot ([IO.FileAttributes]::ReadOnly -bor [IO.FileAttributes]::System -bor [IO.FileAttributes]::Hidden))))
            [IO.Directory]::Delete($row.Path,$false)
            $row.Removed=$true
            Send-USFolderNotice (Split-Path $row.Path -Parent)
            Save-USState $journal.State $journal.Path
        }
        $journal.State.Status='Completed'; Save-USState $journal.State $journal.Path
    } catch {
        $failure=$_.Exception.Message
        $journal.State.Status='NeedsAttention'; $journal.State.Error=$failure
        try {Save-USState $journal.State $journal.Path} catch {}
        throw "清理停止：$failure$($script:NL)未递归删除任何内容。保留的元数据和记录：$($journal.Path)"
    }
    "已清理旧空目录：$($script:NL)$((@($rows | Where-Object Removed | ForEach-Object Path)) -join $script:NL)$($script:NL)元数据已保留在记录旁：$($journal.Path)$($script:NL)写死旧路径的软件以后仍可能重新创建它们。"
}
function Get-USStatus {
    $result=Invoke-USFreshVerification
    "账户：$($result.User)$($script:NL)新进程编号：$($result.ProcessId)"
    "完整验收："+$(if ($result.Passed) {'通过（44 项）'} else {'未全部通过，尚不能清理旧目录'})
    foreach ($check in $result.Checks) {
        $label=if ($check.Pass) {'通过'} else {'未通过'}
        "$($check.Folder) / $($check.Via)：$label$($script:NL)  $($check.Actual) $($check.Error)"
    }
    "$($script:NL)旧目录："
    foreach ($entry in Get-USCleanupPlan) {"$($entry.Name)：$($entry.Reason)"}
    "$($script:NL)接口检查不代表所有软件实测通过。写死路径、已有收藏位置及 Saved Games/AppData 存档不属于这六个目录重定向。"
}
Export-ModuleMember -Function Get-USContext,Get-USInitPlan,Assert-USFreshPlan,Invoke-USInit,Assert-USUpgradePlan,Get-USRepairPreview,Invoke-USUpgrade,Get-USStatus,Get-USVerification,Get-USCleanupPlan,Invoke-USCleanup
