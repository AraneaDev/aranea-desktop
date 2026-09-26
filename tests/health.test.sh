#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

node - "$repo_root" <<'NODE'
const root = process.argv[2]
const h = require(`${root}/plugins/araneadev.notifications/HealthLogic.js`)
const assert = (cond, msg) => { if (!cond) throw new Error(msg) }

// --- failed units
assert(h.parseFailedUnits('[]', 'system').length === 0, 'empty failed list')
const units = h.parseFailedUnits('[{"unit":"nginx.service","load":"loaded","active":"failed","sub":"failed","description":"nginx"}]', 'user')
assert(units.length === 1 && units[0].key === 'unit:user:nginx.service', 'failed unit keyed by scope')
assert(h.parseFailedUnits('garbage', 'system') === null, 'unparsable output is unknown')

// --- df (fixture captured on this machine: btrfs subvolumes share a source)
const df = [
  'Filesystem                  Mounted on            Type      1B-blocks        Used        Avail Use%',
  '/dev/mapper/root            /                     btrfs 1022042832896 930000000000 92042832896  91%',
  '/dev/mapper/root            /home                 btrfs 1022042832896 930000000000 92042832896  91%',
  '/dev/mapper/root            /var/cache/pacman/pkg btrfs 1022042832896 930000000000 92042832896  91%',
  '/dev/nvme0n1p1              /boot                 vfat     2143281152  1670791168   472489984  78%'
].join('\n')
const rows = h.parseDf(df)
assert(rows.length === 2, 'btrfs subvolumes collapse to one row per source')
assert(rows[0].target === '/' && rows[0].percent === 91, 'shortest mount point wins')
assert(h.parseDf('') === null, 'empty df output is unknown')

// --- disk thresholds and hysteresis
assert(h.diskLevel('ok', 89) === 'ok', 'below 90 is fine')
assert(h.diskLevel('ok', 90) === 'normal', '90 alerts')
assert(h.diskLevel('normal', 97) === 'critical', '97 is critical')
assert(h.diskLevel('critical', 95) === 'normal', 'back below 97 is normal')
assert(h.diskLevel('normal', 88) === 'normal', 'stays alerting down to 88')
assert(h.diskLevel('normal', 87) === 'ok', 'clears below 88')
const disk = h.diskProblems(rows, {})
assert(disk.problems.length === 1 && disk.problems[0].key === 'disk:/' && disk.levels['/'] === 'normal', 'disk problem keyed by mount')

// --- reboot
assert(h.rebootProblem(true, '7.2.5').length === 0, 'modules present: no reboot')
assert(h.rebootProblem(false, '7.2.5')[0].key === 'reboot', 'modules missing: reboot needed')

// --- docker
const ev = (action, name, code, t) => JSON.stringify({ Type: 'container', Action: action, time: t, Actor: { Attributes: { name: name, image: 'postgres:16', exitCode: String(code) } } })
const die = h.parseDockerEvent(ev('die', 'pg', 1, 100))
assert(die.action === 'die' && die.name === 'pg' && die.exitCode === 1 && die.time === 100000, 'docker die event parsed')
assert(h.parseDockerEvent('not json') === null, 'bad docker line ignored')
let hist = h.recordDockerEvent({}, die, 100000)
assert(h.containerProblems(hist, 100000)[0].loop === false, 'single non-zero exit is a normal problem')
hist = h.recordDockerEvent(hist, h.parseDockerEvent(ev('start', 'pg', 0, 101)), 101000)
assert(h.containerProblems(hist, 101000).length === 0, 'start clears a single exit')
hist = h.recordDockerEvent(hist, h.parseDockerEvent(ev('die', 'pg', 1, 150)), 150000)
hist = h.recordDockerEvent(hist, h.parseDockerEvent(ev('start', 'pg', 0, 151)), 151000)
hist = h.recordDockerEvent(hist, h.parseDockerEvent(ev('die', 'pg', 1, 200)), 200000)
hist = h.recordDockerEvent(hist, h.parseDockerEvent(ev('start', 'pg', 0, 201)), 201000)
let loop = h.containerProblems(hist, 201000)
assert(loop.length === 1 && loop[0].loop === true && loop[0].exits === 3, 'three exits in 5 minutes is a restart loop, even while running')
assert(h.containerProblems(hist, 100000 + 300001 + 100000).length === 0, 'loop clears when the window drains and it is running')
assert(h.containerProblems(h.recordDockerEvent({}, h.parseDockerEvent(ev('die', 'ok', 0, 5)), 5000), 5000).length === 0, 'clean exit is not a problem')
hist = h.recordDockerEvent(hist, h.parseDockerEvent(ev('destroy', 'pg', 0, 202)), 202000)
assert(h.containerProblems(hist, 202000).length === 0, 'destroy forgets the container')

// --- copy
assert(h.humanBytes(92042832896) === '86 GB' && h.humanBytes(472489984) === '451 MB' && h.humanBytes(1536) === '1.5 KB', 'human bytes')
const unitItem = h.itemFor(units[0])
assert(unitItem.summary === 'nginx.service failed' && unitItem.body === 'User service' && unitItem.urgency === 2, 'unit copy')
assert(unitItem.execArgv.join(' ') === 'xdg-terminal-exec journalctl --user -u nginx.service -e', 'unit action')
const diskItem = h.itemFor(disk.problems[0])
assert(diskItem.summary === '/ is 91% full' && diskItem.body === '86 GB free of 952 GB' && diskItem.urgency === 1, 'disk copy')
assert(h.itemFor(h.rebootProblem(false, '7.2.5')[0]).body === 'Running 7.2.5; its modules were removed', 'reboot copy')
assert(loop[0] && h.itemFor(loop[0]).summary === 'Container pg keeps restarting' && h.itemFor(loop[0]).urgency === 2, 'loop copy')

