'use strict';

// System panel: filled from the same /api/software response, so Refresh updates it too.
const system = {
  host: document.getElementById('system-host'),
  ips: document.getElementById('system-ips'),
};

// Tabs: the selected one is kept in the URL (#software, #executables), so a
// reload or a link opens the same tab. Hidden tabs keep their state.
const tabs = [...document.querySelectorAll('[role="tab"]')];

function tabFromHash() {
  const name = location.hash.slice(1);
  return tabs.some((tab) => tab.dataset.tab === name) ? name : 'software';
}

function showTab(name) {
  for (const tab of tabs) {
    const selected = tab.dataset.tab === name;
    tab.setAttribute('aria-selected', String(selected));
    tab.tabIndex = selected ? 0 : -1;
    document.getElementById(tab.getAttribute('aria-controls')).hidden = !selected;
  }
}

function selectTab(tab) {
  tab.focus();
  if (location.hash !== `#${tab.dataset.tab}`) location.hash = tab.dataset.tab;
}

for (const tab of tabs) {
  tab.addEventListener('click', () => selectTab(tab));
  // Arrow keys move between tabs, as in the ARIA tabs pattern
  tab.addEventListener('keydown', (event) => {
    const i = tabs.indexOf(tab);
    const next = { ArrowRight: i + 1, ArrowLeft: i - 1, Home: 0, End: tabs.length - 1 }[event.key];
    if (next === undefined) return;
    event.preventDefault();
    selectTab(tabs[(next + tabs.length) % tabs.length]);
  });
}
window.addEventListener('hashchange', () => showTab(tabFromHash()));
showTab(tabFromHash());

// Installed software tab: fetch /api/software, then filter and sort client-side.
const software = {
  items: [],
  data: null, // last /api/software response, for Download
  sortKey: 'Name',
  sortDir: 1,
  els: {
    count: document.getElementById('software-count'),
    filter: document.getElementById('software-filter'),
    refresh: document.getElementById('software-refresh'),
    format: document.getElementById('software-format'),
    download: document.getElementById('software-download'),
    time: document.getElementById('software-time'),
    status: document.getElementById('software-status'),
    body: document.getElementById('software-body'),
    headers: document.querySelectorAll('#panel-software th[data-sort]'),
  },
};

async function loadSoftware() {
  const { els } = software;
  els.refresh.disabled = true;
  els.download.disabled = true;
  els.status.className = 'muted';
  els.status.textContent = 'Reading installed software…';

  try {
    const res = await fetch('/api/software');
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || `HTTP ${res.status}`);

    software.items = data.items;
    software.data = data;
    system.host.textContent = data.computerName;
    system.ips.textContent = data.ipAddresses.length ? data.ipAddresses.join(', ') : 'N/A';
    els.time.textContent = `Read at ${new Date(data.generatedAt).toLocaleString()}`;
    els.status.textContent = '';
    renderSoftware();
  } catch (err) {
    els.status.className = 'error';
    els.status.textContent = `Could not load installed software: ${err.message}`;
  } finally {
    els.refresh.disabled = false;
    // After a failed refresh, the previous list can still be downloaded
    els.download.disabled = !software.data;
  }
}

function renderSoftware() {
  const { els, sortKey, sortDir } = software;
  const query = els.filter.value.trim().toLowerCase();

  const rows = software.items
    .filter((item) => !query ||
      item.Name.toLowerCase().includes(query) ||
      item.Version.toLowerCase().includes(query))
    .sort((a, b) => sortDir * a[sortKey].localeCompare(b[sortKey], undefined, { numeric: true, sensitivity: 'base' }));

  // Build rows with textContent so names are never interpreted as HTML
  const fragment = document.createDocumentFragment();
  for (const item of rows) {
    const tr = document.createElement('tr');
    for (const value of [item.Name, item.Version]) {
      const td = document.createElement('td');
      td.textContent = value;
      tr.appendChild(td);
    }
    fragment.appendChild(tr);
  }
  els.body.replaceChildren(fragment);

  els.count.textContent = query
    ? `${rows.length} of ${software.items.length}`
    : `${software.items.length}`;

  showSortOrder(els.headers, sortKey, sortDir);
}

function showSortOrder(headers, sortKey, sortDir) {
  for (const th of headers) {
    th.setAttribute('aria-sort',
      th.dataset.sort === sortKey ? (sortDir === 1 ? 'ascending' : 'descending') : 'none');
  }
}

