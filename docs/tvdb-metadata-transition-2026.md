# Plex TheTVDB metadata transition — December 2026

## Purpose
Inventory **all Plex libraries** on the Intel Mac mini, identify TV library and series-level episode-order settings that depend on TheTVDB, and plan a reviewable migration before the announced December 3, 2026 cutoff.

Official notice: https://forums.plex.tv/t/upcoming-change-thetvdb-metadata-support-ending-on-december-3rd/946215

## Repository and scope
- Repository: `darrenchilton/plex_monitor`.
- Host: existing macOS Plex Media Server.
- Inventory **every library**; TV libraries additionally require show-level ordering/legacy-agent review.
- This project is **separate from the existing Plex monitor**. Do not alter `scripts/plex_monitor.sh`, its launchd services, recovery logic or autodeploy behavior for the migration.
- Nothing here authorizes an automated metadata edit or refresh.

## Safety requirements
1. Read-only discovery first. Never modify a live Plex SQLite database.
2. Never print, log, upload, commit or paste API tokens, authorization headers, cookies, environment variable values, raw HTTP traces, raw application logs, private configuration or database dumps.
3. Diagnostics should emit only explicit safe fields: library name/type, show title, counts, recognized episode-order labels, and sanitized status/errors. Unrecognized content must be omitted, not printed.
4. Store any later reports locally and review them for privacy before committing aggregate summaries. Do **not** commit per-title inventories without explicit approval.
5. Before any migration, take a verified backup and record rollback procedure; exclude credentials from GitHub.
6. Avoid bulk refresh: changing episode order can mismatch specials, alternate/DVD/absolute orders and episode-level metadata.

## Work plan
- [ ] Verify macOS account/Plex database location and read-only DB access.
- [ ] Read schema safely (column names and table availability only; no raw rows or configuration).
- [ ] Inventory all libraries and TV shows, including inherited vs explicit episode-order overrides and legacy agents.
- [ ] Classify: already TMDB, TheTVDB aired candidate, alternate-order hold, legacy-agent migration, unknown/manual review.
- [ ] Review classification and back up Plex metadata before any mutation.
- [ ] Pilot changes on a few representative series, validate season/episode counts and specials, then consider broader changes.
- [ ] Re-audit and record outcomes.

## Findings
### Stage 1 — 2026-11-21
- Read-only access to Plex SQLite library database: **OK**.
- Required tables `library_sections` and `metadata_items`: **present**.
- Libraries: **2 total**, including **1 movies** and **1 TV**.
- Next step: inspect only allowlisted schema fields and aggregate TV show/season/episode counts. Do not infer a series' effective ordering solely from library defaults; per-show settings take precedence.

## Reference behavior
Plex announced that it will not alter current metadata on December 3. TheTVDB-specific orders will stop getting TheTVDB metadata updates; the legacy TheTVDB agent stops matching new shows/episodes. Plex advises TMDB ordering, with an exception for series that need alternate episode orders until TMDB episode groups become available.
