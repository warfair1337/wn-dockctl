// server.js
const express      = require('express');
const Docker       = require('dockerode');
const { execSync } = require('child_process');
const os           = require('os');
const osu          = require('os-utils');

const docker = new Docker({ socketPath: '/var/run/docker.sock' });
const app    = express();

app.use(express.json());
app.use(express.static('public'));

function formatUptime(startedAt) {
  const diffMs = Date.now() - new Date(startedAt).getTime();
  const secs   = Math.floor(diffMs / 1000) % 60;
  const mins   = Math.floor(diffMs / 1000 / 60) % 60;
  const hrs    = Math.floor(diffMs / 1000 / 3600);
  return `${hrs}h ${mins}m ${secs}s`;
}

app.get('/containers', async (req, res) => {
  try {
    // System stats
    const cpuUtil = await new Promise(r => osu.cpuUsage(r));
    const totalMem = os.totalmem() / 1024 / 1024;
    const freeMem  = os.freemem()  / 1024 / 1024;
    const usedMem  = totalMem - freeMem;
    const memUtil  = usedMem / totalMem;
    const cpuInfo  = os.cpus()[0];
    const cpuModel = cpuInfo.model;
    const cpuCores = os.cpus().length;

    // GPU summary
    const gpuCsv = execSync(
      'nvidia-smi --query-gpu=index,name,memory.total,memory.used,memory.free --format=csv,noheader,nounits'
    ).toString().trim();
    const gpus = gpuCsv
      ? gpuCsv.split('\n').map(line => {
          const [i, name, tot, used, free] = line.split(',').map(s => s.trim());
          return { index: i, name, memoryTotalMb:+tot, memoryUsedMb:+used, memoryFreeMb:+free };
        })
      : [];

    // host-PID → used GPU MiB
    const rawApps = execSync(
      'nvidia-smi --query-compute-apps=pid,used_memory --format=csv,noheader,nounits'
    ).toString().trim();
    const gpuMap = rawApps
      ? Object.fromEntries(
          rawApps.split('\n').map(l => {
            const [pid, mem] = l.split(',').map(s => s.trim());
            return [pid, +mem];
          })
        )
      : {};

    // Containers
    const list = await docker.listContainers({ all: true });
    const containers = await Promise.all(list.map(async c => {
      const ctr  = docker.getContainer(c.Id);
      const info = await ctr.inspect();

      // Defaults for non-running
      let uptime      = '—';
      let memMiB      = 0;
      let gpuMemMiB   = 0;

      if (c.State === 'running') {
        // only now do stats & top
        const stats = await ctr.stats({ stream: false });
        memMiB = (stats.memory_stats.usage || 0) / 1024 / 1024;

        // sum all PIDs in container
        const top = await ctr.top();
        const pidIdx = top.Titles.findIndex(t => t.toLowerCase() === 'pid');
        gpuMemMiB = top.Processes
          .map(proc => proc[pidIdx])
          .reduce((sum, pid) => sum + (gpuMap[pid] || 0), 0);

        uptime = formatUptime(info.State.StartedAt);
      }

      return {
        id          : c.Id,
        name        : c.Names[0].replace(/^\//, ''),
        state       : c.State,
        uptime,
        memoryMb    : memMiB.toFixed(1),
        gpuMemoryMb : gpuMemMiB
      };
    }));

    res.json({
      containers,
      gpus,
      cpu: {
        model       : cpuModel,
        cores       : cpuCores,
        utilization : cpuUtil
      },
      system: {
        totalMb     : totalMem.toFixed(1),
        usedMb      : usedMem.toFixed(1),
        freeMb      : freeMem.toFixed(1),
        utilization : memUtil
      }
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

app.post('/containers/:id/:action', async (req, res) => {
  const { id, action } = req.params;
  if (!['start','stop','restart'].includes(action)) {
    return res.status(400).send('Invalid action');
  }
  try {
    await docker.getContainer(id)[action]();
    res.sendStatus(204);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

const PORT = process.env.PORT || 3000;
const HOST = process.env.HOST || '0.0.0.0';
app.listen(PORT, HOST, () =>
  console.log(`Listening at http://${HOST}:${PORT}`)
);