// Executables tab: nothing is searched until Scan is pressed, because a full
// search can take minutes. The result stays until the next Scan.
const executables = {
  items: [],
  sorted: null, // items in the table's sort order, rebuilt when the data or sort changes
  data: null, // last /api/executables response, for Download
  sortKey: 'Directory',
  sortDir: 1,
  scanning: false,
  els: {
    count: document.getElementById('executables-count'),
    filter: document.getElementById('executables-filter'),
    scan: document.getElementById('executables-scan'),
    format: document.getElementById('executables-format'),
    download: document.getElementById('executables-download'),
    all: document.getElementById('executables-all'),
    categories: document.querySelectorAll('#panel-executables input[name="category"]'),
    time: document.getElementById('executables-time'),
    status: document.getElementById('executables-status'),
    body: document.getElementById('executables-body'),
    more: document.getElementById('executables-more'),
    headers: document.querySelectorAll('#panel-executables th[data-sort]'),
  },
};

// Building more rows than this makes the page slow; the filter finds the rest
const maxExecutableRows = 5000;

const categoryLabels = {
  Executable: 'Executables',
  Library: 'Dynamic Libraries',
  Script: 'Scripts',
  Installer: 'Installers',
  Other: 'Others',
};

function selectedCategories() {
  return [...executables.els.categories].filter((box) => box.checked).map((box) => box.value);
}

function updateScanButton() {
  executables.els.scan.disabled = executables.scanning || selectedCategories().length === 0;
}

// "All" is ticked when every category is, and partly ticked when only some are
function updateAllCheckbox() {
  const { all, categories } = executables.els;
  const ticked = selectedCategories().length;
  all.checked = ticked === categories.length;
  all.indeterminate = ticked > 0 && ticked < categories.length;
}

