// Euclid's ConPTY host. It starts one command under a Windows pseudoconsole and relays bytes:
// pseudoconsole output goes to stdout unchanged, and stdin carries frames from the gateway.
// A frame is one type byte, a little-endian 32-bit payload length, then the payload:
//   'd' bytes to type into the console, 'r' a resize as two little-endian 16-bit values
//   (columns, rows), 'x' stop. When stdin closes, the gateway is gone and the command is ended.
// Written for the C# 5 compiler that Windows PowerShell 5.1 provides through Add-Type.
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using Microsoft.Win32.SafeHandles;

namespace EuclidPty
{
    public static class Host
    {
        [StructLayout(LayoutKind.Sequential)]
        struct Coord { public short X; public short Y; }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct StartupInfo
        {
            public int cb; public string lpReserved; public string lpDesktop; public string lpTitle;
            public int dwX; public int dwY; public int dwXSize; public int dwYSize;
            public int dwXCountChars; public int dwYCountChars; public int dwFillAttribute; public int dwFlags;
            public short wShowWindow; public short cbReserved2; public IntPtr lpReserved2;
            public IntPtr hStdInput; public IntPtr hStdOutput; public IntPtr hStdError;
        }

        [StructLayout(LayoutKind.Sequential)]
        struct StartupInfoEx { public StartupInfo StartupInfo; public IntPtr lpAttributeList; }

        [StructLayout(LayoutKind.Sequential)]
        struct ProcessInformation { public IntPtr hProcess; public IntPtr hThread; public int dwProcessId; public int dwThreadId; }

