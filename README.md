# Windows UserSpace

> 开发说明：本项目当前版本由维护者提出需求、委托 OpenAI Codex 编写和修改。维护者是非专业开发者，能理解代码的基本逻辑，负责确定使用方式并反馈实际测试结果。请先备份数据，再使用涉及文件移动和系统设置的功能。
>
> Development disclosure: OpenAI Codex wrote and revised the current version at the maintainer's request. The maintainer is a non-professional developer who can follow the basic code logic and contributes requirements and hands-on testing feedback. Back up your data before using features that move files or change Windows settings.

> **推荐使用时机：完成 Windows 首次设置（OOBE，Out-of-Box Experience）后，尚未存入个人文件或积累应用数据时，执行“初始化 UserSpace”。** 脚本没有 OOBE 状态或空目录限制；遇到已有内容仍会尝试迁移。对于已经长期使用的系统，请先备份并单独评估迁移影响。已有 UserSpace 的维护可使用“修复并更新”，文件保留原位。
>
> **Recommended timing: initialize UserSpace after Windows first-run setup (OOBE, Out-of-Box Experience), before adding personal files or accumulating application data.** The script does not enforce OOBE status or empty folders; it will attempt to move existing content. Back up and assess migration risks before using initialization on an established system. For an existing UserSpace setup, Repair and update keeps files in place.

