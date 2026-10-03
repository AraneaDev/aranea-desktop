// Logic contract for the health modules (moved from tests/health.test.sh).
// Run with `node --test tests/js/` (tools/check runs it with coverage).
const { test } = require("node:test")
const { loadPragma } = require("./lib/load-pragma.js")

const h = loadPragma("plugins/araneadev.health/HealthLogic.js")
const presentation = loadPragma("plugins/araneadev.health/HealthPresentation.js")

test("health presentation owns byte formatting", () => {
  if (presentation.humanBytes(1536) !== "1.5 KB") throw new Error("byte formatting")
})

const assert = (cond, msg) => {
  if (!cond) throw new Error(msg)
}
const eq = (a, b, msg) => {
  if (a !== b) throw new Error(`${msg}: got ${JSON.stringify(a)}`)
}
const deepEq = (a, b, msg) => {
  if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${msg}: got ${JSON.stringify(a)}`)
}

test("parseFailedUnits keys failed units by scope", () => {
  assert(h.parseFailedUnits("[]", "system").length === 0, "empty failed list")
  const units = h.parseFailedUnits(
    '[{"unit":"nginx.service","load":"loaded","active":"failed","sub":"failed","description":"nginx"}]',
    "user"
  )
  assert(
    units.length === 1 && units[0].key === "unit:user:nginx.service",
    "failed unit keyed by scope"
  )
  assert(h.parseFailedUnits("garbage", "system") === null, "unparsable output is unknown")
})

test("parseDf collapses btrfs subvolumes to one row per source", () => {
  // fixture captured on this machine: btrfs subvolumes share a source
  const df = [
    "Filesystem                  Mounted on            Type      1B-blocks        Used        Avail Use%",
    "/dev/mapper/root            /                     btrfs 1022042832896 930000000000 92042832896  91%",
    "/dev/mapper/root            /home                 btrfs 1022042832896 930000000000 92042832896  91%",
    "/dev/mapper/root            /var/cache/pacman/pkg btrfs 1022042832896 930000000000 92042832896  91%",
    "/dev/nvme0n1p1              /boot                 vfat     2143281152  1670791168   472489984  78%"
  ].join("\n")
  const rows = h.parseDf(df)
  assert(rows.length === 2, "btrfs subvolumes collapse to one row per source")
  assert(rows[0].target === "/" && rows[0].percent === 91, "shortest mount point wins")
  assert(h.parseDf("") === null, "empty df output is unknown")
})

test("diskLevel applies thresholds with hysteresis", () => {
  assert(h.diskLevel("ok", 89) === "ok", "below 90 is fine")
  assert(h.diskLevel("ok", 90) === "normal", "90 alerts")
  assert(h.diskLevel("normal", 97) === "critical", "97 is critical")
  assert(h.diskLevel("critical", 95) === "normal", "back below 97 is normal")
  assert(h.diskLevel("normal", 88) === "normal", "stays alerting down to 88")
  assert(h.diskLevel("normal", 87) === "ok", "clears below 88")
})

test("diskProblems keys a problem by mount point", () => {
  const df = [
    "Filesystem                  Mounted on            Type      1B-blocks        Used        Avail Use%",
    "/dev/mapper/root            /                     btrfs 1022042832896 930000000000 92042832896  91%",
    "/dev/nvme0n1p1              /boot                 vfat     2143281152  1670791168   472489984  78%"
  ].join("\n")
  const rows = h.parseDf(df)
  const disk = h.diskProblems(rows, {})
  assert(
    disk.problems.length === 1 &&
      disk.problems[0].key === "disk:/" &&
      disk.levels["/"] === "normal",
    "disk problem keyed by mount"
  )
})

test("rebootProblem fires only when kernel modules are missing", () => {
  assert(h.rebootProblem(true, "7.2.5").length === 0, "modules present: no reboot")
  assert(h.rebootProblem(false, "7.2.5")[0].key === "reboot", "modules missing: reboot needed")
})

test("docker events feed restart-loop detection", () => {
  const ev = (action, name, code, t) =>
    JSON.stringify({
      Type: "container",
      Action: action,
      time: t,
      Actor: { Attributes: { name: name, image: "postgres:16", exitCode: String(code) } }
    })
  const die = h.parseDockerEvent(ev("die", "pg", 1, 100))
  assert(
    die.action === "die" && die.name === "pg" && die.exitCode === 1 && die.time === 100000,
    "docker die event parsed"
  )
  assert(h.parseDockerEvent("not json") === null, "bad docker line ignored")
  let hist = h.recordDockerEvent({}, die, 100000)
  assert(
    h.containerProblems(hist, 100000)[0].loop === false,
    "single non-zero exit is a normal problem"
  )
  hist = h.recordDockerEvent(hist, h.parseDockerEvent(ev("start", "pg", 0, 101)), 101000)
  assert(h.containerProblems(hist, 101000).length === 0, "start clears a single exit")
  hist = h.recordDockerEvent(hist, h.parseDockerEvent(ev("die", "pg", 1, 150)), 150000)
  hist = h.recordDockerEvent(hist, h.parseDockerEvent(ev("start", "pg", 0, 151)), 151000)
  hist = h.recordDockerEvent(hist, h.parseDockerEvent(ev("die", "pg", 1, 200)), 200000)
  hist = h.recordDockerEvent(hist, h.parseDockerEvent(ev("start", "pg", 0, 201)), 201000)
  let loop = h.containerProblems(hist, 201000)
  assert(
    loop.length === 1 && loop[0].loop === true && loop[0].exits === 3,
    "three exits in 5 minutes is a restart loop, even while running"
  )
  assert(
    h.containerProblems(hist, 100000 + 300001 + 100000).length === 0,
    "loop clears when the window drains and it is running"
  )
  assert(
    h.containerProblems(
      h.recordDockerEvent({}, h.parseDockerEvent(ev("die", "ok", 0, 5)), 5000),
      5000
    ).length === 0,
    "clean exit is not a problem"
  )
  hist = h.recordDockerEvent(hist, h.parseDockerEvent(ev("destroy", "pg", 0, 202)), 202000)
  assert(h.containerProblems(hist, 202000).length === 0, "destroy forgets the container")
})

test("itemFor builds notification copy for units, disk, reboot and loops", () => {
  const units = h.parseFailedUnits(
    '[{"unit":"nginx.service","load":"loaded","active":"failed","sub":"failed","description":"nginx"}]',
    "user"
  )
  const df = [
    "Filesystem                  Mounted on            Type      1B-blocks        Used        Avail Use%",
    "/dev/mapper/root            /                     btrfs 1022042832896 930000000000 92042832896  91%",
    "/dev/nvme0n1p1              /boot                 vfat     2143281152  1670791168   472489984  78%"
  ].join("\n")
  const disk = h.diskProblems(h.parseDf(df), {})
  const ev = (action, name, code, t) =>
    JSON.stringify({
      Type: "container",
      Action: action,
      time: t,
      Actor: { Attributes: { name: name, image: "postgres:16", exitCode: String(code) } }
    })
  let hist = h.recordDockerEvent({}, h.parseDockerEvent(ev("die", "pg", 1, 100)), 100000)
  hist = h.recordDockerEvent(hist, h.parseDockerEvent(ev("start", "pg", 0, 101)), 101000)
  hist = h.recordDockerEvent(hist, h.parseDockerEvent(ev("die", "pg", 1, 150)), 150000)
  hist = h.recordDockerEvent(hist, h.parseDockerEvent(ev("start", "pg", 0, 151)), 151000)
  hist = h.recordDockerEvent(hist, h.parseDockerEvent(ev("die", "pg", 1, 200)), 200000)
  hist = h.recordDockerEvent(hist, h.parseDockerEvent(ev("start", "pg", 0, 201)), 201000)
  const loop = h.containerProblems(hist, 201000)

  assert(
    h.humanBytes(92042832896) === "86 GB" &&
      h.humanBytes(472489984) === "451 MB" &&
      h.humanBytes(1536) === "1.5 KB",
    "human bytes"
  )
  const unitItem = h.itemFor(units[0])
  assert(
    unitItem.summary === "nginx.service failed" &&
      unitItem.body === "User service" &&
      unitItem.urgency === 2,
    "unit copy"
  )
  assert(
    unitItem.execArgv.join(" ") === "xdg-terminal-exec journalctl --user -u nginx.service -e",
    "unit action"
  )
  const diskItem = h.itemFor(disk.problems[0])
  assert(
    diskItem.summary === "/ is 91% full" &&
      diskItem.body === "86 GB free of 952 GB" &&
      diskItem.urgency === 1,
    "disk copy"
  )
  assert(
    h.itemFor(h.rebootProblem(false, "7.2.5")[0]).body ===
      "Running 7.2.5; its modules were removed",
    "reboot copy"
  )
  assert(
    loop[0] &&
      h.itemFor(loop[0]).summary === "Container pg keeps restarting" &&
      h.itemFor(loop[0]).urgency === 2,
    "loop copy"
  )
})

test("health lives only in the dropdown: no center items, no mutes (Revision 1)", () => {
  for (const gone of ["reconcile", "parseMuteFile", "serializeMuteFile", "seedDiskLevels"]) {
    assert(
      typeof h[gone] === "undefined",
      gone + " must be gone: health no longer posts to the center"
    )
  }
})

test("container state survives restarts and stream gaps (review fixes)", () => {
  const ps = [
    JSON.stringify({
      Names: "pg",
      Image: "postgres:16",
      State: "exited",
      Status: "Exited (1) 3 minutes ago"
    }),
    JSON.stringify({ Names: "web", Image: "nginx", State: "running", Status: "Up 2 hours" }),
    JSON.stringify({
      Names: "job",
      Image: "alpine",
      State: "exited",
      Status: "Exited (0) 1 hour ago"
    })
  ].join("\n")
  const seen = h.parseDockerPs(ps)
  assert(
    seen.length === 3 &&
      seen[0].exitCode === 1 &&
      seen[1].running === true &&
      seen[2].exitCode === 0,
    "docker ps parsed"
  )
  assert(
    h.parseDockerPs("") !== null && h.parseDockerPs("").length === 0,
    "no containers is a known empty list"
  )
  let seeded = h.seedDockerHistory({}, seen, 1000)
  let seededProblems = h.containerProblems(seeded, 1000)
  assert(
    seededProblems.length === 1 &&
      seededProblems[0].key === "container:pg" &&
      seededProblems[0].exitCode === 1,
    "restart: a stopped failed container keeps its problem"
  )
  const loopHist = { web: { image: "nginx", exits: [900, 950, 990], last: "die", lastExit: 1 } }
  seeded = h.seedDockerHistory(loopHist, seen, 1000)
  assert(
    h.containerProblems(seeded, 1000).some((p) => p.key === "container:web" && p.loop),
    "reconnect keeps exits counted before the gap"
  )
  seeded = h.seedDockerHistory(
    { gone: { image: "x", exits: [], last: "die", lastExit: 2 } },
    seen,
    1000
  )
  assert(!seeded.gone, "containers removed during the gap are forgotten")
  seeded = h.seedDockerHistory(
    { pg: { image: "postgres:16", exits: [], last: "die", lastExit: 143 } },
    [{ name: "pg", image: "postgres:16", running: true, exitCode: 0 }],
    1000
  )
  assert(
    h.containerProblems(seeded, 1000).length === 0,
    "a container that came back during the gap clears"
  )
})

test("pseudo and read-only filesystems never alert (review fixes)", () => {
  const dfPseudo = [
    "Filesystem Mounted on Type 1B-blocks Used Avail Use%",
    "/dev/sda1 / ext4 1000 500 500 50%",
    "MyApp /tmp/.mount_MyApp fuse.MyApp 100 100 0 100%",
    "/dev/loop0 /mnt/iso iso9660 700 700 0 100%",
    "/dev/sdb1 /run/media/tim/NTFS fuseblk 1000 950 50 95%"
  ].join("\n")
  const pseudoRows = h.parseDf(dfPseudo)
  assert(
    pseudoRows.map((r) => r.target).join() === "/,/run/media/tim/NTFS",
    "fuse.* and iso9660 skipped, fuseblk kept"
  )
})

test("mount points with spaces are parsed from the numeric columns at the end (minor fixes)", () => {
  const dfSpaces = [
    "Filesystem Mounted on Type 1B-blocks Used Avail Use%",
    "/dev/sdc1 /run/media/tim/My Drive ext4 1000 950 50 95%"
  ].join("\n")
  const spaced = h.parseDf(dfSpaces)
  assert(
    spaced.length === 1 &&
      spaced[0].target === "/run/media/tim/My Drive" &&
      spaced[0].percent === 95,
    "mount point with spaces is monitored"
  )
})

test("pruneDockerHistory keeps only problems and recent exits (minor fixes)", () => {
  const stale = {
    old: { image: "a", exits: [], last: "die", lastExit: 0 },
    up: { image: "b", exits: [], last: "start", lastExit: 0 },
    bad: { image: "c", exits: [], last: "die", lastExit: 1 },
    busy: { image: "d", exits: [990], last: "start", lastExit: 0 }
  }
  const pruned = h.pruneDockerHistory(stale, 1000)
  assert(
    Object.keys(pruned).sort().join() === "bad,busy",
    "history keeps only problems and recent exits"
  )
})

test("actions that need a terminal are left out when xdg-terminal-exec is missing (minor fixes)", () => {
  const noTerm = h.itemFor(
    { key: "unit:system:a.service", check: "unit", unit: "a.service", scope: "system" },
    { terminal: false }
  )
  assert(noTerm.execArgv.length === 0, "no terminal: no journal action")
  assert(
    h.itemFor({ key: "unit:system:a.service", check: "unit", unit: "a.service", scope: "system" })
      .execArgv[0] === "xdg-terminal-exec",
    "terminal assumed by default"
  )
})

test("statusFor and annotateProblems produce dropdown status and rows", () => {
  const unitP = { key: "unit:system:a.service", check: "unit", unit: "a.service", scope: "system" }
  const diskP = {
    key: "disk:/",
    check: "disk",
    target: "/",
    percent: 92,
    size: 100,
    avail: 8,
    level: "normal"
  }
  assert(h.statusFor([]) === "healthy", "no problems is healthy")
  assert(h.statusFor([diskP]) === "attention", "a normal problem is attention")
  assert(h.statusFor([diskP, unitP]) === "critical", "a critical problem is critical")
  const rowsA = h.annotateProblems([diskP, unitP], { terminal: true })
  assert(
    rowsA[0].key === "unit:system:a.service" &&
      rowsA[0].urgency === 2 &&
      rowsA[0].muted === undefined,
    "critical rows first, no mute state"
  )
  assert(rowsA[1].key === "disk:/" && rowsA[1].summary === "/ is 92% full", "row copy")
})

test("health cursor by key (4c)", () => {
  const rows = [{ key: "disk:/" }, { key: "unit:user:x" }, { key: "container:db" }]
  eq(h.indexOfKey(rows, "unit:user:x"), 1, "index")
  eq(h.indexOfKey(rows, "gone"), -1, "missing")
  eq(h.moveCursorKey(rows, "", 1), "disk:/", "first")
  eq(h.moveCursorKey(rows, "", -1), "container:db", "last")
  eq(h.moveCursorKey(rows, "container:db", 1), "disk:/", "wraps")
  eq(h.moveCursorKey(rows, "gone", 1), "disk:/", "stale key restarts")
  eq(h.moveCursorKey([], "x", 1), "", "no rows")
  const resorted = [{ key: "reboot" }].concat(rows)
  eq(h.indexOfKey(resorted, "unit:user:x"), 2, "follows its row")
})

test("docker stops, OOM and failed ps (4c)", () => {
  const now = 10000000
  const ps = (status) =>
    h.parseDockerPs(JSON.stringify({ Names: "db", Image: "pg", State: "exited", Status: status }))
  const problems = (hist) => h.containerProblems(hist, now).map((p) => p.key)
  deepEq(
    problems(h.seedDockerHistory({}, ps("Exited (143) 1 minute ago"), now)),
    [],
    "SIGTERM stop is clean"
  )
  deepEq(
    problems(h.seedDockerHistory({}, ps("Exited (137) 1 minute ago"), now)),
    [],
    "SIGKILL stop is clean"
  )
  deepEq(
    problems(h.seedDockerHistory({}, ps("Exited (1) 1 minute ago"), now)),
    ["container:db"],
    "real failure"
  )
  const ev = (action, exitCode) =>
    h.parseDockerEvent(
      JSON.stringify({
        Action: action,
        time: now / 1000,
        Actor: { Attributes: { name: "db", image: "pg", exitCode: String(exitCode || 0) } }
      })
    )
  deepEq(ev("oom").action, "oom", "oom events are parsed")
  let hist = h.recordDockerEvent({}, ev("start"), now)
  hist = h.recordDockerEvent(hist, ev("oom"), now)
  hist = h.recordDockerEvent(hist, ev("die", 137), now)
  deepEq(problems(hist), ["container:db"], "OOM kill is flagged")
  deepEq(h.pruneDockerHistory(hist, now).db !== undefined, true, "OOM kill kept by pruning")
  hist = h.recordDockerEvent(hist, ev("start"), now)
  deepEq(hist.db.oomKilled, false, "start clears the OOM mark")
  let stops = h.recordDockerEvent({}, ev("die", 143), now)
  stops = h.recordDockerEvent(stops, ev("start"), now)
  stops = h.recordDockerEvent(stops, ev("die", 143), now)
  stops = h.recordDockerEvent(stops, ev("start"), now)
  stops = h.recordDockerEvent(stops, ev("die", 143), now)
  deepEq(stops.db.exits.length, 0, "clean stops never count toward a restart loop")
  deepEq(h.isFailedExit({ lastExit: 143 }), false, "143")
  deepEq(h.isFailedExit({ lastExit: 137, oomKilled: true }), true, "137 with OOM")
  deepEq(h.isFailedExit({ lastExit: 2 }), true, "2")
})

test("disk level from a known previous level (4c)", () => {
  if (h.diskLevel("ok", 89) !== "ok") throw new Error("89% from ok stays ok")
  if (h.diskLevel("normal", 89) !== "normal") throw new Error("hysteresis")
})

test("problem rows are keyed by id, falling back to their text", () => {
  // The source module and the facade copy HealthLogic.js carries.
  for (const m of [presentation, h]) {
    eq(m.problemKey({ key: "disk:/", summary: "/ is 92% full" }), "disk:/", "id first")
    eq(m.problemKey({ key: "", summary: "Reboot" }), "Reboot", "empty id falls back")
    eq(m.problemKey({ summary: "Reboot" }), "Reboot", "missing id falls back")
    eq(m.problemKey({ key: 7, summary: 3 }), "", "non-string fields give no key")
    eq(m.problemKey(null), "", "no row, no key")
    eq(m.problemKeys([{ key: "a" }, { summary: "b" }, null]), "a\nb\n", "keys joined")
    eq(m.problemKeys(undefined), "", "no rows")
    const rows = [{ key: "disk:/" }, { summary: "Reboot" }]
    eq(h.indexOfKey(rows, "Reboot"), 1, "the cursor finds a text-keyed row")
    eq(h.indexOfKey(rows, ""), -1, "an empty key finds nothing")
    eq(h.moveCursorKey(rows, "disk:/", 1), "Reboot", "and moves onto it")
  }
})

test("a keyed problem action only lands on the row it names", () => {
  // The source module and the facade copy HealthLogic.js carries.
  for (const m of [presentation, h]) {
    const rows = [{ key: "disk:/" }, { key: "reboot" }]
    eq(m.keyedProblem(rows, 1, "reboot"), rows[1], "a matching row")
    eq(m.keyedProblem(rows, 0, "reboot"), null, "a re-sorted row is refused")
    eq(m.keyedProblem(rows, 5, "reboot"), null, "out of range")
    eq(m.keyedProblem(rows, 0, ""), null, "an empty key")
    eq(m.keyedProblem(rows, 0, 3), null, "a non-string key")
    eq(m.keyedProblem(undefined, 0, "disk:/"), null, "no rows")
  }
})

test("strand bar fractions", () => {
  // The source module and the facade copy HealthLogic.js carries.
  for (const m of [presentation, h]) {
    eq(m.barFraction(58), 0.58, "a percentage")
    eq(m.barFraction(-4), 0, "clamped low")
    eq(m.barFraction(140), 1, "clamped high")
    eq(m.barFraction(NaN), 0, "NaN is empty")
    eq(m.barFraction("x"), 0, "text is empty")
  }
})

test("the CPU trace's samples", () => {
  // The source module and the facade copy HealthLogic.js carries.
  for (const m of [presentation, h]) {
    deepEq(
      m.cpuSamples([12, 140, -3, "x"]),
      [
        { rx: 12, tx: 0 },
        { rx: 100, tx: 0 },
        { rx: 0, tx: 0 },
        { rx: 0, tx: 0 }
      ],
      "percentages clamped into LinkGraph samples"
    )
    deepEq(m.cpuSamples(null), [], "no history")
  }
})

test("problem glyphs are the Nerd Font code points", () => {
  const glyphs = ["unit", "disk", "reboot", "container"].map(
    (check) =>
      h.itemFor({ check, unit: "a", scope: "system", target: "/", name: "c", release: "" }).glyph
  )
  deepEq(
    glyphs.map((g) => g.codePointAt(0)),
    [0xf0493, 0xf02ca, 0xf0709, 0xf0868],
    "unit, disk, reboot, container"
  )
})

test("the keyboard cursor: the first key only reveals", () => {
  const rows = [{ key: "disk:/" }, { key: "reboot" }, { summary: "Container web exited" }]
  deepEq(h.cursorMove(rows, "", false, 1), { key: "disk:/", keyboard: true }, "reveal on first")
  deepEq(
    h.cursorMove(rows, "", false, -1),
    { key: "Container web exited", keyboard: true },
    "reveal on last going up"
  )
  deepEq(
    h.cursorMove(rows, "reboot", false, 1),
    { key: "reboot", keyboard: true },
    "reveal where the pointer left it"
  )
  deepEq(h.cursorMove(rows, "gone", false, 1), { key: "disk:/", keyboard: true }, "a lost key")
  deepEq(
    h.cursorMove(rows, "reboot", true, 1),
    { key: "Container web exited", keyboard: true },
    "then moves"
  )
  deepEq(h.cursorMove(rows, "reboot", true, 0), { key: "reboot", keyboard: true }, "no dy")
  deepEq(h.cursorMove([], "", false, 1), { key: "", keyboard: false }, "no rows")
  deepEq(h.cursorMove(null, "", false, 1), { key: "", keyboard: false }, "null rows")
})

test("Enter reveals before it opens, and only a keyed row", () => {
  const rows = [{ key: "disk:/" }, { key: "reboot" }]
  deepEq(h.cursorPress(rows, "", false), { keyboard: false, row: null }, "no cursor: nothing")
  deepEq(h.cursorPress(rows, "gone", true), { keyboard: true, row: null }, "a lost key: nothing")
  deepEq(h.cursorPress(rows, "reboot", false), { keyboard: true, row: null }, "hover: reveal")
  eq(h.cursorPress(rows, "reboot", true).row, rows[1], "keyboard: open")
  eq(h.outlineIndex(rows, "reboot", true), 1, "the outline follows the keyboard")
  eq(h.outlineIndex(rows, "reboot", false), -1, "never the pointer")
})
