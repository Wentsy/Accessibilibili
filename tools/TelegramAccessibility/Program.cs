using System.Collections.Concurrent;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows.Automation;
using WinForms = System.Windows.Forms;

namespace TelegramAccessibility;

internal static class Program
{
    private const int WhKeyboardLl = 13;
    private const int WmKeyDown = 0x0100;
    private const int WmSysKeyDown = 0x0104;
    private const int VkTab = 0x09;
    private const int VkReturn = 0x0D;
    private const int VkSpace = 0x20;
    private const int VkShift = 0x10;
    private const ulong InjectedMarker = 0x5849584954474141UL; // "XIXITGAA"

    private static readonly BlockingCollection<Action> Work = new();
    private static readonly LowLevelKeyboardProc HookProc = KeyboardHook;
    private static IntPtr _hook;
    private static volatile bool _enabled = true;
    private static Thread? _worker;
    private static WinForms.NotifyIcon? _tray;

    [STAThread]
    private static void Main()
    {
        using var mutex = new Mutex(true, @"Local\XiXiTelegramAccessibility", out var created);
        if (!created)
        {
            WinForms.MessageBox.Show(
                "Telegram 無障礙鍵盤增強已經在執行。",
                "TelegramAccessibility",
                WinForms.MessageBoxButtons.OK,
                WinForms.MessageBoxIcon.Information);
            return;
        }

        WinForms.ApplicationConfiguration.Initialize();
        EnsureTelegramRunning();

        _worker = new Thread(WorkerLoop)
        {
            IsBackground = true,
            Name = "TelegramAccessibility.UIAWorker"
        };
        _worker.SetApartmentState(ApartmentState.MTA);
        _worker.Start();

        _hook = SetWindowsHookEx(WhKeyboardLl, HookProc, GetModuleHandle(null), 0);
        if (_hook == IntPtr.Zero)
        {
            WinForms.MessageBox.Show(
                "無法安裝鍵盤攔截器。請確認 TelegramAccessibility 與 Telegram 使用相同權限執行。",
                "TelegramAccessibility",
                WinForms.MessageBoxButtons.OK,
                WinForms.MessageBoxIcon.Error);
            return;
        }

        var menu = new WinForms.ContextMenuStrip();
        var enabledItem = new WinForms.ToolStripMenuItem("啟用鍵盤增強") { Checked = true, CheckOnClick = true };
        enabledItem.CheckedChanged += (_, _) => _enabled = enabledItem.Checked;
        var exitItem = new WinForms.ToolStripMenuItem("結束");
        exitItem.Click += (_, _) => WinForms.Application.Exit();
        menu.Items.Add(enabledItem);
        menu.Items.Add(new WinForms.ToolStripSeparator());
        menu.Items.Add(exitItem);

        _tray = new WinForms.NotifyIcon
        {
            Icon = System.Drawing.SystemIcons.Application,
            Text = "Telegram 無障礙鍵盤增強",
            Visible = true,
            ContextMenuStrip = menu
        };

        WinForms.Application.ApplicationExit += (_, _) =>
        {
            _tray.Visible = false;
            _tray.Dispose();
            if (_hook != IntPtr.Zero)
            {
                UnhookWindowsHookEx(_hook);
                _hook = IntPtr.Zero;
            }
            Work.CompleteAdding();
        };

        WinForms.Application.Run();
    }

    private static void EnsureTelegramRunning()
    {
        if (Process.GetProcessesByName("Telegram").Length > 0
            || Process.GetProcessesByName("TelegramDesktop").Length > 0)
        {
            return;
        }

        try
        {
            var telegram = Path.Combine(AppContext.BaseDirectory, "Telegram.exe");
            if (File.Exists(telegram))
            {
                Process.Start(new ProcessStartInfo
                {
                    FileName = telegram,
                    WorkingDirectory = AppContext.BaseDirectory,
                    UseShellExecute = true
                });
            }
            else
            {
                WinForms.MessageBox.Show(
                    "找不到同資料夾的 Telegram.exe。請保留整個壓縮包解壓後的檔案結構。",
                    "TelegramAccessible",
                    WinForms.MessageBoxButtons.OK,
                    WinForms.MessageBoxIcon.Warning);
            }
        }
        catch
        {
            WinForms.MessageBox.Show(
                "Telegram 啟動失敗。你也可以先手動開啟 Telegram.exe，再執行 TelegramAccessible.exe。",
                "TelegramAccessible",
                WinForms.MessageBoxButtons.OK,
                WinForms.MessageBoxIcon.Warning);
        }
    }