[中文](#中文) · [English](#english)

## 中文

### 这是什么

UserSpace 将 Windows 的常用个人文件夹集中到 `%USERPROFILE%\UserSpace`。它借鉴了 Linux 中集中管理用户目录的习惯，使用 Windows 的系统目录接口实现重定向。

许多软件会在用户根目录创建配置和缓存。UserSpace 提供一个相对独立的个人文件入口，方便整理资料和项目。用户账户、AppData 和 OneDrive 保持原位。

初始化后，目录结构如下：

```text
%USERPROFILE%\UserSpace\
├── Desktop       ← 系统桌面
├── Documents     ← 系统文档
├── Downloads     ← 系统下载
├── Music         ← 系统音乐
├── Pictures      ← 系统图片
├── Videos        ← 系统视频
├── Assets
├── Games
├── Projects
├── Resources
├── Utils
└── VSTPlugins
```

前六项对应 Windows 系统目录，后六项是普通文件夹。你可以自行添加其他目录。UserSpace 本身是本地普通目录，卷挂载、junction 和 symlink 由你另行管理。

### 开始使用

适用环境为 Windows 11，启动器使用系统自带的 Windows PowerShell 5.1。请登录需要配置的日常账户，下载并解压完整仓库，然后双击 `启动.cmd`。`app` 文件夹需要与启动器放在一起。

**初始化和修复成功后会自动注销。请先保存工作并关闭相关软件。** 开始前会显示确认窗口，默认选中“取消”。取消、操作失败、查看状态和清理旧空目录都不会触发注销。

界面默认跟随 Windows 显示语言：中文使用简体中文，其他语言使用英语。主窗口底部可以手动切换，选择仅在本次运行中有效。翻译来自本地字典，无需联网。

| 按钮 | 适用情况与操作 |
| --- | --- |
| 修复并更新（保留原文件） | 已有 UserSpace 时使用。先列出当前位置与目标位置的差异，确认后修正系统设置并更新图标。六个目标目录必须已存在，现有文件和链接保留原位。 |
| 初始化 UserSpace（迁入已有文件） | 推荐用于新装系统完成 OOBE 后的首次配置。补建 12 个预设目录，将六个系统目录中的已有内容迁入对应目标，再更新系统位置和图标。同名冲突会停止操作并保留两边内容。 |
| 查看状态 | 只读检查目录位置、兼容设置和图标，显示旧目录的清理条件。结果可以复制。 |
| 清理旧空目录 | 列出可清理的旧位置，另行确认后删除空目录。残留的已识别 `desktop.ini` 会先保存到操作记录旁。普通文件、子目录或链接会阻止清理。 |

“修复并更新”适合更新已有设置。它保留旧位置的数据；软件改为读取 UserSpace 后，你可能需要单独导入这些数据。长期使用的电脑可能存在文件占用、固定路径或相对链接依赖。文件移动检查无法验证所有软件的依赖关系，因此请先备份并核对应用的迁移要求。

### 系统位置如何生效

工具设置六个常用 Known Folder 和五个 Local Known Folder，将对应的 `User Shell Folders` 配置指向 UserSpace。系统接口检查通过后，再同步 `Shell Folders` 中六个旧式兼容值，并更新文件夹图标。每次初始化或修复结束前，会在新进程中执行 44 项检查。

按 Windows 系统接口查找目录的软件，应该能读到新位置。使用固定路径、历史收藏或独立存档设置的软件，需要单独核对。`Saved Games` 和 `AppData` 中的数据仍由软件原有规则管理。

资源管理器的“用户名”视图可能继续显示桌面、下载等入口。这些入口可以指向 UserSpace 中的同一文件夹。**请先核实物理路径，避免把入口当成重复目录删除。**

### 范围与操作记录

初始化支持同一卷内的移动。六个系统目录及其目标需要是普通本地目录；遇到 OneDrive 备份位置、其他自定义重定向或相关路径上的目录链接时，预检会停止，留给你另行处理。修复模式会保留自建目录中的现有链接。

设置和图标备份、操作记录保存在当前账户的 `%LOCALAPPDATA%\UserSpaceBootstrap`。这些记录用于排查问题，包含本机路径、账户标识等信息，公开分享前请脱敏。设置备份不能代替文件备份。

操作中断时，部分设置或文件可能已经改变。工具会记录完成情况并提示查看状态，随后由你处理冲突或占用。它没有一键撤销功能。

### 文件与命令行

日常使用只需打开 `启动.cmd`。想了解内部实现，可以阅读 [模块说明](模块说明.md)。`app/UserSpace.Strings.json` 保存中英文文案；系统返回的错误信息可能沿用 Windows 的语言。

以下命令在仓库根目录运行，均为只读：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\app\UserSpace.ps1 -Action Plan -Language zh-CN
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\app\UserSpace.ps1 -Action Status -Language en
```

## English

### Purpose

UserSpace brings the main Windows personal folders together under `%USERPROFILE%\UserSpace`. Inspired by the organization of Linux user directories, it uses Windows folder-location interfaces to redirect Desktop, Documents, Downloads, Music, Pictures and Videos.

Applications often place configuration and cache folders in the user profile root. UserSpace gives personal files and projects a separate place within that profile. The account profile, AppData and OneDrive stay in their existing locations.

Setup also creates six ordinary folders: Assets, Games, Projects, Resources, Utils and VSTPlugins. You can add more folders yourself. UserSpace is a regular local directory; volume mounts, junctions and symbolic links are managed separately.

### Getting started

The intended environment is Windows 11. The launcher uses the included Windows PowerShell 5.1. Sign in to the account you want to configure, download and extract the complete repository, then double-click `启动.cmd`. Keep the `app` folder beside the launcher.

**Successful initialization or repair automatically signs you out. Save your work and close your apps first.** Each operation begins with a confirmation dialog, with Cancel selected by default. Canceling, a failed operation, viewing status and cleaning up old folders do not trigger sign-out.

The interface follows the Windows display language: Simplified Chinese for Chinese locales, English otherwise. The selector at the bottom of the main window lets you switch languages for the current session. Translation uses a local dictionary and needs no network connection.

| Button | When to use it and what it does |
| --- | --- |
| Repair and update (keep files in place) | For an existing UserSpace setup. Review location differences, then update Windows settings and folder icons. The six target folders must already exist. Files and links stay where they are. |
| Initialize UserSpace (move existing files) | Recommended for initial configuration after OOBE on a fresh Windows installation. Create missing preset folders, move existing content from the six Windows folders, then update locations and icons. A name conflict stops the operation and keeps both copies. |
| View status | Read-only checks of folder locations, compatibility settings, icons and old-folder cleanup eligibility. Results can be copied. |
| Clean up old empty folders | Review eligible old locations, then confirm removal. Any recognized residual `desktop.ini` is saved beside the operation record first. Files, subfolders or links prevent removal. |

Repair keeps data at the old locations. After apps begin using UserSpace, you may need to import that data separately. Established systems may have locked files, fixed paths or relative-link dependencies. File-move checks cannot verify every app's dependencies. Back up your data and review app-specific migration requirements first.

### How redirection works

The tool sets six common Known Folders and five Local Known Folders, with their corresponding `User Shell Folders` settings. After Windows interface checks pass, it synchronizes six legacy `Shell Folders` values and updates folder icons. A new process runs 44 checks before initialization or repair can finish successfully.

Apps that ask Windows for these folder locations should receive the UserSpace paths. Check apps using fixed paths, saved favorites or their own save-data settings separately. Data in `Saved Games` and `AppData` stays under the apps' existing rules.

Explorer's user-name view may still show Desktop, Downloads and similar entries pointing to the same folders in UserSpace. **Verify the physical paths before deleting apparent duplicates.**

### Scope and records

Initialization supports moves within one volume. The six Windows folders and their targets must be regular local directories. Preflight stops at OneDrive backup locations, other custom redirects or directory links along the relevant paths, so those setups can be handled separately. Repair leaves links in custom folders in place.

Settings, icon backups and operation records are stored under `%LOCALAPPDATA%\UserSpaceBootstrap` for the current account. Records contain machine-specific paths and account identifiers; redact them before sharing. Settings backups are not file backups.

An interrupted operation may leave some settings or files already changed. The tool records progress and reports the error so you can check the status and resolve conflicts or locked files. There is no one-click undo.

### Files and command line

Open `启动.cmd` for normal use. [Module notes](模块说明.md#english) describe the implementation in Chinese and English. `app/UserSpace.Strings.json` contains both languages. Errors returned by Windows may remain in the operating system's language.

Read-only commands, run from the repository root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\app\UserSpace.ps1 -Action Plan -Language en
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\app\UserSpace.ps1 -Action Status -Language en
```

## License

GNU GPL v3. See [LICENSE](LICENSE).
