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
- Stage 2 schema inspection: `library_sections` has `agent`, `scanner`, `language`, `user_fields`; `metadata_items` has `metadata_type`, `library_section_id`, `guid`, `extra_data`, `user_fields` and ID/parent keys.
- TV inventory: **1,024 shows**, **2,141 seasons**, **21,916 episodes**.
- Stage 3: TV agent is **tv.plex.agents.series** (modern Plex TV Series); all **1,024** shows have nonempty `extra_data` and **0** shows have populated `user_fields`.
- Neither observation identifies effective per-show episode ordering; do not equate empty `user_fields` with no overrides or assume populated `extra_data` is a TVDB indicator.
- Stage 4: user screenshot confirms TV library Advanced > Episode ordering is **The Movie Database**. No library-level change required.
- Stage 5: read-only scan of all **1,024 shows** found **zero** matches for `showOrdering`, `episodeOrdering`, `tmdbAiring`, and `episodeSort` in `metadata_items.extra_data`. These are *not* proof that there are no show overrides.
- Stage 6: `metadata_item_settings` **exists**, `library_section_settings` **does not**; confirmed `metadata_item_settings` columns include `id`, `guid`, `extra_data`, `account_id`. Plex documentation associates this table primarily with account-level viewing state, so its presence is not evidence of episode-order settings.
- Decision: stop speculative field scanning. TV library default is TMDB, with per-show ordering still **unverified**. The proper next step is security-reviewed access to Plex's `showOrdering` API property, with no token exposure or network transmission under the owner's diagnostic safety constraint. Do not make any mass changes from these exploratory findings. Do not infer a series' effective ordering solely from library defaults; per-show settings take precedence.

## Reference behavior
Plex announced that it will not alter current metadata on December 3. TheTVDB-specific orders will stop getting TheTVDB metadata updates; the legacy TheTVDB agent stops matching new shows/episodes. Plex advises TMDB ordering, with an exception for series that need alternate episode orders until TMDB episode groups become available.


### Validation — 2026-11-21 00:21 EST
- Executed `python3 scripts/plex_tvdb_inventory.py` on Plexs-Mac-mini after fast-forwarding repository to `2370201`.
- `AUDIT_STATUS=OK`; reported 2 libraries (1 movie, 1 TV), modern Plex Series agent, 1,024 shows, 2,141 seasons, 21,916 episodes.
- All four exploratory `extra_data` ordering marker counts remained zero.
- `SHOW_LEVEL_ORDERING_VERIFIED=NO`: no claims about per-show TheTVDB overrides can be made yet.

## Reusable read-only inventory
- Script: [`scripts/plex_tvdb_inventory.py`](../scripts/plex_tvdb_inventory.py).
- Runs entirely against the local SQLite library database in read-only mode.
- Only prints fixed, allowlisted category labels and integer totals; no raw metadata, secrets, titles, host identifiers, or paths.
- Does **not** determine per-series ordering, and an absent text marker must never be interpreted as proof of no TVDB overrides.
- To run from an already checked-out repository: `python3 scripts/plex_tvdb_inventory.py`.
- Running it against the active Plex database may report a momentary count snapshot; it cannot guarantee a transactionally complete, season-wide audit.
- Do not make any migration decisions from this script alone.

## Manual show-level verification
Plex Web > select TV show > Edit > Advanced > Episode ordering. Record only which of the defined values is selected, without copying authentication data. The valid selections are Library default, The Movie Database (Aired), TheTVDB (Aired), TheTVDB (DVD), and TheTVDB (Absolute). This check is useful to verify behavior but is not a substitute for an automated inventory of every show.

## Automation boundary
Plex's authenticated metadata API can expose `showOrdering`, but it normally requires a token. Current diagnostic constraints prohibit commands that could print or transmit credentials, including issuing token-bearing API calls. Accordingly the GitHub script intentionally does not call the API. A full 1,024-show classification remains blocked pending an explicitly approved secure method compatible with these constraints.

## Manual sample — November 21, 2026
- User checked one randomly selected TV show in Plex Web > Edit > Advanced > Episode ordering.
- The selection was **Library default**, which inherits the confirmed library-wide TMDB ordering.
- This sample is reassuring but does not establish that all 1,024 series lack overrides.
- No migration is approved or necessary based on currently verified evidence. Do not run a bulk refresh.

## Security review — 2026-11-21
- Verified against Plex's official authentication guidance that a claimed Plex server requires authenticated access for the library API; a local HTTP request is not exempt from authentication.
- Verified against Python-PlexAPI documentation that individual TV shows expose `showOrdering` with values `None` (library default), `tmdbAiring` (TMDB), `aired` (TheTVDB Aired), `dvd` (TheTVDB DVD), and `absolute` (TheTVDB Absolute).
- A complete automated show-level audit would ordinarily use authenticated requests to the Plex local API. Under the owner's current strict rule against commands capable of transmitting any credential, that request is **not authorized**, even if its output is sanitized or the server address is localhost.
- The SQLite inventory is working and has no per-show order classifications. Do **not** treat zero marker matches as zero TheTVDB overrides.
- A future fully automated audit requires a user-approved change to the credential-transmission constraint or a verified credential-free local interface that reliably exposes each show's effective setting. Neither is currently established.
- Until then: no bulk migration, no metadata refresh, no misleading compliance claim. Existing library default is TMDB and a manually sampled series inherited it.

References:
- https://support.plex.tv/articles/204059436-finding-an-authentication-token-x-plex-token/
- https://python-plexapi.readthedocs.io/en/latest/modules/video.html
