using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Windows.Interop;
using QiaoQiao.Core;

namespace QiaoQiao;

// Passive background raw input: never suppresses, transforms or forwards keys.
// The owning HWND's normal WPF message pump calls DefWindowProc for WM_INPUT.
internal sealed class RawInput : IDisposable
{
    private readonly HwndSource source;
    private readonly PetModel model;
    private readonly Action changed;
    private readonly PressFilter presses = new();
    private IntPtr buffer = Marshal.AllocHGlobal(256);
    private uint capacity = 256;
    private DateTimeOffset lastMotion;
    public bool Connected { get; private set; }
    public int LastError { get; private set; }
    public long CountedEvents { get; private set; }

    public RawInput(HwndSource source, PetModel model, Action changed)
    {
        this.source = source; this.model = model; this.changed = changed;
        source.AddHook(Hook); Register();
    }
    public void Register()
    {
        var devices = new[] { new Device(1, 6, 0x2100, source.Handle), new Device(1, 2, 0x2100, source.Handle) };
        Connected = RegisterRawInputDevices(devices, 2, (uint)Marshal.SizeOf<Device>());
        LastError = Connected ? 0 : Marshal.GetLastWin32Error();
    }
    public void Reset() => presses.Reset();
    private IntPtr Hook(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == 0x21) { handled = true; return new IntPtr(3); } // MA_NOACTIVATE
        if (msg == 0xFE) { if (wParam.ToInt64() == 2) presses.Remove(lParam.ToInt64()); return IntPtr.Zero; }
        if (msg != 0xFF) return IntPtr.Zero;
        uint size = 0, headerSize = (uint)Marshal.SizeOf<Header>();
        if (GetRawInputData(lParam, 0x10000003, IntPtr.Zero, ref size, headerSize) == uint.MaxValue || size < headerSize || size > 65536) return IntPtr.Zero;
        if (size > capacity) { Marshal.FreeHGlobal(buffer); buffer = Marshal.AllocHGlobal((int)size); capacity = size; }
        if (GetRawInputData(lParam, 0x10000003, buffer, ref size, headerSize) != size) return IntPtr.Zero;
        var h = Marshal.PtrToStructure<Header>(buffer);
        var data = IntPtr.Add(buffer, (int)headerSize);
        var now = DateTimeOffset.Now;
        if (h.Type == 1 && size >= headerSize + 16)
        {
            var k = Marshal.PtrToStructure<Keyboard>(data);
            bool down = presses.Accept(h.Device.ToInt64(), k.MakeCode, k.VirtualKey, k.Flags);
            if (down) { model.Press(now, k.VirtualKey is 8 or 46); if (!model.Paused) CountedEvents++; changed(); }
            else if ((k.Flags & 1) == 0) model.Activity(now); // auto-repeat is activity only
        }
        else if (h.Type == 0 && size >= headerSize + 24)
        {
            var m = Marshal.PtrToStructure<Mouse>(data);
            foreach (var flag in new ushort[] { 1, 4, 16, 64, 256 })
                if ((m.ButtonFlags & flag) != 0) { model.Press(now); if (!model.Paused) CountedEvents++; changed(); }
            if ((m.X != 0 || m.Y != 0 || (m.ButtonFlags & 0xC00) != 0) && (now - lastMotion).TotalMilliseconds >= 80)
            { lastMotion = now; model.Activity(now); }
        }
        return IntPtr.Zero;
    }
    public void Dispose()
    {
        source.RemoveHook(Hook);
        RegisterRawInputDevices([new Device(1, 6, 1, IntPtr.Zero), new Device(1, 2, 1, IntPtr.Zero)], 2, (uint)Marshal.SizeOf<Device>());
        if (buffer != IntPtr.Zero) { Marshal.FreeHGlobal(buffer); buffer = IntPtr.Zero; }
    }
    [StructLayout(LayoutKind.Sequential)] private struct Device(ushort page, ushort usage, uint flags, IntPtr target)
    { public ushort Page = page, Usage = usage; public uint Flags = flags; public IntPtr Target = target; }
    [StructLayout(LayoutKind.Sequential)] private struct Header { public uint Type, Size; public IntPtr Device, WParam; }
    [StructLayout(LayoutKind.Sequential)] private struct Keyboard { public ushort MakeCode, Flags, Reserved, VirtualKey; public uint Message, Extra; }
    [StructLayout(LayoutKind.Explicit, Size = 24)] private struct Mouse
    { [FieldOffset(0)] public ushort Flags; [FieldOffset(4)] public ushort ButtonFlags; [FieldOffset(6)] public ushort ButtonData; [FieldOffset(12)] public int X; [FieldOffset(16)] public int Y; }
    [DllImport("user32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool RegisterRawInputDevices([In] Device[] devices, uint count, uint size);
    [DllImport("user32.dll", SetLastError = true)] private static extern uint GetRawInputData(IntPtr input, uint command, IntPtr data, ref uint size, uint headerSize);
}
