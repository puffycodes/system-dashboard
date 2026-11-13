# List Executables

On macOS, see also [macOS support](macos.md) for the volumes searched and the categories.

- Tag the list with the host it was read on, as in [list_installed_software](list_installed_software.md)
    - Turn on/off with an option (default: on)
    - Host Name
    - Current Timestamp

- List the executable files that exist on the system.
    - Scope of Listing:
        - Default: limit to local disks
    - File Types to List:
        - Category
            - Executables
            - Dynamic Libraries
            - Scripts
            - Installers
            - Others
        - Option to include each of the categories
            - Default: Executables Only
    - Output Fields:
        - File Name
        - Directory that the File is in
        - File Size
        - File Timestamp
        - File Category (e.g. executables, dynamic libraries, etc.)

- Output Formats:
    - text
        - With the host tag: `Host Name:` and `Timestamp:` lines, then a blank line, before the table.
    - csv
        - With the host tag: `HostName` and `Timestamp` columns before the file's columns, repeated on each row.
    - json
        - With the host tag: an object `{"HostName": ..., "Timestamp": ..., "Executables": [...]}`, with the array under `Executables`.
    - html
        - With the host tag: the title names the host, and a `Host Name` / `Timestamp` table comes before the file count.
