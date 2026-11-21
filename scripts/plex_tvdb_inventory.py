#!/usr/bin/env python3
"""Read-only, aggregate-only Plex library/TV ordering discovery.

No network access, HTTP clients, credentials, config-file reads or writes.
Output is strictly predeclared labels and integer counts. This script does NOT
classify per-show episode ordering.
"""
from __future__ import annotations

import sqlite3
from pathlib import Path


def main() -> None:
    database = (
        Path.home()
        / "Library/Application Support/Plex Media Server"
        / "Plug-in Support/Databases"
        / "com.plexapp.plugins.library.db"
    )
    if not database.is_file():
        print("AUDIT_STATUS=DB_NOT_FOUND")
        return

    try:
        # SQLite's immutable=1 avoids modifying WAL or lock state, but may miss
        # recent uncheckpointed transactions. Use ordinary ro for live inventory.
        with sqlite3.connect(database.as_uri() + "?mode=ro", uri=True, timeout=5) as con:
            con.execute("PRAGMA query_only=ON")
            types = con.execute(
                "SELECT section_type, COUNT(*) FROM library_sections GROUP BY section_type"
            ).fetchall()
            by_type = {int(t): int(n) for t, n in types}
            print("LIBRARIES_TOTAL=" + str(sum(by_type.values())))
            for t, label in ((1, "MOVIE"), (2, "TV"), (8, "MUSIC")):
                print("LIBRARIES_" + label + "=" + str(by_type.get(t, 0)))
            print("LIBRARIES_OTHER=" + str(
                sum(v for k, v in by_type.items() if k not in (1, 2, 8))
            ))

            agents = {
                "tv.plex.agents.series": "MODERN_PLEX_SERIES",
                "com.plexapp.agents.thetvdb": "LEGACY_TVDB",
                "com.plexapp.agents.themoviedb": "LEGACY_TMDB",
            }
            for value, count in con.execute(
                "SELECT agent, COUNT(*) FROM library_sections "
                "WHERE section_type=2 GROUP BY agent"
            ):
                # Never print unknown database strings.
                print("TV_AGENT_" + agents.get(value, "UNRECOGNIZED")
                      + "=" + str(int(count)))

            counts = dict(con.execute(
                "SELECT metadata_type, COUNT(*) FROM metadata_items "
                "WHERE library_section_id IN "
                "(SELECT id FROM library_sections WHERE section_type=2) "
                "GROUP BY metadata_type"
            ).fetchall())
            for kind, label in ((2, "SHOWS"), (3, "SEASONS"), (4, "EPISODES")):
                print("TV_" + label + "=" + str(int(counts.get(kind, 0))))
            print("TV_OTHER_METADATA=" + str(sum(
                int(v) for k, v in counts.items() if k not in (2, 3, 4)
            )))

            markers = ("showOrdering", "episodeOrdering", "tmdbAiring", "episodeSort")
            for marker in markers:
                count = con.execute(
                    "SELECT COUNT(*) FROM metadata_items WHERE metadata_type=2 "
                    "AND library_section_id IN "
                    "(SELECT id FROM library_sections WHERE section_type=2) "
                    "AND instr(COALESCE(extra_data, ''), ?) > 0",
                    (marker,),
                ).fetchone()[0]
                print("EXTRA_DATA_" + marker.upper() + "_MATCHES=" + str(int(count)))

            print("SHOW_LEVEL_ORDERING_VERIFIED=NO")
            print("AUDIT_STATUS=OK")
    except (sqlite3.Error, OSError):
        # Do not print raw exceptions; they could contain sensitive paths or DB data.
        print("AUDIT_STATUS=FAILED")


if __name__ == "__main__":
    main()
