"""Windows GPU regression host: invisible parent, no desktop input or visible game window.

Uses Godot's supported --wid embedding and an always-updating SubViewport. Captures exercise
the renderer, but timings from this hidden host must not be reported as desktop FPS.
"""
import argparse
import ctypes
from ctypes import wintypes
import os
from pathlib import Path
import subprocess
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', required=True)
    parser.add_argument('--timeout', type=float, default=180)
    parser.add_argument('--coast', action='store_true')
    parser.add_argument('--baseline', action='store_true')
    parser.add_argument('--debug', action='store_true')
    parser.add_argument('--warmup', type=float, default=18.0, help='Coast warm-up seconds')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    output = Path(args.output).resolve()
    output.mkdir(parents=True, exist_ok=True)
    user = ctypes.WinDLL('user32', use_last_error=True)
    user.CreateWindowExW.restype = wintypes.HWND
    user.CreateWindowExW.argtypes = [wintypes.DWORD, wintypes.LPCWSTR, wintypes.LPCWSTR,
        wintypes.DWORD, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int,
        wintypes.HWND, wintypes.HMENU, wintypes.HINSTANCE, ctypes.c_void_p]
    user.DestroyWindow.argtypes = [wintypes.HWND]
    user.IsWindowVisible.argtypes = [wintypes.HWND]
    # No WS_VISIBLE, no ShowWindow, and no foreground/input calls.
    host = user.CreateWindowExW(0x08000000, 'STATIC', 'Construct background renderer',
        0x80000000, 0, 0, 1440, 900, None, None, None, None)
    if not host or user.IsWindowVisible(host):
        raise RuntimeError('Could not create an invisible render host')
    env = dict(os.environ, CONSTRUCT_WATER_CHECK_DIR=str(output), CONSTRUCT_COAST_WARMUP=str(args.warmup))
    binary = os.environ.get('GODOT_BIN', str(root / '.tools/godot/Godot_v4.7.2-stable_win64.exe'))
    startup = subprocess.STARTUPINFO()
    startup.dwFlags = subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = 0
    process = None
    try:
        with (output / 'run.log').open('w', encoding='utf-8') as log:
            process = subprocess.Popen([binary, '--path', str(root / 'world'), '--windowed', '--wid', str(host),
                '--audio-driver', 'Dummy', '--script', 'res://scripts/diagnostics/background_render.gd',
                # --smoke is a second save-protection guard if an older controller is restored:
                # it will run its isolated smoke check and fail our water marker, never a normal session.
                '--', '--smoke', '--coast-check' if args.coast else '--water-check', '--quality=balanced',
                *(['--coast-baseline'] if args.baseline else []),
                *(['--coast-debug'] if args.debug else [])], cwd=root, env=env, stdout=log,
                stderr=subprocess.STDOUT, startupinfo=startup, creationflags=subprocess.CREATE_NO_WINDOW)
            start = time.monotonic()
            scanned = 0
            message = wintypes.MSG()
            while process.poll() is None:
                while user.PeekMessageW(ctypes.byref(message), None, 0, 0, 1):
                    user.TranslateMessage(ctypes.byref(message))
                    user.DispatchMessageW(ctypes.byref(message))
                with (output / 'run.log').open('r', encoding='utf-8', errors='replace') as stream:
                    stream.seek(scanned)
                    recent = stream.read()
                    scanned = stream.tell()
                if 'ERROR:' in recent:
                    raise RuntimeError('Renderer reported an error; see run.log')
                if time.monotonic() - start > args.timeout:
                    subprocess.run(['taskkill','/PID',str(process.pid),'/T','/F'],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                        creationflags=subprocess.CREATE_NO_WINDOW)
                    process.wait()
                    raise TimeoutError('Background renderer exceeded time limit; see run.log')
                time.sleep(0.02)
        report = (output / 'run.log').read_text(encoding='utf-8')
        print(report[-5000:])
        marker = 'CONSTRUCT_COAST_CHECK_OK' if args.coast else 'CONSTRUCT_WATER_CHECK_OK'
        if process.returncode or marker not in report or 'SCRIPT ERROR:' in report or '\nERROR:' in report:
            raise RuntimeError('Background water check failed; see run.log')
    finally:
        if process is not None and process.poll() is None:
            subprocess.run(['taskkill','/PID',str(process.pid),'/T','/F'],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                creationflags=subprocess.CREATE_NO_WINDOW)
            process.wait()
        user.DestroyWindow(host)


if __name__ == '__main__':
    main()
