"""
Antigravity 15-Account Registration & Pairing Setup
Assists in initial OAuth pre-registration and produces the phone pairing credentials.
"""
import os
import sys
import json
import socket
from pathlib import Path
import qrcode

FLEET_DIR = Path.home() / ".antigravity-fleet"
CONFIG_PATH = Path(__file__).parent.parent / "bridge" / "config" / "fleet_config.json"

def main():
    print("=" * 60)
    print("  ANTIGRAVITY 15-ACCOUNT PRE-REGISTRATION & PAIRING SETUP")
    print("=" * 60)

    FLEET_DIR.mkdir(parents=True, exist_ok=True)

    with open(CONFIG_PATH, "r", encoding="utf-8") as f:
        config = json.load(f)

    total_accounts = config.get("fleet", {}).get("total_accounts", 15)
    pairing_token = config.get("gateway", {}).get("pairing_token")
    port = config.get("gateway", {}).get("port", 8765)

    print(f"\n[+] Preparing {total_accounts} isolated profiles in: {FLEET_DIR}")

    for i in range(1, total_accounts + 1):
        pdir = FLEET_DIR / f"profile_{i:02d}"
        pdir.mkdir(parents=True, exist_ok=True)
        # Verify or generate CSRF token
        csrf_file = pdir / "csrf.token"
        if not csrf_file.exists():
            import secrets
            csrf_file.write_text(secrets.token_hex(16), encoding="utf-8")

        status = "Pre-configured"
        if (pdir / "antigravity_state.pbtxt").exists() or (pdir / "conversation_summaries.db").exists():
            status = "AUTHENTICATED"
        print(f"  - Slot #{i:02d}: {pdir.name} [{status}]")

    # Discover host IP
    local_ip = "127.0.0.1"
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        local_ip = s.getsockname()[0]
        s.close()
    except Exception:
        pass

    pairing_info = {
        "host": local_ip,
        "port": port,
        "token": pairing_token
    }

    qr_path = Path(__file__).parent.parent / "pairing_qr.png"
    qr = qrcode.QRCode(box_size=10, border=2)
    qr.add_data(json.dumps(pairing_info))
    qr.make(fit=True)
    img = qr.make_image(fill_color="black", back_color="white")
    img.save(qr_path)

    print("\n" + "=" * 60)
    print("  MOBILE PAIRING READY")
    print("=" * 60)
    print(f"Host IP       : {local_ip}")
    print(f"Gateway Port  : {port}")
    print(f"Pairing Token : {pairing_token}")
    print(f"QR Code Saved : {qr_path}")
    print("\nScan this QR code from your Flutter mobile app to instantly connect!")
    print("=" * 60)

if __name__ == "__main__":
    main()
