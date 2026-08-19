# youtube-aaa-playlist-clearer

A fast, repeatable Windows Python utility that clears every video from the user's YouTube playlist named `aaa` without deleting the playlist itself.

The script was created after a Telegram `/yt` mission to force-delete all videos from playlist `aaa` and make the operation reusable. It uses the logged-in local Chrome Profile 2 session (`michaelovsky22@gmail.com`) to authenticate to YouTube, reads the live playlist, removes each current playlist row with YouTube's safe playlist-row removal action, then re-reads the playlist and exits only when zero rows remain.

## What it does

`a.py` performs this workflow every time it runs:

1. Copies the Chrome Profile 2 cookie database to a temporary file.
2. Decrypts YouTube cookies locally using Windows DPAPI and the Chrome master key.
3. Fetches the live YouTube playlist page for playlist `aaa`.
4. Extracts authenticated Innertube configuration from the live page.
5. Reads all current playlist rows and their `setVideoId` values.
6. Removes rows using `ACTION_REMOVE_VIDEO` for this playlist only.
7. Re-reads the playlist and verifies that zero rows remain.
8. Prints `RESULT=PASS` only after verification succeeds.

It does **not** delete the YouTube playlist object, delete videos from YouTube, reorder unrelated playlists, or touch browser profile files except reading/copying cookies for authentication.

## Target playlist

- Playlist name: `aaa`
- Playlist ID: `PLtD44E7z8BkPPFsTc0pLUC2LCJh8HrgQA`
- URL: <https://www.youtube.com/playlist?list=PLtD44E7z8BkPPFsTc0pLUC2LCJh8HrgQA>

## Prerequisites

- Windows PowerShell 5 or Windows Terminal.
- Python from the Windows launcher: `py -3`.
- Python packages available in the Windows Python environment:
  - `requests`
  - `cryptography`
- Google Chrome Profile 2 must be logged in to the YouTube account that owns/can edit playlist `aaa`.
- Run on the same Windows user profile where Chrome stores Profile 2 cookies.

## Usage

### Clear playlist `aaa`

```powershell
py -3 F:\Downloads\a.py
```

The live runnable copy is intentionally preserved at `F:\Downloads\a.py` because that is the path requested for repeated future use.

### Run from this repository copy

```powershell
py -3 .\a.py
```

### Dry run / inspect current rows without deleting

```powershell
py -3 .\a.py --dry-run
```

### Use another playlist ID

```powershell
py -3 .\a.py --playlist-id PLxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

## Expected output

When the playlist has videos, the script prints each current row and then verifies removal:

```text
FOUND_ROWS=21
ROW[1] videoId=... setVideoId=... title=...
VERIFY_ROWS=0
REMOVED_ROWS=21
RESULT=PASS
```

When the playlist is already empty, the script is idempotent:

```text
FOUND_ROWS=0
VERIFY_ROWS=0
REMOVED_ROWS=0
RESULT=PASS
```

## Important files

- `a.py` â€” main reusable playlist-clearer script.
- `docs/verification/verification-run.txt` â€” latest repository verification run.
- `tools/check_py.py` â€” helper used during development to verify Windows Python dependencies.
- `tools/debug_ytcfg.py` â€” helper used during development to debug YouTube config extraction.

## Safety notes

- The script uses `setVideoId` with `ACTION_REMOVE_VIDEO`, which removes a video row from the playlist. This is the fast equivalent of YouTube UI action `Remove from playlist 'aaa'` / Hebrew `×”×¡×¨×” ×ž×”×¤×œ×™×™×œ×™×¡×˜ 'aaa'`.
- It never calls a playlist deletion endpoint.
- It verifies by re-reading the playlist after removal.
- If authentication fails, it prints `RESULT=FAIL` and does not claim success.
- If any rows remain after a retry, it prints those remaining rows and exits non-zero.

## Troubleshooting

### `No SAPISID-family YouTube auth cookie found`

Open YouTube in the real Chrome Profile 2 and sign in, then rerun the script.

### `Not authenticated to YouTube with Chrome Profile 2 cookies`

The cookies are stale or not for the right account. Reopen YouTube in Chrome Profile 2 and confirm the account can edit playlist `aaa`.

### Missing Python packages

Install the packages in the Windows Python environment:

```powershell
py -3 -m pip install requests cryptography
```

### Playlist still has rows

Run the script again. It is safe and idempotent; it re-reads the live playlist each time and removes only current rows from the configured playlist.

## Verification performed

- The live `F:\Downloads\a.py` script removed 21 videos from playlist `aaa`.
- A second run returned `FOUND_ROWS=0`, `VERIFY_ROWS=0`, `RESULT=PASS`.
- The repository copy was verified with `py -3 .\a.py --dry-run`.
