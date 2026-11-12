# Known Issues

## The Executables table is slow for very large lists

**Status:** open. No option has been chosen yet.

### Symptoms

When all categories are scanned on a typical Windows machine, the list has 271,962 items. In headless Chrome on the Go dashboard:

| Action | Time |
|---|---|
| Show the list after the scan | 31 s |
| Filter (each change of the filter text) | 1.7 s |
| Sort (each header click) | 6.6 s |

The page doesn't respond during these. With the default category (Executables only), the list is a few thousand items and the table is fast.

### Cause

- `renderExecutables()` in `www/app.js` rebuilds the whole table on every filter change and sort.
  - With all categories, that's 271,962 rows × 5 cells, about 1.36 million `<td>` elements.
  - Creating these elements and laying out the table takes most of the time.
- Sorting with `Intl.Collator` makes up part of the sort time, but the rebuild still dominates.
- Filtering converts every name and directory to lowercase on each change.
- The 5,000-row cap that used to hide the problem was removed so that the table shows the whole list.

### Options

1. **Virtual scrolling (recommended)**
    - Only the rows in view, about 50, are in the DOM. Spacers above and below keep the scrollbar's size and position right.
    - Expected effect, not measured yet: showing takes milliseconds, and filtering and sorting cost only the work on the data.
    - Trade-offs:
        - Rows need a fixed height, so long directories can't wrap. They'd be cut off with "…" and show the full path on hover (`title`).
        - Columns need fixed widths (`table-layout: fixed`).
        - The browser's Ctrl+F only finds the rows that are on screen. The table's own filter still searches every row.
    - It's about 60–80 lines in `app.js`, with no change to the API or the servers.
2. **Pagination**
    - Show, say, 1,000 rows per page with Previous and Next controls.
    - It's simpler than virtual scrolling and about as fast, but you page through the list instead of scrolling.
    - The spec would need to describe the paging controls.
3. **Let the browser skip off-screen rows**
    - Use `content-visibility: auto` (with `contain-intrinsic-size`) and `table-layout: fixed`.
    - It's a few lines of CSS. Every row stays in the DOM, so Ctrl+F still works.
    - It cuts layout and drawing time, but all the elements are still created. Showing would likely take a few seconds rather than 31, not milliseconds.
4. **Render in chunks**
    - Show the first few hundred rows at once and append the rest in batches, for example with `requestIdleCallback`.
    - The page is usable sooner, but the total work is unchanged. A filter or sort made while rows are still being added has to cancel the pending batches.
5. **Smaller improvements, to combine with any of the above**
    - Prepare the lowercase name and directory and the formatted size once when the list loads, not on every render.
    - Keep the sorted list for each column, so clicking the same header again just reverses it.
6. **Paging, filtering and sorting on the server (not recommended)**
    - This means adding `offset`, `limit`, `filter` and `sort` to `/api/executables` in both servers.
    - It's a big change. The PowerShell server handles one request at a time, so each page request would wait for a scan in progress.

### Recommendation and next steps

- Recommendation: options 1 and 5 together.
- Before implementing, update `docs/spec/system-dashboard.md` to say that long directories are cut off, with the full path on hover.
- Keep `src/go/www` and `src/powershell/www` identical.
- Measure again with all categories: show, filter and sort times. The headless Chrome scripts used for the timings above are in the session scratchpad and aren't part of the repo.
