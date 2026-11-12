'use strict';

// System panel: filled from the same /api/software response, so Refresh updates it too.
const system = {
  host: document.getElementById('system-host'),
  ips: document.getElementById('system-ips'),
  time: document.getElementById('system-time'),
};

// Installed software panel: fetch /api/software, then filter and sort client-side.
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
    status: document.getElementById('software-status'),
    body: document.getElementById('software-body'),
    headers: document.querySelectorAll('th[data-sort]'),
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
    system.time.textContent = new Date(data.generatedAt).toLocaleString();
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

  for (const th of els.headers) {
    th.setAttribute('aria-sort',
      th.dataset.sort === sortKey ? (sortDir === 1 ? 'ascending' : 'descending') : 'none');
  }
}

// Download: the same formats and layout as list_installed_software.sh, with
// the system information first. Always the whole list, in the order the server
// sent it (the scripts' order), whatever the table's filter and sort.
const downloadFormats = {
  text: { ext: 'txt', type: 'text/plain', build: formatText },
  csv: { ext: 'csv', type: 'text/csv', build: formatCsv },
  json: { ext: 'json', type: 'application/json', build: formatJson },
  html: { ext: 'html', type: 'text/html', build: formatHtml },
};

function systemInfo(data) {
  return {
    host: data.computerName,
    ipList: data.ipAddresses,
    ips: data.ipAddresses.length ? data.ipAddresses.join(', ') : 'N/A',
    // As in the scripts: ISO 8601 to the second, with the time-zone offset
    time: data.generatedAt.replace(/\.\d+/, '').replace(/Z$/, '+00:00'),
  };
}

function formatText(items, info) {
  const width = Math.max(4, ...items.map((item) => item.Name.length));
  const row = (name, version) => `${name.padEnd(width)}  ${version}\n`;
  return `Host Name:    ${info.host}\n` +
    `IP Addresses: ${info.ips}\n` +
    `Timestamp:    ${info.time}\n\n` +
    row('Name', 'Version') +
    row('----', '-------') +
    items.map((item) => row(item.Name, item.Version)).join('');
}

function formatCsv(items, info) {
  const field = (s) => `"${s.replace(/"/g, '""')}"`;
  const prefix = `${field(info.host)},${field(info.ips)},${field(info.time)},`;
  return '"HostName","IPAddresses","Timestamp","Name","Version"\n' +
    items.map((item) => `${prefix}${field(item.Name)},${field(item.Version)}\n`).join('');
}

function formatJson(items, info) {
  const str = JSON.stringify;
  return '{\n' +
    `  "HostName": ${str(info.host)},\n` +
    `  "IPAddresses": [${info.ipList.map(str).join(', ')}],\n` +
    `  "Timestamp": ${str(info.time)},\n` +
    '  "Software": [\n' +
    items.map((item, i) => `    {"Name": ${str(item.Name)}, "Version": ${str(item.Version)}}` +
      (i < items.length - 1 ? ',\n' : '\n')).join('') +
    '  ]\n}\n';
}

function formatHtml(items, info) {
  const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;')
    .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const title = `Installed software on ${esc(info.host)}`;
  return '<!DOCTYPE html>\n' +
    `<html><head><meta charset="utf-8"><title>${title}</title></head><body>\n` +
    `<h1>${title}</h1>\n` +
    '<table>\n' +
    `<tr><th>Host Name</th><td>${esc(info.host)}</td></tr>\n` +
    `<tr><th>IP Addresses</th><td>${esc(info.ips)}</td></tr>\n` +
    `<tr><th>Timestamp</th><td>${esc(info.time)}</td></tr>\n` +
    '</table>\n' +
    `<p>${items.length} items</p>\n` +
    '<table>\n' +
    '<tr><th>Name</th><th>Version</th></tr>\n' +
    items.map((item) => `<tr><td>${esc(item.Name)}</td><td>${esc(item.Version)}</td></tr>\n`).join('') +
    '</table>\n' +
    '</body></html>\n';
}

// installed_software_<hostname>_<YYYYMMDD_HHMMSS>.<ext>, using the time the list was
// read in the machine's local time, as in the file. Characters that aren't
// allowed in Windows file names are replaced with "_".
function downloadFileName(info, ext) {
  const host = info.host.replace(/[<>:"/\\|?*\x00-\x1f]/g, '_');
  // info.time is "YYYY-MM-DDTHH:MM:SS<offset>"
  const stamp = `${info.time.slice(0, 10).replace(/\D/g, '')}_${info.time.slice(11, 19).replace(/\D/g, '')}`;
  return `installed_software_${host}_${stamp}.${ext}`;
}

function downloadSoftware() {
  const { data, els } = software;
  const format = downloadFormats[els.format.value];
  const info = systemInfo(data);
  const blob = new Blob([format.build(data.items, info)], { type: `${format.type};charset=utf-8` });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = downloadFileName(info, format.ext);
  link.click();
  setTimeout(() => URL.revokeObjectURL(url), 0);
}

for (const th of software.els.headers) {
  th.addEventListener('click', () => {
    if (software.sortKey === th.dataset.sort) {
      software.sortDir = -software.sortDir;
    } else {
      software.sortKey = th.dataset.sort;
      software.sortDir = 1;
    }
    renderSoftware();
  });
}

software.els.filter.addEventListener('input', renderSoftware);
software.els.refresh.addEventListener('click', loadSoftware);
software.els.download.addEventListener('click', downloadSoftware);

loadSoftware();