        [DllImport("kernel32.dll", SetLastError = true)]
        static extern int CreatePseudoConsole(Coord size, SafeFileHandle input, SafeFileHandle output, uint flags, out IntPtr console);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern int ResizePseudoConsole(IntPtr console, Coord size);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern void ClosePseudoConsole(IntPtr console);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool CreatePipe(out SafeFileHandle read, out SafeFileHandle write, IntPtr attributes, int size);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool InitializeProcThreadAttributeList(IntPtr list, int count, int flags, ref IntPtr size);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool UpdateProcThreadAttribute(IntPtr list, uint flags, IntPtr attribute, IntPtr value, IntPtr size,
            IntPtr previous, IntPtr returnSize);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern void DeleteProcThreadAttributeList(IntPtr list);
        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode, EntryPoint = "CreateProcessW")]
        static extern bool CreateProcess(string application, string commandLine, IntPtr processAttributes, IntPtr threadAttributes,
            bool inheritHandles, uint creationFlags, IntPtr environment, string currentDirectory, ref StartupInfoEx startupInfo,
            out ProcessInformation information);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool GetExitCodeProcess(IntPtr process, out uint code);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool TerminateProcess(IntPtr process, uint code);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool CloseHandle(IntPtr handle);

        const uint ExtendedStartupInfoPresent = 0x00080000;
        const int UseStdHandles = 0x00000100;
        const uint Infinite = 0xFFFFFFFF;
        static readonly IntPtr PseudoConsoleAttribute = new IntPtr(0x00020016);

        public static int Run(string commandLine, string directory, short cols, short rows)
        {
            SafeFileHandle inputRead, inputWrite, outputRead, outputWrite;
            if (!CreatePipe(out inputRead, out inputWrite, IntPtr.Zero, 0) || !CreatePipe(out outputRead, out outputWrite, IntPtr.Zero, 0))
                throw new InvalidOperationException("Could not create the console pipes (" + Marshal.GetLastWin32Error() + ").");
            Coord size = new Coord();
            size.X = cols;
            size.Y = rows;
            IntPtr console;
            int created = CreatePseudoConsole(size, inputRead, outputWrite, 0, out console);
            if (created != 0)
                throw new InvalidOperationException("ConPTY is unavailable (0x" + created.ToString("x") + "). It needs Windows 10 version 1809 or later.");
            // The pseudoconsole keeps its own copies of its ends of the pipes.
            inputRead.Dispose();
            outputWrite.Dispose();

            IntPtr listSize = IntPtr.Zero;
            InitializeProcThreadAttributeList(IntPtr.Zero, 1, 0, ref listSize);
            IntPtr list = Marshal.AllocHGlobal(listSize);
            ProcessInformation process;
            try
            {
                if (!InitializeProcThreadAttributeList(list, 1, 0, ref listSize) ||
                    !UpdateProcThreadAttribute(list, 0, PseudoConsoleAttribute, console, new IntPtr(IntPtr.Size), IntPtr.Zero, IntPtr.Zero))
                    throw new InvalidOperationException("Could not attach the pseudoconsole (" + Marshal.GetLastWin32Error() + ").");
                StartupInfoEx startup = new StartupInfoEx();
                startup.StartupInfo.cb = Marshal.SizeOf(typeof(StartupInfoEx));
                // Empty standard handles keep the command on the pseudoconsole instead of this host's pipes.
                startup.StartupInfo.dwFlags = UseStdHandles;
                startup.lpAttributeList = list;
                if (!CreateProcess(null, commandLine, IntPtr.Zero, IntPtr.Zero, false, ExtendedStartupInfoPresent, IntPtr.Zero,
                        directory, ref startup, out process))
                    throw new InvalidOperationException("Could not start " + commandLine + " (" + Marshal.GetLastWin32Error() + ").");
            }
            finally
            {
                DeleteProcThreadAttributeList(list);
                Marshal.FreeHGlobal(list);
            }
            CloseHandle(process.hThread);

            Stream stdout = Console.OpenStandardOutput();
            Stream stdin = Console.OpenStandardInput();
            FileStream fromConsole = new FileStream(outputRead, FileAccess.Read, 4096, false);
            FileStream toConsole = new FileStream(inputWrite, FileAccess.Write, 4096, false);
            IntPtr processHandle = process.hProcess;
            IntPtr consoleHandle = console;

            Thread pump = new Thread(delegate ()
            {
                byte[] buffer = new byte[16384];
                try
                {
                    int read;
                    while ((read = fromConsole.Read(buffer, 0, buffer.Length)) > 0)
                    {
                        stdout.Write(buffer, 0, read);
                        stdout.Flush();
                    }
                }
                catch (IOException) { }
                catch (ObjectDisposedException) { }
            });
            pump.IsBackground = true;
            pump.Start();

            Thread input = new Thread(delegate ()
            {
                byte[] header = new byte[5];
                try
                {
                    while (ReadExactly(stdin, header, 5))
                    {
                        int length = BitConverter.ToInt32(header, 1);
                        if (length < 0 || length > (1 << 20)) break;
                        byte[] payload = new byte[length];
                        if (!ReadExactly(stdin, payload, length)) break;
                        if (header[0] == (byte)'d')
                        {
                            toConsole.Write(payload, 0, length);
                            toConsole.Flush();
                        }
                        else if (header[0] == (byte)'r' && length == 4)
                        {
                            Coord next = new Coord();
                            next.X = BitConverter.ToInt16(payload, 0);
                            next.Y = BitConverter.ToInt16(payload, 2);
                            ResizePseudoConsole(consoleHandle, next);
                        }
                        else if (header[0] == (byte)'x')
                        {
                            break;
                        }
                    }
                }
                catch (IOException) { }
                catch (ObjectDisposedException) { }
                // The gateway asked to stop or went away. End the command so this host exits too.
                TerminateProcess(processHandle, 1);
            });
            input.IsBackground = true;
            input.Start();

            WaitForSingleObject(processHandle, Infinite);
            uint code;
            GetExitCodeProcess(processHandle, out code);
            // Closing the pseudoconsole ends its output. The pump drains what is left first.
            ClosePseudoConsole(consoleHandle);
            pump.Join(2000);
            CloseHandle(processHandle);
            return unchecked((int)code);
        }

        static bool ReadExactly(Stream stream, byte[] buffer, int count)
        {
            int offset = 0;
            while (offset < count)
            {
                int read = stream.Read(buffer, offset, count - offset);
                if (read <= 0) return false;
                offset += read;
            }
            return true;
        }
    }
}
