import os
import sys
import multiprocessing
import threading
import time

def parent_watchdog(parent_pid: int):
    """
    Terminates the bridge gateway immediately if the parent Fleet Station UI process exits.
    Guarantees zero orphaned bridge or cloudflared processes on Windows.
    Uses Win32 kernel event signaling for instantaneous sub-millisecond teardown.
    """
    try:
        import ctypes
        SYNCHRONIZE = 0x00100000
        kernel32 = ctypes.windll.kernel32
        handle = kernel32.OpenProcess(SYNCHRONIZE, False, parent_pid)
        if handle:
            print(f"[WATCHDOG] Win32 kernel synchronization attached to parent UI PID {parent_pid}", flush=True)
            kernel32.WaitForSingleObject(handle, 0xFFFFFFFF)  # INFINITE
            kernel32.CloseHandle(handle)
            print(f"[WATCHDOG] Parent UI process {parent_pid} has terminated. Shutting down gateway...", flush=True)
        else:
            print(f"[WATCHDOG] Parent PID {parent_pid} already gone or cannot be opened.", flush=True)
    except Exception as e:
        print(f"[WATCHDOG] Win32 wait exception ({e}), falling back to psutil loop", flush=True)
        try:
            import psutil
            while psutil.pid_exists(parent_pid):
                time.sleep(1.0)
        except Exception:
            pass

    try:
        from bridge.server import tunnel_mgr, fleet_mgr
        tunnel_mgr.stop()
        fleet_mgr.stop_all()
    except Exception:
        pass
    os._exit(0)

if __name__ == "__main__":
    multiprocessing.freeze_support()
    
    # Ensure working directory and sys.path contain base folder
    base_dir = os.path.dirname(os.path.abspath(__file__))
    if base_dir not in sys.path:
        sys.path.insert(0, base_dir)
        
    import uvicorn
    from bridge.server import app, ensure_port_available
    
    port = int(os.environ.get("AGY_PORT", "8765"))
    if "AGY_PORT" not in os.environ:
        try:
            from pathlib import Path
            import json
            cfg_path = Path.home() / ".antigravity-fleet" / "config" / "fleet_config.json"
            if cfg_path.exists():
                with open(cfg_path, "r", encoding="utf-8") as f:
                    c = json.load(f)
                    p = c.get("gateway", {}).get("port")
                    if p:
                        port = int(p)
        except Exception:
            pass

    host = os.environ.get("AGY_HOST", "0.0.0.0")
    
    print(f"Antigravity Bridge Gateway checking port {port} availability...", flush=True)
    ensure_port_available(port)

    # Bind watchdog to parent UI PID if launched by Fleet Station
    parent_pid_str = os.environ.get("AGY_PARENT_PID")
    if parent_pid_str and parent_pid_str.isdigit():
        parent_pid = int(parent_pid_str)
        t = threading.Thread(target=parent_watchdog, args=(parent_pid,), daemon=True)
        t.start()
        print(f"[WATCHDOG] Active monitoring bound to parent UI PID {parent_pid}", flush=True)

    print(f"Antigravity Bridge Gateway starting on {host}:{port}...", flush=True)
    try:
        uvicorn.run(app, host=host, port=port, log_level="info")
    except OSError as e:
        if "10048" in str(e):
            print(f"[RETRY] Caught Errno 10048. Forcing port release and retrying...", flush=True)
            ensure_port_available(port)
            uvicorn.run(app, host=host, port=port, log_level="info")
        else:
            raise
    finally:
        try:
            from bridge.server import tunnel_mgr, fleet_mgr
            tunnel_mgr.stop()
            fleet_mgr.stop_all()
        except Exception:
            pass
