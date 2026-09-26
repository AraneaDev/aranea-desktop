#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

node - "$repo_root" <<'NODE'
const root = process.argv[2]
const m = require(`${root}/plugins/araneadev.health/MetricsLogic.js`)
const assert = (cond, msg) => { if (!cond) throw new Error(msg) }

// fixtures captured on this machine (2026-09-27)
const stat1 = 'cpu  644372 1410 171944 36311509 108470 67995 49168 0 0 0\ncpu0 1 2 3 4 5 6 7 0 0 0\n'
const stat2 = 'cpu  644472 1410 171994 36311859 108470 67995 49168 0 0 0\n'
const a = m.parseCpuStat(stat1), b = m.parseCpuStat(stat2)
assert(a && b && b.total - a.total === 500 && b.busy - a.busy === 150, 'cpu busy/total from the first line')
assert(m.cpuPercent(a, b) === 30, 'cpu percent from deltas')
assert(m.cpuPercent(null, b) === null, 'first sample has no percent')
assert(m.cpuPercent(b, a) === 0, 'counter going backwards is 0, never negative')
assert(m.parseCpuStat('garbage') === null, 'bad stat is unknown')
let hist = []
for (let i = 0; i < 65; i++) hist = m.pushHistory(hist, i, 60)
assert(hist.length === 60 && hist[0] === 5 && hist[59] === 64, 'history keeps the newest 60')

assert(m.parseLoadavg('0.84 0.71 0.66 2/1234 5678\n').join() === '0.84,0.71,0.66', 'loadavg')
const mem = m.parseMeminfo('MemTotal:       16088900 kB\nMemFree: 1 kB\nMemAvailable:   11529640 kB\nSwapTotal:      32177440 kB\nSwapFree:       32177440 kB\n')
assert(mem.memTotal === 16088900 * 1024 && mem.memUsed === (16088900 - 11529640) * 1024 && mem.swapUsed === 0, 'meminfo in bytes, used = total - available')
assert(m.parseMeminfo('') === null, 'empty meminfo is unknown')

const route = 'Iface\tDestination\tGateway\tFlags\nwlp2s0\t0000A8C0\t00000000\t0001\nwlp2s0\t00000000\t0100A8C0\t0003\n'
assert(m.defaultInterface(route) === 'wlp2s0', 'default route interface')
assert(m.defaultInterface('Iface\tDestination\n') === '', 'no default route')
const dev1 = 'Inter-|   Receive\n face |bytes\n    lo: 100 1 0 0 0 0 0 0 100 1 0 0 0 0 0 0\nwlp2s0: 1817394129 1610619    0 4408    0     0          0         0 272567143  439348    0    0    0     0       0          0\n'
const dev2 = 'wlp2s0: 1817742129 1610619 0 4408 0 0 0 0 272591143 439348 0 0 0 0 0 0\n'
const n1 = m.parseNetDev(dev1, 'wlp2s0'), n2 = m.parseNetDev(dev2, 'wlp2s0')
assert(n1.rx === 1817394129 && n1.tx === 272567143, 'net/dev rx/tx')
const rates = m.netRates(n1, n2, 2000)
assert(rates.down === 174000 && rates.up === 12000, 'rates per second')
assert(m.netRates(n2, n1, 2000).down === 0, 'counter reset is 0')
assert(m.parseNetDev(dev1, 'eth9') === null, 'missing interface is unknown')

const ps1 = '  94371 472200     590 claude\n 259390 393580       7 quickshell\n  61409 324316     296 chromium\n'
const ps2 = '  94371 472300     594 claude\n 259390 393580       7 quickshell\n  61409 330000     297 chromium\n  70000 1000 50 newbie\n'
const top = m.topProcesses(m.parsePs(ps1), m.parsePs(ps2), 2000, 3)
assert(top.cpu[0].comm === 'claude' && top.cpu[0].percent === 200 && top.cpu[1].comm === 'chromium' && top.cpu[1].percent === 50, 'cpu from cputime deltas (100% = one core)')
assert(!top.cpu.some(p => p.comm === 'newbie'), 'processes seen once have no cpu figure yet')
assert(top.mem[0].comm === 'claude' && top.mem[0].rss === 472300 * 1024, 'memory by rss')
assert(m.parsePs('') !== null && m.parsePs('').length === 0, 'empty ps is an empty list')

assert(m.formatUptime(46583) === 'up 12h 56m', 'hours and minutes')
assert(m.formatUptime(3 * 86400 + 4 * 3600 + 5) === 'up 3d 4h', 'days and hours')
assert(m.formatUptime(125) === 'up 2m', 'minutes')
assert(m.usageLevel(89) === 'normal' && m.usageLevel(90) === 'attention' && m.usageLevel(97) === 'critical', 'bar levels')
assert(m.humanBytes(4.4 * 1024 ** 3) === '4.4 GB' && m.humanBytes(16088900 * 1024) === '15 GB', 'human bytes')
assert(m.formatRate(348000) === '340 KB/s' && m.formatRate(0) === '0 B/s', 'rates')

console.log('metrics logic contract passed')
NODE

echo "metrics contract passed"
