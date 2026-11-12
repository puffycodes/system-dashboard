# List Installed Software

- List the following information about the system
    - Turn on/off with an option (default: on)
    - Host Name
    - IP Addresses
        - The addresses of the machine's active network interfaces, IPv4 first.
        - Loopback and link-local addresses (`127.x.x.x`, `::1`, `169.254.x.x`, `fe80::`) are skipped.
        - Shown as `N/A` if there are none (an empty list in json).
    - Current Timestamp
        - ISO 8601 in local time with its time-zone offset, to the second (e.g. `2026-11-12T10:54:59+08:00`).
        - The batch script uses the system's date and time format instead, as cmd can't produce ISO 8601.

- List the software that are currently installed on the system.
    - Output fields:
        - Software Name/Description
        - Version Number
    - A missing version is shown as `N/A`.
    - Duplicate name + version entries (e.g. the same software listed in more than one place) are listed once.

- Output formats:
    - text (default)
        - With system information: `Host Name:`, `IP Addresses:` and `Timestamp:` lines, then a blank line, before the table.
        - An aligned `Name` / `Version` table. The batch script writes `Name  |  Version` lines instead, without a header.
    - csv
        - Header `"Name","Version"`, with all fields quoted.
        - With system information: `HostName`, `IPAddresses` and `Timestamp` columns before `Name` and `Version`, repeated on each row.
    - json
        - An array of `{"Name": ..., "Version": ...}` objects.
        - With system information: an object `{"HostName": ..., "IPAddresses": [...], "Timestamp": ..., "Software": [...]}`, with the array under `Software`.
    - html
        - A full page with a title, the item count and a `Name` / `Version` table.
        - With system information: the title names the host, and a `Host Name` / `IP Addresses` / `Timestamp` table comes before the item count.
    - Multiple IP addresses are separated by `, ` in text, csv and html.
