// 初始化使用的接口：查询/设置目录位置、读取路径属性、同卷无覆盖移动。
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

namespace UserSpaceInitV4
{
    public sealed class Entry
    {
        public bool Exists;
        public bool Directory;
        public bool Reparse;
    }

    public static class Native
    {
        [DllImport("shell32.dll", ExactSpelling = true)]
        static extern int SHGetKnownFolderPath(ref Guid id, uint flags, IntPtr token, out IntPtr path);
        [DllImport("shell32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
        static extern int SHSetKnownFolderPath(ref Guid id, uint flags, IntPtr token, string path);
        [DllImport("shell32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
        static extern int SHGetFolderPathW(IntPtr hwnd, int csidl, IntPtr token, uint flags, StringBuilder path);
        [DllImport("shell32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
        static extern void SHChangeNotify(int eventId, uint flags, string item1, IntPtr item2);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        static extern uint GetFileAttributesW(string path);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        static extern bool MoveFileExW(string source, string destination, uint flags);

        public static string KnownPath(string folderId, bool defaultPath)
        {
            Guid id = new Guid(folderId);
            IntPtr pointer = IntPtr.Zero;
            try
            {
                // 只查询位置，不创建目录；defaultPath 表示查询 Windows 默认位置。
                int hr = SHGetKnownFolderPath(ref id, defaultPath ? 0x4400u : 0x4000u, IntPtr.Zero, out pointer);
                Marshal.ThrowExceptionForHR(hr);
                return Marshal.PtrToStringUni(pointer);
            }
            finally { if (pointer != IntPtr.Zero) Marshal.FreeCoTaskMem(pointer); }
        }

        public static void SetKnownPath(string folderId, string path)
        {
            Guid id = new Guid(folderId);
            Marshal.ThrowExceptionForHR(SHSetKnownFolderPath(ref id, 0, IntPtr.Zero, path));
        }

        // 仅作兼容性验收：模拟仍使用旧接口的程序读取当前目录，不创建目录。
        public static string LegacyPath(int csidl)
        {
            var path = new StringBuilder(260);
            Marshal.ThrowExceptionForHR(SHGetFolderPathW(IntPtr.Zero, csidl | 0x4000, IntPtr.Zero, 0, path));
            return path.ToString();
        }

        public static void NotifyFolder(string path)
        {
            // SHCNE_UPDATEDIR | SHCNE_ATTRIBUTES, SHCNF_PATHW | SHCNF_FLUSHNOWAIT。
            SHChangeNotify(0x1000 | 0x800, 0x0005 | 0x2000, path, IntPtr.Zero);
        }

        public static void MoveEntry(string source, string destination)
        {
            // flags=0：同卷移动，不覆盖现有目标；不使用跨卷复制删除或延迟删除。
            if (!MoveFileExW(source, destination, 0))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot move: " + source + " -> " + destination);
        }

        public static Entry Inspect(string path)
        {
            // 检查路径自身的属性，包括目标失联的链接；不修改或跟随链接创建目录。
            uint attr = GetFileAttributesW(path);
            if (attr == 0xffffffff)
            {
                int error = Marshal.GetLastWin32Error();
                if (error == 2 || error == 3) return new Entry();
                throw new Win32Exception(error, "Cannot inspect: " + path);
            }
            return new Entry
            {
                Exists = true,
                Directory = (attr & 0x10) != 0,
                Reparse = (attr & 0x400) != 0
            };
        }
    }
}