    private static void WorkerLoop()
    {
        foreach (var action in Work.GetConsumingEnumerable())
        {
            try
            {
                action();
            }
            catch
            {
                // Deliberately silent: accessibility helpers must never take Telegram down.
            }
        }
    }

    private static IntPtr KeyboardHook(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode < 0 || !_enabled || (wParam.ToInt32() != WmKeyDown && wParam.ToInt32() != WmSysKeyDown))
        {
            return CallNextHookEx(_hook, nCode, wParam, lParam);
        }

        var data = Marshal.PtrToStructure<KbdLlHookStruct>(lParam);
        if ((ulong)data.DwExtraInfo.ToInt64() == InjectedMarker || !IsTelegramForeground())
        {
            return CallNextHookEx(_hook, nCode, wParam, lParam);
        }

        var vk = (int)data.VkCode;

        if (vk == VkTab)
        {
            var shift = (GetAsyncKeyState(VkShift) & 0x8000) != 0;
            TryQueue(() => HandleTab(shift));
            return (IntPtr)1;
        }

        if (vk == VkReturn || vk == VkSpace)
        {
            var focus = GetTelegramFocus();
            if (focus != null && ShouldActivateOurselves(focus, vk == VkSpace))
            {
                TryQueue(() => ActivateFocused(focus, vk));
                return (IntPtr)1;
            }
        }

