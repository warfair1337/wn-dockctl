<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Docker Controls</title>
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
      margin: 20px;
      background-color: #f4f6f8;
      color: #333;
    }
    h1 {
      margin-bottom: 1em;
      font-size: 1.75rem;
    }
    #dashboard {
      max-width: 1200px;
      margin: auto;
    }
    /* System Stats */
    #sys-stats {
      margin-bottom: 1.5em;
    }
    #sys-stats table {
      border-collapse: collapse;
      width: 100%;
      margin-bottom: 1em;
      background: #fff;
      box-shadow: 0 2px 4px rgba(0,0,0,0.1);
    }
    #sys-stats th,
    #sys-stats td {
      padding: 8px 12px;
      border-bottom: 1px solid #e1e5ea;
      text-align: left;
    }
    #sys-stats th {
      width: 30%;
      background-color: #f0f2f5;
    }
    /* GPU Stats */
    #gpu-stats {
      margin-bottom: 1.5em;
    }
    #gpu-stats table {
      border-collapse: collapse;
      width: 100%;
      margin-bottom: 1em;
      background: #fff;
      box-shadow: 0 2px 4px rgba(0,0,0,0.1);
    }
    #gpu-stats th,
    #gpu-stats td {
      padding: 8px 12px;
      border-bottom: 1px solid #e1e5ea;
      text-align: left;
    }
    /* Containers Table */
    table#ct-table {
      width: 100%;
      border-collapse: collapse;
      background: #fff;
      box-shadow: 0 2px 4px rgba(0,0,0,0.1);
    }
    #ct-table th,
    #ct-table td {
      padding: 10px 12px;
      border-bottom: 1px solid #e1e5ea;
      text-align: left;
    }
    #ct-table th {
      background-color: #f0f2f5;
    }
    tr.running {
      background-color: #e6ffed;
    }
    tr.exited {
      background-color: #ffecec;
    }
    tr:hover {
      background-color: #eef3f7;
    }
    button {
      padding: 6px 10px;
      border: none;
      border-radius: 4px;
      cursor: pointer;
      font-size: 0.9rem;
      transition: background 0.2s;
    }
    button[data-action="start"]   { background-color: #28a745; color: #fff; }
    button[data-action="stop"]    { background-color: #dc3545; color: #fff; }
    button[data-action="restart"] { background-color: #007bff; color: #fff; }
    button:disabled               { opacity: 0.6; cursor: not-allowed; }
  </style>
</head>
<body>
  <div id="dashboard">
    <h1>Docker Controls</h1>

    <!-- System Stats -->
    <div id="sys-stats">Loading system stats...</div>

    <!-- GPU summary -->
    <div id="gpu-stats">Loading GPU stats...</div>

    <!-- Containers Table -->
    <table id="ct-table">
      <thead>
        <tr>
          <th>Name</th>
          <th>Status</th>
          <th>Uptime</th>
          <th>Memory (MiB)</th>
          <th>GPU (MiB)</th>
          <th>Actions</th>
        </tr>
      </thead>
      <tbody></tbody>
    </table>
  </div>

  <script>
    async function load() {
      try {
        const res = await fetch('/containers');
        const { containers, gpus, cpu, system } = await res.json();

        // Render System Stats
        const sysDiv = document.getElementById('sys-stats');
        if (cpu && system) {
          let html = '<table>' +
            '<tr><th>CPU Model</th><td>' + cpu.model + '</td></tr>' +
            '<tr><th>Cores</th><td>' + cpu.cores + '</td></tr>' +
            '<tr><th>CPU Utilization</th><td>' + (cpu.utilization * 100).toFixed(1) + ' %</td></tr>' +
            '<tr><th>Total Memory</th><td>' + system.totalMb + ' MiB</td></tr>' +
            '<tr><th>Used Memory</th><td>' + system.usedMb + ' MiB</td></tr>' +
            '<tr><th>Free Memory</th><td>' + system.freeMb + ' MiB</td></tr>' +
            '<tr><th>Memory Utilization</th><td>' + (system.utilization * 100).toFixed(1) + ' %</td></tr>' +
            '</table>';
          sysDiv.innerHTML = html;
        } else {
          sysDiv.textContent = 'System stats unavailable.';
        }

        // Render GPU Stats
        const gpuDiv = document.getElementById('gpu-stats');
        if (gpus.length) {
          let html = '<table><tr><th>GPU</th><th>Total MiB</th><th>Used MiB</th><th>Free MiB</th></tr>';
          gpus.forEach(g => {
            html += '<tr>' +
              '<td>' + g.index + ' – ' + g.name + '</td>' +
              '<td>' + g.memoryTotalMb + '</td>' +
              '<td>' + g.memoryUsedMb + '</td>' +
              '<td>' + g.memoryFreeMb + '</td>' +
              '</tr>';
          });
          html += '</table>';
          gpuDiv.innerHTML = html;
        } else {
          gpuDiv.textContent = 'No NVIDIA GPU detected.';
        }

        // Render Containers Table
        const tbody = document.querySelector('#ct-table tbody');
        tbody.innerHTML = '';
        containers.forEach(c => {
          const tr = document.createElement('tr');
          tr.classList.add(c.state === 'running' ? 'running' : 'exited');
          tr.innerHTML = `
            <td>${c.name}</td>
            <td>${c.state}</td>
            <td>${c.uptime}</td>
            <td>${c.memoryMb}</td>
            <td>${c.gpuMemoryMb}</td>
            <td>
              <button data-action="${c.state === 'running' ? 'stop' : 'start'}">
                ${c.state === 'running' ? 'Stop' : 'Start'}
              </button>
              <button data-action="restart">Restart</button>
            </td>`;
          tr.querySelectorAll('button').forEach(btn => {
            btn.onclick = async () => {
              btn.disabled = true;
              await fetch(`/containers/${c.id}/${btn.dataset.action}`, { method: 'POST' });
              load();
            };
          });
          tbody.appendChild(tr);
        });
      } catch (err) {
        console.error(err);
      }
    }

    load();
    setInterval(load, 5000);
  </script>
</body>
</html>

