#!/usr/bin/env python3
"""Populate project fields Priority, Size, Estimate and assign milestone for issues.

Prereqs:
  - gh CLI authenticated with 'project' scope
  - Existing export: project_items.json (created via:
        gh project item-list 5 --owner nam20485 --limit 200 --format json > project_items.json )

Run:
  python scripts/update_project_fields.py        # apply
  python scripts/update_project_fields.py --dry  # show commands only
"""
from __future__ import annotations
import json, subprocess, argparse, shutil, sys
from pathlib import Path

PROJECT_NUMBER = 5
PROJECT_ID = "PVT_kwHOABvqFM4BAC-P"

# Field IDs
FIELD_PRIORITY = "PVTSSF_lAHOABvqFM4BAC-Pzgy-ANw"  # single select
FIELD_SIZE = "PVTSSF_lAHOABvqFM4BAC-Pzgy-AN0"      # single select
# Estimate field currently treated as generic field; CLI rejects text updates (likely number type or unsupported via item-edit for issue items). Skipping automatic updates.
FIELD_ESTIMATE = "PVTF_lAHOABvqFM4BAC-Pzgy-AN4"

PRIORITY_OPTIONS = {  # name -> option id (updated with P3)
    # P0 not present currently
    "P1": "167bf1e6",
    "P2": "5f467c99",
    "P3": "7febabd1",
}
SIZE_OPTIONS = {
    "XS": "70550aec",
    "S": "45ee563e",
    "M": "5e486d01",
    "L": "4f508161",
    "XL": "fb9c8ac9",
}

ISSUE_PLAN = {  # issue -> spec
    6:  {"priority": "P1", "size": "S",  "estimate": "0.5d"},
    8:  {"priority": "P1", "size": "M",  "estimate": "1d"},
    11: {"priority": "P1", "size": "L",  "estimate": "2d"},
    13: {"priority": "P1", "size": "S",  "estimate": "0.25d"},
    14: {"priority": "P1", "size": "M",  "estimate": "0.5d"},
    7:  {"priority": "P2", "size": "M",  "estimate": "0.75d"},
    9:  {"priority": "P2", "size": "M",  "estimate": "1d"},
    10: {"priority": "P2", "size": "S",  "estimate": "0.5d"},
    12: {"priority": "P3", "size": "L",  "estimate": "2d"},  # P3 not defined -> skip project priority field
    15: {"priority": "P2", "size": "L",  "estimate": "1.5d"},
    1:  {"priority": "P1", "size": "M",  "estimate": "1d"},
    2:  {"priority": "P1", "size": "M",  "estimate": "1d"},
    3:  {"priority": "P1", "size": "L",  "estimate": "1.5d"},
    4:  {"priority": "P2", "size": "L",  "estimate": "2d"},
    5:  {"priority": "P2", "size": "XL", "estimate": "3d"},
    16: {"priority": "P2", "size": "M",  "estimate": "1d"},
    17: {"priority": "P2", "size": "S",  "estimate": "0.5d"},
}

MILESTONE_TITLE = "Version 1"
ITEMS_JSON = Path("project_items.json")

def run(cmd, dry=False):
    if dry:
        print("DRY:", " ".join(cmd))
        return 0
    return subprocess.run(cmd, check=True).returncode

def parse_items():
    data = json.loads(ITEMS_JSON.read_text(encoding='utf-8'))
    mapping = {}
    for it in data.get('items', []):
        content = it.get('content') or {}
        num = content.get('number')
        if num is not None:
            mapping[num] = it['id']
    return mapping

def milestone_number():
    # Use double quotes for jq expression and escape internal quotes for cross-shell compatibility
    jq_filter = f".[] | select(.title==\"{MILESTONE_TITLE}\") | .number"
    out = subprocess.check_output([
        'gh','api','repos/nam20485/cloud-ws/milestones','--jq',jq_filter
    ]).decode().strip().splitlines()
    if not out:
        raise SystemExit(f"Milestone {MILESTONE_TITLE} not found")
    return out[0]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dry', action='store_true', help='dry-run')
    args = ap.parse_args()

    if shutil.which('gh') is None:
        print('gh CLI required', file=sys.stderr)
        sys.exit(1)
    if not ITEMS_JSON.exists():
        print('project_items.json missing – fetching ...')
        # Capture stdout to file via shell redirection portable method using Python
        with open(ITEMS_JSON, 'w', encoding='utf-8') as f:
            subprocess.run(['gh','project','item-list',str(PROJECT_NUMBER),'--owner','nam20485','--limit','200','--format','json'], check=True, stdout=f)
    items = parse_items()
    ms = milestone_number()  # numeric, but gh issue edit appears to expect title on Windows gh 2.74

    missing = [i for i in ISSUE_PLAN if i not in items]
    if missing:
        print('WARNING: issues missing from project items (skip):', missing)

    for issue, spec in ISSUE_PLAN.items():
        item_id = items.get(issue)
        if not item_id:
            continue
        prio = spec['priority']
        opt = PRIORITY_OPTIONS.get(prio)
        if opt:
            run(['gh','project','item-edit','--id',item_id,'--project-id',PROJECT_ID,'--field-id',FIELD_PRIORITY,'--single-select-option-id',opt], dry=args.dry)
        else:
            print(f"Skip project Priority for #{issue} (option '{prio}' not defined)")
        run(['gh','project','item-edit','--id',item_id,'--project-id',PROJECT_ID,'--field-id',FIELD_SIZE,'--single-select-option-id',SIZE_OPTIONS[spec['size']]], dry=args.dry)
    # Skip Estimate due to API limitation (error when sending text). You can set manually if needed.
    run(['gh','issue','edit',str(issue),'--repo','nam20485/cloud-ws','--milestone',MILESTONE_TITLE], dry=args.dry)

    print('Done.' if not args.dry else 'Dry-run done.')

if __name__ == '__main__':
    main()