        return CallNextHookEx(_hook, nCode, wParam, lParam);
    }

    private static void HandleTab(bool backward)
    {
        var focus = GetTelegramFocus();
        if (focus == null)
        {
            SendKey(VkTab, backward);
            return;
        }

        // Shift+Tab remains native for now. The critical forward path is:
        // compose edit -> message list, without the bot command surface stealing Tab.
        if (backward || !IsComposerEdit(focus))
        {
            SendKey(VkTab, backward);
            return;
        }

        SendKey(VkTab, false);
        Thread.Sleep(30);

        var after = GetTelegramFocus();
        if (after == null || IsMessageList(after))
        {
            return;
        }

        // Telegram bot command autocomplete currently consumes the first Tab.
        // Skip only controls that are clearly bot-command related, never blindly
        // double-Tab in ordinary chats.
        if (IsBotCommandish(after))
        {
            SendKey(VkTab, false);
            Thread.Sleep(25);
        }
    }

    private static void ActivateFocused(AutomationElement focus, int originalKey)
    {
        try
        {
            if (TryPattern<InvokePattern>(focus, InvokePattern.Pattern, p => p.Invoke()))
                return;

            if (TryPattern<TogglePattern>(focus, TogglePattern.Pattern, p => p.Toggle()))
                return;

            if (TryPattern<SelectionItemPattern>(focus, SelectionItemPattern.Pattern, p => p.Select()))
            {
                // Selection alone is not activation for some Telegram painted rows.
                if (IsBotCommandish(focus) && TryClickElement(focus))
                    return;
                return;
            }

            if (TryPattern<ExpandCollapsePattern>(focus, ExpandCollapsePattern.Pattern, p =>
                {
                    if (p.Current.ExpandCollapseState == ExpandCollapseState.Collapsed)
                        p.Expand();
                    else if (p.Current.ExpandCollapseState == ExpandCollapseState.Expanded)
                        p.Collapse();
                }))
                return;

            if (TryPattern<LegacyIAccessiblePattern>(focus, LegacyIAccessiblePattern.Pattern, p => p.DoDefaultAction()))
                return;

            if (TryClickElement(focus))
                return;
        }
        catch
        {
        }

        // If no accessibility action exists, preserve Telegram's native behavior.
        SendKey(originalKey, false);
    }

    private static bool ShouldActivateOurselves(AutomationElement focus, bool space)
    {
        try
        {
            if (IsComposerEdit(focus) || IsMessageList(focus))
                return false; // Space on message list is Telegram's native voice/audio play-pause.

            if (IsBotCommandish(focus))
                return true;

            var type = focus.Current.ControlType;
            return type == ControlType.Button
                || type == ControlType.MenuItem
                || type == ControlType.CheckBox
                || type == ControlType.RadioButton
                || type == ControlType.Hyperlink
                || type == ControlType.TabItem;
        }
        catch
        {
            return false;
        }
    }

    private static bool IsComposerEdit(AutomationElement element)
    {
        try
        {
            if (element.Current.ControlType != ControlType.Edit)
                return false;

            var hwnd = GetForegroundWindow();
            if (hwnd == IntPtr.Zero || !GetWindowRect(hwnd, out var wr))
                return true;

            var r = element.Current.BoundingRectangle;
            if (r.IsEmpty || wr.Bottom <= wr.Top)
                return true;

            // Message composer lives near the bottom. This prevents us from
            // hijacking Telegram's search fields at the top of the window.
            var threshold = wr.Top + (wr.Bottom - wr.Top) * 0.45;
            return r.Top >= threshold;
        }
        catch
        {
            return false;
        }
    }

    private static bool IsMessageList(AutomationElement element)
    {
        try
        {
            if (element.Current.ControlType != ControlType.List)
                return false;

            var cls = Safe(() => element.Current.ClassName);
            var aid = Safe(() => element.Current.AutomationId);
            var name = Safe(() => element.Current.Name);
            var combined = (cls + " " + aid + " " + name).ToLowerInvariant();

            if (combined.Contains("dialogs::innerwidget")
                || combined.Contains("fieldautocomplete")
                || combined.Contains("botcommand")
                || combined.Contains("bot command")
                || combined.Contains("機器人命令")
                || combined.Contains("机器人命令"))
                return false;

            return combined.Contains("history")
                || combined.Contains("listwidget")
                || combined.Contains("message")
                || string.IsNullOrWhiteSpace(combined);
        }
        catch
        {
            return false;
        }
    }

    private static bool IsBotCommandish(AutomationElement element)
    {
        try
        {
            if (IsMessageList(element))
                return false;

            var name = Safe(() => element.Current.Name).Trim();
            var cls = Safe(() => element.Current.ClassName);
            var aid = Safe(() => element.Current.AutomationId);
            var combined = (name + " " + cls + " " + aid).ToLowerInvariant();

            if (name.StartsWith("/", StringComparison.Ordinal))
                return true;

            return combined.Contains("fieldautocomplete")
                || combined.Contains("botcommand")
                || combined.Contains("bot command")
                || combined.Contains("botkeyboard")
                || combined.Contains("機器人命令")
                || combined.Contains("机器人命令")
                || combined.Contains("命令選單")
                || combined.Contains("命令菜单");
        }
        catch
        {
            return false;
        }
    }

    private static AutomationElement? GetTelegramFocus()
    {
        try
        {
            var focus = AutomationElement.FocusedElement;
            if (focus == null)
                return null;

            var pid = focus.Current.ProcessId;
            return IsTelegramProcess(pid) ? focus : null;
        }
        catch
        {
            return null;
        }
    }

    private static bool IsTelegramForeground()
    {
        var hwnd = GetForegroundWindow();
        if (hwnd == IntPtr.Zero)
            return false;

        GetWindowThreadProcessId(hwnd, out var pid);
        return IsTelegramProcess((int)pid);
    }

    private static bool IsTelegramProcess(int pid)
    {
        if (pid <= 0)
            return false;

        try
        {
            using var process = Process.GetProcessById(pid);
            return process.ProcessName.Equals("Telegram", StringComparison.OrdinalIgnoreCase)
                || process.ProcessName.Equals("TelegramDesktop", StringComparison.OrdinalIgnoreCase);
        }
        catch
        {
            return false;
        }
    }

    private static bool TryClickElement(AutomationElement element)
    {
        try
        {
            if (element.TryGetClickablePoint(out var point))
            {
                ClickAt((int)Math.Round(point.X), (int)Math.Round(point.Y));
                return true;
            }

            var rect = element.Current.BoundingRectangle;
            if (rect.IsEmpty || rect.Width <= 1 || rect.Height <= 1)
                return false;

            ClickAt(
                (int)Math.Round(rect.Left + rect.Width / 2),
                (int)Math.Round(rect.Top + rect.Height / 2));
            return true;
        }
        catch
        {
            return false;
        }
    }

    private static bool TryPattern<T>(AutomationElement element, AutomationPattern pattern, Action<T> action) where T : class
    {
        try
        {
            if (element.TryGetCurrentPattern(pattern, out var raw) && raw is T typed)
            {
                action(typed);
                return true;
            }
        }
        catch
        {
        }
        return false;
    }

    private static string Safe(Func<string> getter)
    {
        try { return getter() ?? string.Empty; }
        catch { return string.Empty; }
    }

    private static void TryQueue(Action action)
    {
        try
        {
            if (!Work.IsAddingCompleted)
                Work.Add(action);
        }
        catch
        {
        }
    }

    private static void SendKey(int vk, bool withShift)
    {
        var inputs = new List<Input>();
        if (withShift)
            inputs.Add(KeyInput(VkShift, false));
        inputs.Add(KeyInput(vk, false));
        inputs.Add(KeyInput(vk, true));
        if (withShift)
            inputs.Add(KeyInput(VkShift, true));
        SendInput((uint)inputs.Count, inputs.ToArray(), Marshal.SizeOf<Input>());
    }

    private static Input KeyInput(int vk, bool up) => new()
    {
        Type = 1,
        U = new InputUnion
        {
            Ki = new KeyboardInput
            {
                WVk = (ushort)vk,
                WScan = 0,
                DwFlags = up ? 0x0002u : 0u,
                Time = 0,
                DwExtraInfo = (UIntPtr)InjectedMarker
            }
        }
    };

    private static void ClickAt(int x, int y)
    {
        SetCursorPos(x, y);
        var inputs = new[]
        {
            new Input
            {
                Type = 0,
                U = new InputUnion
                {
                    Mi = new MouseInput { DwFlags = 0x0002u, DwExtraInfo = (UIntPtr)InjectedMarker }
                }
            },
            new Input
            {
                Type = 0,
                U = new InputUnion
                {
                    Mi = new MouseInput { DwFlags = 0x0004u, DwExtraInfo = (UIntPtr)InjectedMarker }
                }
            }
        };
        SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<Input>());
    }

    private delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    private struct KbdLlHookStruct
    {
        public uint VkCode;
        public uint ScanCode;
        public uint Flags;
        public uint Time;
        public UIntPtr DwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Input
    {
        public uint Type;
        public InputUnion U;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion
    {
        [FieldOffset(0)] public MouseInput Mi;
        [FieldOffset(0)] public KeyboardInput Ki;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KeyboardInput
    {
        public ushort WVk;
        public ushort WScan;
        public uint DwFlags;
        public uint Time;
        public UIntPtr DwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MouseInput
    {
        public int Dx;
        public int Dy;
        public uint MouseData;
        public uint DwFlags;
        public uint Time;
        public UIntPtr DwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Rect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnhookWindowsHookEx(IntPtr hhk);

    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("kernel32.dll", CharSet = CharSet.Auto)]
    private static extern IntPtr GetModuleHandle(string? lpModuleName);

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll")]
    private static extern short GetAsyncKeyState(int vKey);

    [DllImport("user32.dll")]
    private static extern bool GetWindowRect(IntPtr hWnd, out Rect lpRect);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint nInputs, Input[] pInputs, int cbSize);

    [DllImport("user32.dll")]
    private static extern bool SetCursorPos(int x, int y);
}
