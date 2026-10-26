# System Dashboard

A local web dashboard showing information about the machine it runs on.

## Runtime

- Runs on the target machine without installing any other software.
- Serves a web page that is viewed in the default browser at `http://localhost:<port>/`.
    - Default port: 8080.
    - The port can be changed with a command-line option.
    - Can open the default browser automatically on start.
- Prints the dashboard's URL on start, and a line per request (time, method, path, status).
- If the port is already in use, exits with an error that suggests choosing another port.
- Stops cleanly on Ctrl+C.

## Security

- Listens on the loopback interface only; other machines cannot reach it.
- No authentication, so it must not be exposed beyond the local machine.
- Read-only: it never changes the machine.

## Features

- Retrieve a list of the software installed on the machine.
    - Same entries as [list_installed_software](list_installed_software.md): name and version, a missing version shown as `N/A`, and duplicate name + version entries listed once.
    - Display them in a table.
        - Columns: Name, Version.
        - Sorted by name, ascending, by default.
        - Click a column header to sort by it; click again to reverse the order. Sorting is case-insensitive and orders numbers naturally (e.g. `2` before `10`).
    - Filter the table by text matching the name or version (case-insensitive).
    - Show the number of items, or `<shown> of <total>` while a filter is applied.
    - Refresh button to re-read the list from the machine.
    - Show the computer name and when the list was last read.
    - Show a loading message while the list is read, and an error message if it can't be loaded.

## User interface

- A single page, with each feature in its own panel.
- Follows the system's light or dark theme.
- Usable on narrow windows: controls wrap, and the table scrolls sideways when needed.
- Text from the machine (e.g. software names) is always displayed as plain text, never interpreted as HTML.

## API

The page gets its data from a JSON API on the same server.

- `GET /api/software` returns:

    ```json
    {
      "computerName": "MY-PC",
      "generatedAt": "2026-10-26T11:20:17.123+08:00",
      "items": [{ "Name": "Git", "Version": "2.39.1" }]
    }
    ```

    - `generatedAt` is an ISO 8601 timestamp of when the list was read, in local time with its time-zone offset.
    - `items` is always an array, even when empty.
- Unknown `/api/` paths return `404` with `{ "error": "<message>" }`.
- Any other path serves a file of the page (`/` serves the page itself); unknown files return `404`.
- Only read requests are accepted; methods such as `POST` return `405`.
- Responses are not cached by the browser (`Cache-Control: no-store`), so Refresh always shows current data.
