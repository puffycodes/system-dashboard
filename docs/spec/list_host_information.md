# List Host Information

- List the information that identifies the system.
    - Host Name
        - The computer name (`uname -n` on Linux), the same as in [list_installed_software](list_installed_software.md) and [list_executables](list_executables.md), so their files can be matched to this host.
    - IP Addresses
        - The addresses of the machine's active network interfaces, IPv4 first.
        - Loopback and link-local addresses (`127.x.x.x`, `::1`, `169.254.x.x`, `fe80::`) are skipped.
        - Shown as `N/A` if there are none (an empty list in json).
    - Timestamp
        - When the information was read: ISO 8601 in local time with its time-zone offset, to the second (e.g. `2026-11-12T10:54:59+08:00`).
        - The batch script uses the system's date and time format instead, as cmd can't produce ISO 8601.
    - More fields may be added later. Each format below allows for them without breaking existing readers.

- Output formats:
    - text (default)
        - One `<Label>: <value>` line per field, with the values aligned: `Host Name:`, `IP Addresses:`, `Timestamp:`.
    - csv
        - Header `"HostName","IPAddresses","Timestamp"` and one row, with all fields quoted.
    - json
        - An object `{"HostName": ..., "IPAddresses": [...], "Timestamp": ...}`.
    - html
        - A full page whose title names the host, with a two-column `Field` / `Value` table.
    - Multiple IP addresses are separated by `, ` in text, csv and html.
