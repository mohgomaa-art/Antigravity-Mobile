import os
import sys
import logging
import ctypes
from ctypes import wintypes
from pathlib import Path

logger = logging.getLogger("agy.desktop_launcher")

if sys.platform == "win32":
    class STARTUPINFO(ctypes.Structure):
        _fields_ = [
            ("cb", wintypes.DWORD),
            ("lpReserved", wintypes.LPWSTR),
            ("lpDesktop", wintypes.LPWSTR),
            ("lpTitle", wintypes.LPWSTR),
            ("dwX", wintypes.DWORD),
            ("dwY", wintypes.DWORD),
            ("dwXSize", wintypes.DWORD),
            ("dwYSize", wintypes.DWORD),
            ("dwXCountChars", wintypes.DWORD),
            ("dwYCountChars", wintypes.DWORD),
            ("dwFillAttribute", wintypes.DWORD),
            ("dwFlags", wintypes.DWORD),
            ("wShowWindow", wintypes.WORD),
            ("cbReserved2", wintypes.WORD),
            ("lpReserved2", ctypes.c_void_p),
            ("hStdInput", wintypes.HANDLE),
            ("hStdOutput", wintypes.HANDLE),
            ("hStdError", wintypes.HANDLE),
        ]

    class PROCESS_INFORMATION(ctypes.Structure):
        _fields_ = [
            ("hProcess", wintypes.HANDLE),
            ("hThread", wintypes.HANDLE),
            ("dwProcessId", wintypes.DWORD),
            ("dwThreadId", wintypes.DWORD),
        ]


def launch_on_interactive_desktop(cmd_line: str, cwd: str = None) -> int:
    """
    Spawns a process explicitly onto the interactive desktop (WinSta0\\default).
    This guarantees that the window appears visibly in the foreground of the
    user's physical monitor, even if this script was invoked from a background
    service, task, or sandboxed runner.
    """
    if sys.platform != "win32":
        import subprocess
        p = subprocess.Popen(cmd_line, shell=True, cwd=cwd)
        return p.pid

    try:
        si = STARTUPINFO()
        si.cb = ctypes.sizeof(STARTUPINFO)
        si.lpDesktop = "WinSta0\\default"
        si.dwFlags = 0x00000001  # STARTF_USESHOWWINDOW
        si.wShowWindow = 1       # SW_SHOWNORMAL

        pi = PROCESS_INFORMATION()

        ok = ctypes.windll.kernel32.CreateProcessW(
            None,
            cmd_line,
            None,
            None,
            False,
            0,
            None,
            cwd,
            ctypes.byref(si),
            ctypes.byref(pi),
        )

        if ok:
            pid = pi.dwProcessId
            ctypes.windll.kernel32.CloseHandle(pi.hProcess)
            ctypes.windll.kernel32.CloseHandle(pi.hThread)
            logger.info(f"Launched on WinSta0\\default (PID {pid}): {cmd_line}")
            return pid
        else:
            err = ctypes.GetLastError()
            logger.warning(f"CreateProcessW returned {err} for {cmd_line}")
            import subprocess
            p = subprocess.Popen(cmd_line, shell=True, cwd=cwd)
            return p.pid
    except Exception as e:
        logger.error(f"Error launching on interactive desktop: {e}")
        import subprocess
        p = subprocess.Popen(cmd_line, shell=True, cwd=cwd)
        return p.pid


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("command", help="Command line to execute on WinSta0\\default")
    parser.add_argument("--cwd", default=None, help="Working directory")
    args = parser.parse_args()
    pid = launch_on_interactive_desktop(args.command, args.cwd)
    print(f"Launched PID: {pid}")
