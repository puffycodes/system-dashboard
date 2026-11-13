# List Installed Software

- Tag the list with the host it was read on
    - Turn on/off with an option (default: on)
    - Host Name
        - The same as in [list_host_information](list_host_information.md).
    - Current Timestamp
        - ISO 8601 in local time with its time-zone offset, to the second (e.g. `2026-11-12T10:54:59+08:00`).
        - The batch script uses the system's date and time format instead, as cmd can't produce ISO 8601.
    - Other information about the host, such as its IP addresses, is listed by [list_host_information](list_host_information.md), not here.

- List the software that are currently installed on the system.
    - Output fields:
        - Software Name/Description
        - Version Number
    - A missing version is shown as `N/A`.
    - Duplicate name + version entries (e.g. the same software listed in more than one place) are listed once.

- Output formats:
    - text (default)
        - With the host tag: `Host Name:` and `Timestamp:` lines, then a blank line, before the table.
        - An aligned `Name` / `Version` table. The batch script writes `Name  |  Version` lines instead, without a header.
    - csv
        - Header `"Name","Version"`, with all fields quoted.
        - With the host tag: `HostName` and `Timestamp` columns before `Name` and `Version`, repeated on each row.
    - json
        - An array of `{"Name": ..., "Version": ...}` objects.
        - With the host tag: an object `{"HostName": ..., "Timestamp": ..., "Software": [...]}`, with the array under `Software`.
    - html
        - A full page with a title, the item count and a `Name` / `Version` table.
        - With the host tag: the title names the host, and a `Host Name` / `Timestamp` table comes before the item count.
