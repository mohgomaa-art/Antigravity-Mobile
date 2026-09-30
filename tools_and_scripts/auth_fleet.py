"""
Antigravity 15-Account Fleet Authentication CLI
Allows interactive configuration and Google OAuth provisioning for each worker account.
"""
import sys
import json
import argparse
from pathlib import Path

# Add project root to sys.path
sys.path.insert(0, str(Path(__file__).parent.parent))

from bridge.core.auth_vault import AuthVault

def main():
    parser = argparse.ArgumentParser(description="Authenticate Antigravity Fleet Accounts")
    parser.add_argument("--slot", type=int, choices=range(1, 16), help="Worker account slot (1-15)")
    parser.add_argument("--email", type=str, help="Account email address")
    parser.add_argument("--token", type=str, help="OAuth refresh token or session token")
    parser.add_argument("--alias", type=str, help="Account alias / label")
    parser.add_argument("--list", action="store_true", help="List all 15 account slots and auth status")
    args = parser.parse_args()

    vault = AuthVault()

    if args.list:
        print("=" * 65)
        print("         ANTIGRAVITY 15-ACCOUNT FLEET AUTHENTICATION STATUS")
        print("=" * 65)
        print(f"{'Slot':<6} {'Alias':<14} {'Email':<28} {'Status':<12}")
        print("-" * 65)
        for cred in vault.list_credentials():
            slot_str = f"#{cred.account_id:02d}"
            status = "AUTHENTICATED" if cred.is_authenticated else "UNLINKED"
            email = cred.email or "(Not configured)"
            print(f"{slot_str:<6} {cred.alias:<14} {email:<28} {status:<12}")
        print("=" * 65)
        return

    if args.slot:
        slot = args.slot
        email = args.email or input(f"Enter Google email for Worker #{slot:02d}: ").strip()
        token = args.token or input(f"Enter OAuth token / API key for Worker #{slot:02d}: ").strip()
        alias = args.alias or f"Worker-{slot:02d}"

        if not email or not token:
            print("[-] Error: Both email and token are required.")
            return

        cred = vault.set_credential(
            account_id=slot,
            email=email,
            token=token,
            alias=alias
        )
        print(f"[+] Successfully authenticated Worker #{slot:02d} ({email})!")
        return

    # Interactive mode for unlinked slots
    print("=" * 65)
    print("  INTERACTIVE ANTIGRAVITY 15-ACCOUNT PROVISIONING")
    print("=" * 65)
    slots = vault.list_credentials()
    for cred in slots:
        status = "AUTHENTICATED" if cred.is_authenticated else "UNLINKED"
        print(f"Slot #{cred.account_id:02d}: {cred.alias} - {cred.email or 'Empty'} [{status}]")

    target = input("\nEnter slot number to authenticate (1-15), or 'q' to quit: ").strip()
    if target.isdigit() and 1 <= int(target) <= 15:
        slot_num = int(target)
        email = input(f"Enter Google email for Worker #{slot_num:02d}: ").strip()
        token = input(f"Enter OAuth / API token for Worker #{slot_num:02d}: ").strip()
        alias = input(f"Enter Alias (default: Worker-{slot_num:02d}): ").strip() or f"Worker-{slot_num:02d}"
        if email and token:
            vault.set_credential(account_id=slot_num, email=email, token=token, alias=alias)
            print(f"\n[+] Worker #{slot_num:02d} authenticated and ready to spawn!")
    else:
        print("Exiting.")

if __name__ == "__main__":
    main()
