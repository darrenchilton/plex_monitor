#!/usr/bin/env python3
"""Read-only Plex TV episode-order audit via localhost API.

Security boundaries: localhost only, GET requests only, no proxies or redirects,
no token in URL/argv/logs/output, never prints raw API/config/database values.
Requires explicit user approval for sending the token to the LOCAL Plex server.
"""
from __future__ import annotations

import argparse
from collections import Counter
import getpass
import http.client
import plistlib
from pathlib import Path
import re
import sqlite3
import sys
from urllib.error import HTTPError, URLError
from urllib.request import HTTPHandler, ProxyHandler, HTTPRedirectHandler, Request, build_opener
import xml.etree.ElementTree as ET

ROOT = Path.home() / "Library/Application Support/Plex Media Server"
DB = ROOT / "Plug-in Support/Databases/com.plexapp.plugins.library.db"
# Never print or upload the content of either preference file.
PREFS = (
    Path.home() / "Library/Preferences/com.plexapp.plexmediaserver.plist",
    ROOT / "Preferences.xml",
)
ORDERS = {
    "": "LIBRARY_DEFAULT",
    "tmdbAiring": "TMDB_AIRED",
    "aired": "TVDB_AIRED",
    "dvd": "TVDB_DVD",
    "absolute": "TVDB_ABSOLUTE",
}
MAX_RESPONSE_BYTES = 2_000_000


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def plex_token() -> str:
    for path in PREFS:
        try:
            if not path.is_file():
                continue
            if path.suffix == ".plist":
                with path.open("rb") as fh:
                    root = plistlib.load(fh)
            else:
                root = ET.parse(path).getroot().attrib
            value = root.get("PlexOnlineToken")
            if isinstance(value, str) and value and "\r" not in value and "\n" not in value:
                return value
        except (OSError, ValueError, TypeError, ET.ParseError, plistlib.InvalidFileException):
            pass
    # getpass is hidden input; do not echo, store or print supplied token.
    value = getpass.getpass("Plex API token (hidden input; Enter to cancel): ")
    if not value or "\r" in value or "\n" in value:
        raise ValueError("TOKEN_NOT_AVAILABLE")
    return value


def ids() -> list[int]:
    with sqlite3.connect(DB.as_uri() + "?mode=ro", uri=True, timeout=5) as con:
        con.execute("PRAGMA query_only=ON")
        return [int(row[0]) for row in con.execute(
            "SELECT id FROM metadata_items WHERE metadata_type=2 "
            "AND library_section_id IN "
            "(SELECT id FROM library_sections WHERE section_type=2) ORDER BY id"
        )]


def classify(xml_data: bytes, expected: int) -> str:
    root = ET.fromstring(xml_data)
    # Require one matching show: silently accepting a mismatched response
    # could incorrectly mark a show as safe.
    matches = [item for item in root.iter()
               if item.tag in ("Directory", "Video")
               and item.get("ratingKey") == str(expected)]
    if len(matches) != 1:
        return "UNVERIFIED"
    item = matches[0]
    values = []
    if "showOrdering" in item.attrib:
        values.append(item.attrib["showOrdering"])
    for setting in item.iter("Setting"):
        if setting.get("id") == "showOrdering":
            if "value" in setting.attrib:
                values.append(setting.attrib["value"])
            else:
                return "UNVERIFIED"
    if not values or len(set(values)) != 1:
        return "UNVERIFIED"
    return ORDERS.get(values[0], "UNVERIFIED")


def main() -> None:
    parser = argparse.ArgumentParser(description="Read-only local Plex show-order audit")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--pilot", action="store_true", help="inspect first five show IDs")
    mode.add_argument("--all", action="store_true", help="inspect all TV show IDs")
    args = parser.parse_args()

    try:
        show_ids = ids()
    except (sqlite3.Error, OSError, ValueError):
        print("AUDIT_STATUS=DATABASE_ACCESS_FAILED")
        return
    if not show_ids:
        print("AUDIT_STATUS=NO_TV_SHOWS")
        return
    checked_ids = show_ids if args.all else show_ids[:5]

    try:
        token = plex_token()
    except (OSError, ValueError, EOFError, KeyboardInterrupt):
        print("AUDIT_STATUS=TOKEN_NOT_AVAILABLE")
        return

    opener = build_opener(ProxyHandler({}), HTTPHandler(), NoRedirect())
    result = Counter()
    affected: dict[str, list[int]] = {
        "TVDB_AIRED": [], "TVDB_DVD": [], "TVDB_ABSOLUTE": [], "UNVERIFIED": []
    }
    http_failures = 0

    for sid in checked_ids:
        # Only numeric IDs queried from the database can form the path.
        if not isinstance(sid, int) or sid < 1:
            result["UNVERIFIED"] += 1
            continue
        request = Request(
            "http://127.0.0.1:32400/library/metadata/"
            + str(sid) + "?includePreferences=1",
            headers={
                "X-Plex-Token": token,
                "Accept": "application/xml",
                "X-Plex-Client-Identifier": "local-tvdb-order-audit",
            },
            method="GET",
        )
        try:
            with opener.open(request, timeout=8) as response:
                # Prevent token forwarding on HTTP redirect.
                if response.status != 200:
                    raise ValueError("NOT_HTTP_200")
                data = response.read(MAX_RESPONSE_BYTES + 1)
                if len(data) > MAX_RESPONSE_BYTES:
                    raise ValueError("OVERSIZE_RESPONSE")
            category = classify(data, sid)
        except (HTTPError, URLError, TimeoutError, OSError, ValueError, ET.ParseError,
                http.client.HTTPException):
            category = "UNVERIFIED"
            http_failures += 1
        result[category] += 1
        if category in affected:
            affected[category].append(sid)

    # Only fixed labels and numeric rating keys. Never raw XML or exceptions.
    print("MODE=" + ("FULL" if args.all else "PILOT"))
    print("DB_SHOWS=" + str(len(show_ids)))
    print("REQUESTED=" + str(len(checked_ids)))
    for label in ("LIBRARY_DEFAULT", "TMDB_AIRED",
                  "TVDB_AIRED", "TVDB_DVD", "TVDB_ABSOLUTE", "UNVERIFIED"):
        print(label + "=" + str(result[label]))
    print("REQUEST_FAILURES=" + str(http_failures))
    for label in ("TVDB_AIRED", "TVDB_DVD", "TVDB_ABSOLUTE", "UNVERIFIED"):
        if affected[label]:
            # Numeric rating keys are safe to share. Titles and paths are not emitted.
            print(label + "_RATING_KEYS=" + ",".join(map(str, affected[label][:30])))
            if len(affected[label]) > 30:
                print(label + "_MORE_RATING_KEYS=" + str(len(affected[label]) - 30))
    if result["UNVERIFIED"] or http_failures:
        print("AUDIT_STATUS=INCOMPLETE")
    elif args.all and len(checked_ids) == len(show_ids):
        print("AUDIT_STATUS=COMPLETE")
    else:
        print("AUDIT_STATUS=PILOT_ONLY")


if __name__ == "__main__":
    main()
