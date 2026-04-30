#!/usr/bin/env python3
"""
Export Firestore data to CSV files for inspection in Excel / Numbers.

The app stores everything under `users/{userId}/...` with these subcollections:
    meals, symptomLogs, environment, consent, Observations_<Type>

This script walks every user document plus every subcollection found under it
and writes one CSV per subcollection name into the output directory. Each row
is one document; columns are the union of all keys across documents (nested
maps and lists are flattened with dotted / indexed keys). A `__userId` and
`__docId` column are added so you can trace each row back to its source.

Setup
-----
    pip install firebase-admin

    # In Firebase Console:
    #   Project settings -> Service accounts -> Generate new private key
    # Save the downloaded JSON somewhere outside the repo. Then:

    export GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json
    python Scripts/export_firestore.py --out ./firestore_export

Or pass the credentials path explicitly:

    python Scripts/export_firestore.py \
        --credentials /path/to/serviceAccount.json \
        --out ./firestore_export
"""

import argparse
import csv
import os
import sys
from pathlib import Path

try:
    import firebase_admin
    from firebase_admin import credentials, firestore
except ImportError:
    sys.exit("Missing dependency. Run: pip install firebase-admin")


def flatten(value, prefix="", out=None):
    """Flatten nested dicts/lists into a single-level dict with dotted keys."""
    if out is None:
        out = {}
    if isinstance(value, dict):
        if not value:
            out[prefix] = ""
        for k, v in value.items():
            key = f"{prefix}.{k}" if prefix else str(k)
            flatten(v, key, out)
    elif isinstance(value, list):
        if not value:
            out[prefix] = ""
        for i, v in enumerate(value):
            key = f"{prefix}[{i}]" if prefix else f"[{i}]"
            flatten(v, key, out)
    else:
        # firestore types -> string-friendly forms
        if hasattr(value, "isoformat"):  # DatetimeWithNanoseconds, datetime
            out[prefix] = value.isoformat()
        elif hasattr(value, "path"):  # DocumentReference
            out[prefix] = value.path
        elif hasattr(value, "latitude") and hasattr(value, "longitude"):  # GeoPoint
            out[prefix] = f"{value.latitude},{value.longitude}"
        else:
            out[prefix] = value
    return out


def write_csv(path: Path, rows: list[dict]) -> None:
    if not rows:
        return
    fieldnames: list[str] = []
    seen = set()
    for row in rows:
        for k in row.keys():
            if k not in seen:
                seen.add(k)
                fieldnames.append(k)
    # Put trace columns first.
    for col in ("__docId", "__userId"):
        if col in fieldnames:
            fieldnames.remove(col)
            fieldnames.insert(0, col)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--credentials", help="Path to service account JSON. Falls back to GOOGLE_APPLICATION_CREDENTIALS.")
    parser.add_argument("--out", default="firestore_export", help="Output directory for CSVs (default: firestore_export)")
    parser.add_argument("--users-collection", default="users", help="Top-level users collection name (default: users)")
    args = parser.parse_args()

    cred_path = args.credentials or os.environ.get("GOOGLE_APPLICATION_CREDENTIALS")
    if not cred_path:
        sys.exit("Provide --credentials or set GOOGLE_APPLICATION_CREDENTIALS.")
    if not Path(cred_path).is_file():
        sys.exit(f"Credentials file not found: {cred_path}")

    firebase_admin.initialize_app(credentials.Certificate(cred_path))
    db = firestore.client()
    out_dir = Path(args.out)

    # Aggregate: subcollection_name -> list of flattened rows.
    users_rows: list[dict] = []
    sub_rows: dict[str, list[dict]] = {}

    user_docs = list(db.collection(args.users_collection).stream())
    print(f"Found {len(user_docs)} user document(s).")

    for user in user_docs:
        user_id = user.id
        user_row = {"__docId": user_id, "__userId": user_id}
        user_row.update(flatten(user.to_dict() or {}))
        users_rows.append(user_row)

        for sub in user.reference.collections():
            sub_name = sub.id
            bucket = sub_rows.setdefault(sub_name, [])
            count = 0
            for doc in sub.stream():
                row = {"__docId": doc.id, "__userId": user_id}
                row.update(flatten(doc.to_dict() or {}))
                bucket.append(row)
                count += 1
            print(f"  {user_id} / {sub_name}: {count} doc(s)")

    write_csv(out_dir / "users.csv", users_rows)
    for name, rows in sub_rows.items():
        write_csv(out_dir / f"{name}.csv", rows)

    print(f"\nWrote {len(users_rows)} user(s) and {sum(len(r) for r in sub_rows.values())} subcollection doc(s) to {out_dir.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
