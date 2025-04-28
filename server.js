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

// format uptime like “0h 12m 37s”
function formatUptime(startedAt) {
  const diffMs = Date.now() - new Date(startedAt).getTime();
  const secs   = Math.floor(diffMs / 1000) % 60;
  const mins   = Math.floor(diffMs / 60000) % 60;
  const hrs    = Math.floor(diffMs / 3600000);
  return `${hrs}h ${mins}m ${secs}s`;
}

app.get('/containers', async (req, res) => {
  try {
    //
    // 1) Host CPU & Memory
    //
    const cpuUtil   = await new Promise(r => osu.cpuUsage(r)); 
    const totalMB   = os.totalmem() / 1024 / 1024;
    const freeMB    = os.freemem()  / 1024 / 1024;
    const usedMB    = totalMB - freeMB;
    const memUtil   = usedMB / totalMB;
    const cpus      = os.cpus();
    const cpuModel  = cpus[0].model;
    const cpuCores  = cpus.length;

    //
    // 2) GPU summary (host‐level)
    //
    const gpuCsv = execSync(
      'nvidia-smi --query-gpu=index,name,memory.total,memory.used,memory.free ' +
      '--format=csv,noheader,nounits'
    ).toString().trim();
    const gpus = gpuCsv
      ? gpuCsv.split('\n').map(line => {
          const [idx, name, tot, used, free] = line.split(',').map(s => s.trim());
          return {
            index       : idx,
            name,
            memoryTotalMb: +tot,
            memoryUsedMb : +used,
            memoryFreeMb : +free
          };
        })
      : [];

    // build a map: host‐pid → GPU‐MiB used
    const rawApps = execSync(
      'nvidia-smi --query-compute-apps=pid,used_memory ' +
      '--format=csv,noheader,nounits'
    ).toString().trim();
    const gpuMap = rawApps
      ? Object.fromEntries(
          rawApps.split('\n').map(l => {
            const [pid, mem] = l.split(',').map(s => s.trim());
            return [pid, +mem];
          })
        )
      : {};

    //
    // 3) Per-container stats
    //
    const containersRaw = await docker.listContainers({ all: true });
    const containers = [];

    for (const c of containersRaw) {
      const ctr   = docker.getContainer(c.Id);
      const info  = await ctr.inspect();

      // defaults for stopped/exited
      let uptime       = '—';
      let containerMB  = '—';
      let containerGPU = '—';

      if (c.State === 'running') {
        try {
          // a) uptime
          uptime = formatUptime(info.State.StartedAt);

          // b) “real” container RAM: usage minus cache = RSS
          const stats = await ctr.stats({ stream: false });
          const usage = stats.memory_stats.usage || 0;
          const cache = stats.memory_stats.stats?.cache || 0;
          const rss   = Math.max(usage - cache, 0);
          containerMB = (rss / 1024 / 1024).toFixed(1);

          // c) sum GPU‐MiB over every PID in this container
          const top = await ctr.top();
          const pidIdx = top.Titles.findIndex(t => t.toLowerCase() === 'pid');
          const sumGpu = top.Processes
            .map(proc => proc[pidIdx])
            .reduce((sum, pid) => sum + (gpuMap[pid] || 0), 0);
          containerGPU = sumGpu;
        } catch (innerErr) {
          console.error(`⚠️  failed stats for ${c.Id}:`, innerErr.message);
        }
      }

      containers.push({
        id           : c.Id,
        name         : c.Names[0].replace(/^\//, ''),
        state        : c.State,
        uptime,
        memoryMb     : containerMB,
        gpuMemoryMb  : containerGPU
      });
    }

    //
    // 4) send everything back
    //
    res.json({
      containers,
      gpus,
      cpu: {
        model       : cpuModel,
        cores       : cpuCores,
        utilization : cpuUtil
      },
      system: {
        totalMb     : totalMB.toFixed(1),
        usedMb      : usedMB.toFixed(1),
        freeMb      : freeMB.toFixed(1),
        utilization : memUtil
      }
    });
  } catch (err) {
    console.error('💥 GET /containers failed:', err);
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
    console.error(`💥 POST /containers/${id}/${action} failed:`, err);
    res.status(500).json({ error: err.message });
  }
});

const PORT = process.env.PORT || 3000;
const HOST = process.env.HOST || '0.0.0.0';
app.listen(PORT, HOST, () => {
  console.log(`✅ Server listening at http://${HOST}:${PORT}`);
});