// --- reconcile (Review Focus 1-3)
const P = key => ({ key: key, check: h.checkOf(key) })
let r = h.reconcile([P('disk:/')], ['disk', 'unit'], [], [], [])
assert(r.upsert.length === 1 && r.resolve.length === 0 && r.expected.join() === 'disk:/', 'new problem is upserted')
r = h.reconcile([], ['disk'], ['disk:/'], ['disk:/'], [])
assert(r.resolve.join() === 'disk:/' && r.expected.length === 0, 'cleared problem resolves')
r = h.reconcile([], ['unit'], ['disk:/'], ['disk:/'], [])
assert(r.resolve.length === 0 && r.expected.join() === 'disk:/', 'unknown check never resolves its items')
r = h.reconcile([P('disk:/')], ['disk'], ['disk:/'], [], [])
assert(r.muted.join() === 'disk:/' && r.upsert.length === 0, 'item removed by the user while open becomes muted')
r = h.reconcile([P('disk:/')], ['disk'], [], [], ['disk:/'])
assert(r.upsert.length === 0 && r.muted.join() === 'disk:/', 'muted problem stays hidden')
r = h.reconcile([], ['disk'], [], [], ['disk:/'])
assert(r.muted.length === 0, 'mute lifts when the problem clears')
r = h.reconcile([], ['disk', 'unit', 'reboot', 'container'], [], ['unit:system:gone.service'], [])
assert(r.resolve.join() === 'unit:system:gone.service', 'restart: stale items resolve on first known check')
r = h.reconcile([P('reboot')], ['reboot'], [], ['reboot'], [])
assert(r.upsert.length === 1 && r.muted.length === 0, 'restart: present item is reused, not muted')

// --- mute file
assert(h.parseMuteFile('{"version":1,"muted":["disk:/"]}').join() === 'disk:/', 'mute file parsed')
assert(h.parseMuteFile('{broken').length === 0, 'corrupt mute file is empty')
assert(JSON.parse(h.serializeMuteFile(['b', 'a'])).muted.join() === 'a,b', 'mute file sorted')

// --- review fixes: container state survives restarts and stream gaps
const ps = [
  JSON.stringify({ Names: 'pg', Image: 'postgres:16', State: 'exited', Status: 'Exited (1) 3 minutes ago' }),
  JSON.stringify({ Names: 'web', Image: 'nginx', State: 'running', Status: 'Up 2 hours' }),
  JSON.stringify({ Names: 'job', Image: 'alpine', State: 'exited', Status: 'Exited (0) 1 hour ago' })
].join('\n')
const seen = h.parseDockerPs(ps)
assert(seen.length === 3 && seen[0].exitCode === 1 && seen[1].running === true && seen[2].exitCode === 0, 'docker ps parsed')
assert(h.parseDockerPs('') !== null && h.parseDockerPs('').length === 0, 'no containers is a known empty list')
let seeded = h.seedDockerHistory({}, seen, 1000)
let seededProblems = h.containerProblems(seeded, 1000)
assert(seededProblems.length === 1 && seededProblems[0].key === 'container:pg' && seededProblems[0].exitCode === 1, 'restart: a stopped failed container keeps its problem')
const loopHist = { web: { image: 'nginx', exits: [900, 950, 990], last: 'die', lastExit: 1 } }
seeded = h.seedDockerHistory(loopHist, seen, 1000)
assert(h.containerProblems(seeded, 1000).some(p => p.key === 'container:web' && p.loop), 'reconnect keeps exits counted before the gap')
seeded = h.seedDockerHistory({ gone: { image: 'x', exits: [], last: 'die', lastExit: 2 } }, seen, 1000)
assert(!seeded.gone, 'containers removed during the gap are forgotten')
seeded = h.seedDockerHistory({ pg: { image: 'postgres:16', exits: [], last: 'die', lastExit: 143 } }, [{ name: 'pg', image: 'postgres:16', running: true, exitCode: 0 }], 1000)
assert(h.containerProblems(seeded, 1000).length === 0, 'a container that came back during the gap clears')

// --- review fixes: pseudo and read-only filesystems never alert
const dfPseudo = [
  'Filesystem Mounted on Type 1B-blocks Used Avail Use%',
  '/dev/sda1 / ext4 1000 500 500 50%',
  'MyApp /tmp/.mount_MyApp fuse.MyApp 100 100 0 100%',
  '/dev/loop0 /mnt/iso iso9660 700 700 0 100%',
  '/dev/sdb1 /run/media/tim/NTFS fuseblk 1000 950 50 95%'
].join('\n')
const pseudoRows = h.parseDf(dfPseudo)
assert(pseudoRows.map(r => r.target).join() === '/,/run/media/tim/NTFS', 'fuse.* and iso9660 skipped, fuseblk kept')

console.log('health logic contract passed')
NODE

# Every check command is bounded: a hung df/systemctl/docker must become
# "unknown", not freeze the check (review Important #4).
health_qml="$repo_root/plugins/araneadev.notifications/Health.qml"
for cmd in '"systemctl", "list-units"' '"systemctl", "--user"' '"df"' '"docker", "info"' '"docker", "ps"'; do
  grep -F "command: [\"timeout\", \"10\", $cmd" "$health_qml" >/dev/null || { echo "unbounded check command: $cmd" >&2; exit 1; }
done
grep -Fq '"-l"' "$health_qml"
grep -Fq '"--since"' "$health_qml"

echo "health contract passed"
