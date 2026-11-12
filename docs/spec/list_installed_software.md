# List Installed Software

- List the following information about the system
    - Turn on/off with an option (default: on)
    - Host Name
    - IP Addresses
        - The addresses of the machine's active network interfaces, IPv4 first.
        - Loopback and link-local addresses (`127.x.x.x`, `::1`, `169.254.x.x`, `fe80::`) are skipped.
        - Shown as `N/A` if there are none (an empty list in json).
    - Current Timestamp

- List the software that are currently installed on the system.
    - Output fields:
        - Software Name/Description
        - Version Number
    - A missing version is shown as `N/A`.
    - Duplicate name + version entries (e.g. the same software listed in more than one place) are listed once.

- Output formats:
    - text (default)
    - csv
    - json
    - html
