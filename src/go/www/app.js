'use strict';

// Installed software panel: fetch /api/software, then filter and sort client-side.
const software = {
  items: [],
  sortKey: 'Name',
  sortDir: 1,
  els: {
    machine: document.getElementById('machine'),
    count: document.getElementById('software-count'),
    filter: document.getElementById('software-filter'),
    refresh: document.getElementById('software-refresh'),
    status: document.getElementById('software-status'),
    body: document.getElementById('software-body'),
    headers: document.querySelectorAll('th[data-sort]'),
  },
};

async function loadSoftware() {
  const { els } = software;
  els.refresh.disabled = true;
  els.status.className = 'muted';
  els.status.textContent = 'Reading installed software…';

  try {
    const res = await fetch('/api/software');
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || `HTTP ${res.status}`);

    software.items = data.items;
    els.machine.textContent =
      `${data.computerName} · updated ${new Date(data.generatedAt).toLocaleString()}`;
    els.status.textContent = '';
    renderSoftware();
  } catch (err) {
    els.status.className = 'error';
    els.status.textContent = `Could not load installed software: ${err.message}`;
  } finally {
    els.refresh.disabled = false;
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

loadSoftware();
