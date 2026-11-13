# System Dashboard

A local web dashboard showing information about the machine it runs on.

## Runtime

- Runs on the target machine without installing any other software.
- Serves a web page that is viewed in the default browser at `http://localhost:<port>/`.
    - Default port: 8080.
    - The port can be changed with a command-line option.
    - Can open the default browser automatically on start.
- A help option prints the command-line options and exits without starting the server.
- A version option prints the version and exits without starting the server. Packaged copies report the version in their package name.
- Prints the dashboard's URL on start, and a line per request (time, method, path, status).
- If the port is already in use, exits with an error that suggests choosing another port.
- Stops cleanly on Ctrl+C.

## Packaging

- One package per target: the PowerShell version, Windows x86-64, Linux x86-64 and Linux ARM64.
- Each package contains only the files needed on the target machine.
- Each package's files are in a folder named after the package, so extracting one never mixes its files with others.
- Each package includes a `README.txt` on starting, stopping and the options for that package, with its version.
- Linux packages keep the binary's executable permission.
- Checksums of the packages are provided in a `SHA256SUMS` file.

## Security

- Listens on the loopback interface only; other machines cannot reach it.
- No authentication, so it must not be exposed beyond the local machine.
- Read-only: it never changes the machine.

## Features

- Show information about the system, as in [list_host_information](list_host_information.md):
    - Host Name and IP Addresses.
    - Read when the page loads; reloading the page reads it again.
    - Each list shows when it was read in its own tab, so the System panel has no timestamp.
    - Shows `…` while it is read, and an error message in the panel if it can't be read.

- Retrieve a list of the software installed on the machine.
    - Same entries as [list_installed_software](list_installed_software.md): name and version, a missing version shown as `N/A`, and duplicate name + version entries listed once.
    - Display them in a table.
        - Columns: Name, Version.
        - Sorted by name, ascending, by default.
        - Click a column header to sort by it; click again to reverse the order. Sorting is case-insensitive and orders numbers naturally (e.g. `2` before `10`).
    - Filter the table by text matching the name or version (case-insensitive).
    - Show the number of items, or `<shown> of <total>` while a filter is applied.
    - Show when the list was read.
    - Refresh button to re-read the list from the machine.
    - Download button to download the list.
        - A dropdown menu to select the available format.
        - A label for the dropdown menu that says "Download Format".
        - The file formats should follow exactly those in [list_installed_software](list_installed_software.md).
        - Default download file name should be installed_software_<hostname>_<YYYYMMDD_HHMMSS>.<extension>.
        - The file includes the host tag (host name and timestamp), as list_installed_software does by default.
        - The file contains the whole list in list_installed_software's order, whatever the table's filter and sort.
        - The button is disabled until the list has loaded and while it is being refreshed.
    - Show a loading message while the list is read, and an error message if it can't be loaded.

- List the executable files on the machine, as in [list_executables](list_executables.md).
    - Searches the local disks only, like list_executables by default.
    - Category checkboxes: Executables, Dynamic Libraries, Scripts, Installers, Others.
        - Default: Executables only, as in list_executables.
        - An "All" checkbox before them selects or clears all five at once.
            - It is ticked when all five are ticked, and shown as partly ticked when only some are.
            - Ticking or clearing a category updates it.
        - Changing them takes effect on the next Scan.
    - Read only when asked: nothing is searched until the Scan button is pressed, because a full search can take minutes.
        - While scanning, show a message with the elapsed time, and disable Scan and Download.
        - A scan can't be cancelled.
        - The result stays until the next Scan, including across tab switches.
        - The PowerShell version answers no other requests while a scan runs, so the other tab's Refresh waits for it. The Go version stays responsive.
    - Display them in a table.
        - Columns: Name, Directory, Size, Modified, Category.
        - Size shown in bytes with thousands separators, and sorted as a number.
        - Sorted by directory, then name, by default; click a column header to sort, as in the installed software table.
    - Filter the table by text matching the name or directory (case-insensitive).
    - Show the number of items, or `<shown> of <total>` while a filter is applied.
    - Show when the list was read.
    - Download button to download the list, as for the installed software.
        - A dropdown menu to select the format, labelled "Download Format".
        - The file formats follow exactly those of [list_executables](list_executables.md).
        - Default download file name should be executables_<hostname>_<YYYYMMDD_HHMMSS>.<extension>.
        - The file includes the host tag (host name and timestamp), as list_executables does by default.
        - The file contains the whole list in list_executables' order, whatever the table's filter and sort.
    - Show an error message if the list can't be read.

## User interface

- A single page: the System panel at the top, then tabs for the lists.
    - Tabs: "Installed Software" (default) and "Executables".
    - The selected tab is kept in the URL (`#software`, `#executables`), so a reload or a link opens the same tab.
    - Each tab keeps its filter, sort and data when you switch away and back.
- Follows the system's light or dark theme.
- Usable on narrow windows: controls wrap, and the table scrolls sideways when needed.
- Text from the machine (e.g. software names) is always displayed as plain text, never interpreted as HTML.

## API

The page gets its data from a JSON API on the same server.

- `GET /api/host` returns:

    ```json
    {
      "computerName": "MY-PC",
      "ipAddresses": ["192.168.1.10"],
      "generatedAt": "2026-10-26T11:20:17.123+08:00"
    }
    ```

    - The same information as list_host_information.
    - `ipAddresses` lists the machine's IP addresses, IPv4 first. It is always an array, even when empty.
    - `generatedAt` is an ISO 8601 timestamp of when the information was read, in local time with its time-zone offset.
- `GET /api/software` returns:

    ```json
    {
      "computerName": "MY-PC",
      "generatedAt": "2026-10-26T11:20:17.123+08:00",
      "items": [{ "Name": "Git", "Version": "2.39.1" }]
    }
    ```

    - `computerName` and `generatedAt` are the host tag: the host name, and an ISO 8601 timestamp of when the list was read, in local time with its time-zone offset.
    - `items` is always an array, even when empty.
- `GET /api/executables?categories=executable,library` returns:

    ```json
    {
      "computerName": "MY-PC",
      "generatedAt": "2026-11-12T15:20:17+08:00",
      "categories": ["Executable", "Library"],
      "items": [{ "Name": "git.exe", "Directory": "C:\\Program Files\\Git\\cmd", "Size": 45056, "Modified": "2026-03-01T10:00:00+08:00", "Category": "Executable" }]
    }
    ```

    - `categories` takes the same names as list_executables' `-c` option (`executable`, `library`, `script`, `installer`, `other`, or `all` for every category), separated by commas. Default: `executable`. An unknown name returns `400` with `{ "error": "<message>" }`.
        - Names are case-sensitive, as with `-c`: `Executable` is an unknown name.
        - An empty list (e.g. `?categories=`) also returns `400`, as `-c` with no names is an error.
    - The response's `categories` lists the categories that were searched.
    - `computerName` and `generatedAt` are the host tag, as for `/api/software`.
    - `items` is always an array, even when empty, with the same fields and order as list_executables.
- Unknown `/api/` paths return `404` with `{ "error": "<message>" }`.
- Any other path serves a file of the page (`/` serves the page itself); unknown files return `404`.
- Only read requests are accepted; methods such as `POST` return `405`.
- Responses are not cached by the browser (`Cache-Control: no-store`), so Refresh always shows current data.