function elapsed(ms) {
  const seconds = Math.floor(ms / 1000);
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`;
}

async function scanExecutables() {
  const { els } = executables;
  const categories = selectedCategories();
  executables.scanning = true;
  updateScanButton();
  els.download.disabled = true;
  els.status.className = 'muted';

  const started = Date.now();
  const tick = () => {
    els.status.textContent = `Searching the local disks… ${elapsed(Date.now() - started)}`;
  };
  tick();
  const timer = setInterval(tick, 1000);

  try {
    const res = await fetch(`/api/executables?categories=${categories.join(',')}`);
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || `HTTP ${res.status}`);

    executables.items = data.items;
    executables.sorted = null;
    executables.data = data;
    els.time.textContent = `Read at ${new Date(data.generatedAt).toLocaleString()} · ` +
      data.categories.map((name) => categoryLabels[name] || name).join(', ');
    els.status.textContent = '';
    renderExecutables();
  } catch (err) {
    els.status.className = 'error';
    els.status.textContent = `Could not scan for executables: ${err.message}`;
  } finally {
    clearInterval(timer);
    executables.scanning = false;
    updateScanButton();
    // After a failed scan, the previous list can still be downloaded
    els.download.disabled = !executables.data;
  }
}

const collator = new Intl.Collator(undefined, { numeric: true, sensitivity: 'base' });

function compareExecutables(a, b, key) {
  return key === 'Size' ? a.Size - b.Size : collator.compare(a[key], b[key]);
}

function renderExecutables() {
  const { els, sortKey, sortDir } = executables;
  if (!executables.sorted) {
    // Ties are broken by directory, then name, the list's own order
    executables.sorted = [...executables.items].sort((a, b) =>
      sortDir * compareExecutables(a, b, sortKey) ||
      collator.compare(a.Directory, b.Directory) ||
      collator.compare(a.Name, b.Name));
  }

  const query = els.filter.value.trim().toLowerCase();
  const rows = query
    ? executables.sorted.filter((item) =>
      item.Name.toLowerCase().includes(query) ||
      item.Directory.toLowerCase().includes(query))
    : executables.sorted;

  // Build rows with textContent so names are never interpreted as HTML
  const fragment = document.createDocumentFragment();
  for (const item of rows.slice(0, maxExecutableRows)) {
    const tr = document.createElement('tr');
    const cells = [
      [item.Name], [item.Directory], [item.Size.toLocaleString(), 'num'], [item.Modified, 'nowrap'], [item.Category],
    ];
    for (const [value, className] of cells) {
      const td = document.createElement('td');
      td.textContent = value;
      if (className) td.className = className;
      tr.appendChild(td);
    }
    fragment.appendChild(tr);
  }
  els.body.replaceChildren(fragment);

  els.more.hidden = rows.length <= maxExecutableRows;
  els.more.textContent = `Showing the first ${maxExecutableRows.toLocaleString()} of ` +
    `${rows.length.toLocaleString()} files. Use the filter to find the others, or download the whole list.`;

  els.count.textContent = query
    ? `${rows.length} of ${executables.items.length}`
    : `${executables.items.length}`;

  showSortOrder(els.headers, sortKey, sortDir);
}

// Download: the same formats and layout as list_installed_software.sh and
// list_executables.sh. Always the whole list, in the order the server sent it
// (the scripts' order), whatever the table's filter and sort.
const downloadTypes = {
  text: { ext: 'txt', type: 'text/plain' },
  csv: { ext: 'csv', type: 'text/csv' },
  json: { ext: 'json', type: 'application/json' },
  html: { ext: 'html', type: 'text/html' },
};

// As in the scripts: ISO 8601 to the second, with the time-zone offset
function isoSeconds(timestamp) {
  return timestamp.replace(/\.\d+/, '').replace(/Z$/, '+00:00');
}

const csvField = (s) => `"${String(s).replace(/"/g, '""')}"`;
const htmlText = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;')
  .replace(/>/g, '&gt;').replace(/"/g, '&quot;');

function systemInfo(data) {
  return {
    host: data.computerName,
    ipList: data.ipAddresses,
    ips: data.ipAddresses.length ? data.ipAddresses.join(', ') : 'N/A',
    time: isoSeconds(data.generatedAt),
  };
}

// The installed software formats, with the system information first
const softwareFormats = {
  text(items, info) {
    const width = Math.max(4, ...items.map((item) => item.Name.length));
    const row = (name, version) => `${name.padEnd(width)}  ${version}\n`;
    return `Host Name:    ${info.host}\n` +
      `IP Addresses: ${info.ips}\n` +
      `Timestamp:    ${info.time}\n\n` +
      row('Name', 'Version') +
      row('----', '-------') +
      items.map((item) => row(item.Name, item.Version)).join('');
  },

  csv(items, info) {
    const prefix = `${csvField(info.host)},${csvField(info.ips)},${csvField(info.time)},`;
    return '"HostName","IPAddresses","Timestamp","Name","Version"\n' +
      items.map((item) => `${prefix}${csvField(item.Name)},${csvField(item.Version)}\n`).join('');
  },

  json(items, info) {
    const str = JSON.stringify;
    return '{\n' +
      `  "HostName": ${str(info.host)},\n` +
      `  "IPAddresses": [${info.ipList.map(str).join(', ')}],\n` +
      `  "Timestamp": ${str(info.time)},\n` +
      '  "Software": [\n' +
      items.map((item, i) => `    {"Name": ${str(item.Name)}, "Version": ${str(item.Version)}}` +
        (i < items.length - 1 ? ',\n' : '\n')).join('') +
      '  ]\n}\n';
  },

  html(items, info) {
    const title = `Installed software on ${htmlText(info.host)}`;
    return '<!DOCTYPE html>\n' +
      `<html><head><meta charset="utf-8"><title>${title}</title></head><body>\n` +
      `<h1>${title}</h1>\n` +
      '<table>\n' +
      `<tr><th>Host Name</th><td>${htmlText(info.host)}</td></tr>\n` +
      `<tr><th>IP Addresses</th><td>${htmlText(info.ips)}</td></tr>\n` +
      `<tr><th>Timestamp</th><td>${htmlText(info.time)}</td></tr>\n` +
      '</table>\n' +
      `<p>${items.length} items</p>\n` +
      '<table>\n' +
      '<tr><th>Name</th><th>Version</th></tr>\n' +
      items.map((item) => `<tr><td>${htmlText(item.Name)}</td><td>${htmlText(item.Version)}</td></tr>\n`).join('') +
      '</table>\n' +
      '</body></html>\n';
  },
};

// The executables formats, as list_executables.sh writes them
const executableFormats = {
  text(items) {
    // A loop, not Math.max(...): the list can be longer than a call's argument limit
    const width = (key, min) => items.reduce((w, item) => Math.max(w, String(item[key]).length), min);
    const wn = width('Name', 4);
    const wd = width('Directory', 9);
    const ws = width('Size', 4);
    const row = (name, dir, size, modified, category) =>
      `${name.padEnd(wn)}  ${dir.padEnd(wd)}  ${size.padStart(ws)}  ${modified.padEnd(25)}  ${category}\n`;
    return row('Name', 'Directory', 'Size', 'Modified', 'Category') +
      row('----', '---------', '----', '--------', '--------') +
      items.map((item) => row(item.Name, item.Directory, String(item.Size), item.Modified, item.Category)).join('');
  },

  csv(items) {
    return '"Name","Directory","Size","Modified","Category"\n' +
      items.map((item) => [item.Name, item.Directory, item.Size, item.Modified, item.Category]
        .map(csvField).join(',') + '\n').join('');
  },

  json(items) {
    const str = JSON.stringify;
    return '[\n' +
      items.map((item, i) => `  {"Name": ${str(item.Name)}, "Directory": ${str(item.Directory)}, ` +
        `"Size": ${item.Size}, "Modified": ${str(item.Modified)}, "Category": ${str(item.Category)}}` +
        (i < items.length - 1 ? ',\n' : '\n')).join('') +
      ']\n';
  },

  html(items) {
    return '<!DOCTYPE html>\n' +
      '<html><head><meta charset="utf-8"><title>Executable files</title></head><body>\n' +
      '<h1>Executable files</h1>\n' +
      `<p>${items.length} files</p>\n` +
      '<table>\n' +
      '<tr><th>Name</th><th>Directory</th><th>Size</th><th>Modified</th><th>Category</th></tr>\n' +
      items.map((item) => `<tr><td>${htmlText(item.Name)}</td><td>${htmlText(item.Directory)}</td>` +
        `<td>${item.Size}</td><td>${htmlText(item.Modified)}</td><td>${htmlText(item.Category)}</td></tr>\n`).join('') +
      '</table>\n' +
      '</body></html>\n';
  },
};

// <prefix>_<hostname>_<YYYYMMDD_HHMMSS>.<ext>, using the time the list was read
// in the machine's local time, as in the file. Characters that aren't allowed
// in Windows file names are replaced with "_".
function downloadFileName(prefix, host, time, ext) {
  const safeHost = host.replace(/[<>:"/\\|?*\x00-\x1f]/g, '_');
  // time is "YYYY-MM-DDTHH:MM:SS<offset>"
  const stamp = `${time.slice(0, 10).replace(/\D/g, '')}_${time.slice(11, 19).replace(/\D/g, '')}`;
  return `${prefix}_${safeHost}_${stamp}.${ext}`;
}

function saveFile(text, format, name) {
  const blob = new Blob([text], { type: `${format.type};charset=utf-8` });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = name;
  link.click();
  setTimeout(() => URL.revokeObjectURL(url), 0);
}

function downloadSoftware() {
  const { data, els } = software;
  const format = downloadTypes[els.format.value];
  const info = systemInfo(data);
  saveFile(softwareFormats[els.format.value](data.items, info), format,
    downloadFileName('installed_software', info.host, info.time, format.ext));
}

function downloadExecutables() {
  const { data, els } = executables;
  const format = downloadTypes[els.format.value];
  saveFile(executableFormats[els.format.value](data.items), format,
    downloadFileName('executables', data.computerName, isoSeconds(data.generatedAt), format.ext));
}

// Click a column header to sort by it; click again to reverse the order
function sortOnClick(state, render) {
  for (const th of state.els.headers) {
    th.addEventListener('click', () => {
      if (state.sortKey === th.dataset.sort) {
        state.sortDir = -state.sortDir;
      } else {
        state.sortKey = th.dataset.sort;
        state.sortDir = 1;
      }
      state.sorted = null;
      render();
    });
  }
}

sortOnClick(software, renderSoftware);
software.els.filter.addEventListener('input', renderSoftware);
software.els.refresh.addEventListener('click', loadSoftware);
software.els.download.addEventListener('click', downloadSoftware);

sortOnClick(executables, renderExecutables);
let filterTimer;
executables.els.filter.addEventListener('input', () => {
  // The list can be long, so wait for a pause in typing
  clearTimeout(filterTimer);
  filterTimer = setTimeout(renderExecutables, 150);
});
executables.els.scan.addEventListener('click', scanExecutables);
executables.els.download.addEventListener('click', downloadExecutables);
for (const box of executables.els.categories) {
  box.addEventListener('change', () => {
    updateAllCheckbox();
    updateScanButton();
  });
}
// Ticking "All" selects every category; clearing it clears them all
executables.els.all.addEventListener('change', () => {
  for (const box of executables.els.categories) box.checked = executables.els.all.checked;
  updateAllCheckbox();
  updateScanButton();
});
updateAllCheckbox();

loadSoftware();
