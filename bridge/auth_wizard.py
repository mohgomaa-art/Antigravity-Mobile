import argparse
import sys
import getpass
from bridge.core.auth_vault import AuthVault

def print_table(vault: AuthVault):
    creds = vault.list_credentials()
    print("=" * 78)
    print(f"{'Slot':<6} | {'Alias':<14} | {'Status':<15} | {'Email':<28} | {'Type':<10}")
    print("-" * 78)
    for c in creds:
        status = "AUTHENTICATED" if c.is_authenticated else "UNCONFIGURED"
        email = c.email or "(none)"
        print(f"#{c.account_id:02d}    | {c.alias:<14} | {status:<15} | {email:<28} | {c.auth_type:<10}")
    print("=" * 78)

def main():
    parser = argparse.ArgumentParser(description="Antigravity 15-Account Fleet Authentication Wizard")
    parser.add_argument("--list", action="store_true", help="List all 15 account slots and authentication status")
    parser.add_argument("--slot", type=int, choices=range(1, 16), help="Slot number to configure (1 to 15)")
    parser.add_argument("--email", type=str, help="Email address of the paid account")
    parser.add_argument("--token", type=str, help="OAuth token, API key, or session secret")
    parser.add_argument("--type", type=str, default="google_oauth", choices=["google_oauth", "api_key", "session_token"], help="Authentication type")
    parser.add_argument("--interactive", action="store_true", help="Interactively configure slots")

    args = parser.parse_args()
    vault = AuthVault()

    if args.list or (not args.slot and not args.interactive):
        print_table(vault)
        return

    if args.slot and args.email:
        token = args.token
        if not token:
            token = getpass.getpass(f"Enter token or API key for Slot #{args.slot:02d} ({args.email}): ")
        vault.set_credential(args.slot, args.email, token, auth_type=args.type)
        print(f"Successfully configured Slot #{args.slot:02d} for {args.email}!")
        print_table(vault)
        return

    if args.interactive:
        print_table(vault)
        slot_str = input("Select slot to configure (1-15, or 'q' to quit): ").strip()
        if slot_str.lower() == 'q':
            return
        slot = int(slot_str)
        email = input(f"Enter email for Slot #{slot:02d}: ").strip()
        auth_type = input("Auth type (1=google_oauth, 2=api_key, 3=session_token) [default: 1]: ").strip()
        t_map = {"1": "google_oauth", "2": "api_key", "3": "session_token"}
        auth_type_val = t_map.get(auth_type, "google_oauth")
        token = getpass.getpass(f"Enter token or API key for {email}: ").strip()
        vault.set_credential(slot, email, token, auth_type=auth_type_val)
        print(f"Successfully updated Slot #{slot:02d}!")
        print_table(vault)

if __name__ == "__main__":
    main()
