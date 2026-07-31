document.addEventListener('DOMContentLoaded', function() {
  var appPrefix = document.body.dataset.appPrefix;
  var tableBody = document.querySelector('#workflows-table tbody');
  var searchInput = document.querySelector('#workflows-search');
  var pageInfo = document.querySelector('#workflows-page-info');
  var prevBtn = document.querySelector('#workflows-prev');
  var nextBtn = document.querySelector('#workflows-next');
  var headers = document.querySelectorAll('#workflows-table th[data-sort]');

  var state = {start: 0, length: 25, orderColumn: 1, orderDir: 'desc', search: ''};

  function updateSortIndicators() {
    headers.forEach(function(h) {
      h.removeAttribute('data-dir');
      if (parseInt(h.dataset.sort, 10) === state.orderColumn) {
        h.setAttribute('data-dir', state.orderDir);
      }
    });
  }

  function load() {
    var url = new URL(appPrefix + '/workflows', window.location.origin);
    url.searchParams.set('start', state.start);
    url.searchParams.set('length', state.length);
    url.searchParams.set('search[value]', state.search);
    url.searchParams.set('order[0][column]', state.orderColumn);
    url.searchParams.set('order[0][dir]', state.orderDir);

    fetch(url).then(function(res) { return res.json(); }).then(function(json) {
      tableBody.innerHTML = '';

      if (json.data.length === 0) {
        var emptyRow = document.createElement('tr');
        var emptyCell = document.createElement('td');
        emptyCell.colSpan = 4;
        emptyCell.className = 'px-4 py-8 text-center text-slate-400';
        emptyCell.textContent = 'No workflows found.';
        emptyRow.appendChild(emptyCell);
        tableBody.appendChild(emptyRow);
      }

      json.data.forEach(function(row, rowIndex) {
        var tr = document.createElement('tr');
        tr.className = (rowIndex % 2 === 0 ? 'bg-white' : 'bg-slate-50') + ' hover:bg-indigo-50 transition-colors';
        row.forEach(function(cell, i) {
          var td = document.createElement('td');
          td.className = i === row.length - 1 ? 'px-4 py-1.5 text-right' : 'px-4 py-1.5 text-slate-700';
          td.innerHTML = cell;
          tr.appendChild(td);
        });
        tableBody.appendChild(tr);
      });

      var from = json.recordsFiltered === 0 ? 0 : state.start + 1;
      var to = Math.min(state.start + state.length, json.recordsFiltered);
      pageInfo.textContent = 'Showing ' + from + '-' + to + ' of ' + json.recordsFiltered;
      prevBtn.disabled = state.start === 0;
      nextBtn.disabled = state.start + state.length >= json.recordsFiltered;
      updateSortIndicators();
    });
  }

  headers.forEach(function(h) {
    h.addEventListener('click', function() {
      var col = parseInt(h.dataset.sort, 10);
      if (state.orderColumn === col) {
        state.orderDir = state.orderDir === 'asc' ? 'desc' : 'asc';
      } else {
        state.orderColumn = col;
        state.orderDir = 'asc';
      }
      state.start = 0;
      load();
    });
  });

  var searchTimeout;
  searchInput.addEventListener('input', function() {
    clearTimeout(searchTimeout);
    searchTimeout = setTimeout(function() {
      state.search = searchInput.value;
      state.start = 0;
      load();
    }, 250);
  });

  prevBtn.addEventListener('click', function() {
    state.start = Math.max(0, state.start - state.length);
    load();
  });
  nextBtn.addEventListener('click', function() {
    state.start += state.length;
    load();
  });

  load();
});
