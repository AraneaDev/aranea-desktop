// The Ready for review card: what it shows, what each press sends, and what never runs by itself.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.projects" as Projects
import "plugins/araneadev.projects/ProjectProblems.js" as Problems

ShellRoot {
  id: host
  // Fixture merge base, 40 hex characters.
  readonly property string mergeBase: '0123456789abcdef0123456789abcdef01234567'
  // Fixture branch head.
  readonly property string head: 'b'.repeat(40)
  // Fixture head after the agent commits again.
  readonly property string newHead: 'c'.repeat(40)
  // Fixture folder of the task checkout.
  readonly property string checkoutPath: '/home/u/Work/myapp-worktrees/feat-x'
  // Held helper calls: review reads, Git commands, registry mutations, launcher and action runs.
  property var reviewCalls: []
  // Held Git commands.
  property var gitCalls: []
  // Held registry changes.
  property var mutations: []
  // Held launcher requests.
  property var launches: []
  // Runs the action client tried to start.
  property var actionCalls: []
  // The same runs with their stdin and completion.
  property var actionRequests: []
  // Review data the next answered read returns.
  property var reviewHead: host.head
  // Whether the fixture checkout has uncommitted changes.
  property bool dirty: false
  // Call counts recorded before capture.
  property var entryCounts: []
  // Commits the fixture review lists.
  property int commitCount: 2
  // Adds five more changed files, the last one binary.
  property bool manyFiles: false
  QmlTest {
    id: t
  }
  Projects.ProjectsPresentation {
    id: entry
    windowEnabled: false
  }
  FloatingWindow {
    visible: true
    width: 900
    height: 900
    Projects.ProjectsSurface {
      id: surface
      anchors.fill: parent
      root: entry
    }
  }
  // Project with a primary and one task checkout; `mark` is the saved review mark, if any.
  function project(mark) {
    return {
      id: 'p-a',
      name: 'p-a',
      tools: {
        terminalId: 'kitty'
      },
      profiles: [
        {
          id: 'pr',
          name: 'Code',
          roles: ['editor'],
          tools: {
            editorId: 'code'
          },
          revision: 1
        }
      ],
      lastProfileId: 'pr',
      lastCheckoutId: 'c-l',
      checkouts: [
        {
          id: 'c-p',
          path: '/home/u/Work/myapp',
          branch: 'main',
          primary: true
        },
        {
          id: 'c-l',
          path: host.checkoutPath,
          branch: 'feat/x',
          primary: false,
          review: mark || undefined
        }
      ]
    }
  }
  // Registry state with the project and an optional saved review mark.
  function state(revision, mark) {
    return {
      revision: revision,
      projects: [host.project(mark)],
      roots: [],
      ignored: []
    }
  }
  // An agent task on the task checkout.
  function task(reportedState, at, verification, result, description) {
    return {
      result: result || '',
      description: description || '',
      id: 't1',
      taskId: 't1',
      reportedState: reportedState,
      lastReceivedAt: at,
      verification: {
        status: verification || 'reported-pass'
      },
      association: {
        status: 'registered',
        projectId: 'p-a',
        checkoutId: 'c-l'
      }
    }
  }
  // Publish agent tasks.
  function setTasks(list) {
    entry.activityClient.snapshot = {
      tasks: list,
      operations: []
    }
  }
  // Helper data for the fixture checkout.
  function reviewData() {
    var data = {
      projectId: 'p-a',
      checkoutId: 'c-l',
      branch: 'feat/x',
      base: 'origin/main',
      mergeBase: host.mergeBase,
      head: host.reviewHead,
      ahead: 2,
      behind: 0,
      commits: Array.apply(null, Array(host.commitCount)).map(function (x, i) {
        return {
          sha: String(i).repeat(40).slice(0, 40),
          subject: 'Change ' + i
        }
      }),
      files: [
        {
          path: 'a.js',
          added: 1,
          removed: 0
        },
        {
          path: 'b.js',
          added: 2,
          removed: 1
        },
        {
          path: 'c.js',
          added: 3,
          removed: 3
        }
      ],
      uncommitted: {
        dirty: host.dirty,
        untracked: false
      },
      truncated: false
    }
    if (host.manyFiles)
      data.files = data.files.concat([
        {
          path: 'd.js',
          added: 4,
          removed: 0
        },
        {
          path: 'e.js',
          added: 5,
          removed: 0
        },
        {
          path: 'f.js',
          added: 6,
          removed: 0
        },
        {
          path: 'g.js',
          added: 7,
          removed: 0
        },
        {
          path: 'img.png',
          added: null,
          removed: null
        }
      ])
    return data
  }
  // Answer every held review read with data or an error.
  function answerReviews(error) {
    for (var i = 0; i < host.reviewCalls.length; i++) {
      var call = host.reviewCalls[i]
      if (call.answered)
        continue
      call.answered = true
      call.done(error ? 1 : 0, JSON.stringify(error ? {
        ok: false,
        data: null,
        error: error
      } : {
        ok: true,
        data: host.reviewData(),
        error: null
      }), '')
    }
  }
  // The review card.
  function card() {
    return t.findChild(surface, 'projectReviewCard')
  }
  // Text of one card item, or null.
  function text(name) {
    var item = t.findChild(card(), name)
    return item ? item.text : null
  }
  // One card button.
  function button(name) {
    return t.findChild(card(), name)
  }
  Component.onCompleted: t.step(80, function () {
    entry.projectController.runner = function (argv, input, done) {
      if (argv[1] === 'snapshot') {
        Qt.callLater(function () {
          done(0, JSON.stringify({
            ok: true,
            state: entry.projectController.state
          }), '')
        })
        return
      }
      if (JSON.parse(input).action === 'navigation-set') {
        Qt.callLater(function () {
          done(0, JSON.stringify({
            ok: true,
            state: entry.projectController.state
          }), '')
        })
        return
      }
      host.mutations.push({
        argv: argv,
        input: input,
        done: done
      })
    }
    entry.gitClient.runner = function (argv, done) {
      Qt.callLater(function () {
        done(0, JSON.stringify({
          ok: true,
          error: null,
          data: {
            projectId: argv[2],
            checkoutId: argv[4],
            path: '/fixture',
            observedAt: Date.now(),
            branch: 'feat/x',
            detached: false,
            upstream: null,
            ahead: 2,
            behind: 0,
            counts: {},
            files: [],
            truncated: false
          }
        }), '')
      })
    }
    entry.gitCommands.runner = function (argv, done) {
      host.gitCalls.push({
        argv: argv,
        done: done
      })
    }
    entry.reviewClient.runner = function (argv, done) {
      host.reviewCalls.push({
        argv: argv,
        done: done,
        answered: false
      })
    }
    entry.reviewClient.launcherRunner = function (argv, input, done) {
      host.launches.push({
        argv: argv,
        input: input,
        done: done
      })
    }
    entry.projectClient.runner = function () {}
    entry.activityClient.runner = function () {}
    entry.actionClient.runner = function (argv, input, done) {
      host.actionCalls.push(argv)
      host.actionRequests.push({
        argv: argv,
        input: input,
        done: done
      })
    }
    entry.actionClient.snapshot = {
      definitions: [
        {
          id: 'a-t',
          projectId: 'p-a',
          name: 'Run tests',
          argv: ['npm', 'test'],
          kind: 'command',
          revision: 1
        }
      ],
      runs: []
    }
    entry.actionClient.available = true
    entry.actionClient.availability = {
      execution: true
    }
    entry.projectClient.available = true
    entry.projectClient.snapshot = {
      availability: {
        compositor: true
      }
    }
    entry.projectController.tools = {
      defaults: {},
      editors: [],
      terminals: [],
      agents: []
    }
    entry.opened = true
    entry.view = surface
    entry.captureActive = false
    host.setTasks([host.task('ready-for-review', 100)])
    entry.projectController.state = host.state(1)
    entry.projectId = 'p-a'
    t.waitFor(function () {
      return host.reviewCalls.length > 0
    }, 3000, 'the review is read for a checkout with a finished task', readFlow)
  })
  // The read names the pair, nothing is fetched, and the card shows the facts.
  function readFlow() {
    t.equal(host.reviewCalls[0].argv.slice(1), ['review', '--project', 'p-a', '--checkout', 'c-l', '--json'], 'the read names the selected pair')
    host.answerReviews(null)
    t.waitFor(function () {
      return host.card() && host.card().visible && !!host.card().info
    }, 3000, 'the card shows with review data', function () {
      t.equal(host.text('reviewTitle'), 'Ready for review · feat/x', 'the title names the branch')
      t.equal(host.text('reviewChanges'), '2 commits · 3 files', 'the changes line counts commits and files')
      t.check(t.findChild(host.card(), 'reviewCommit:0').visible && t.findChild(host.card(), 'reviewCommit:1').visible, 'two commit rows show')
      t.check(!t.findChild(host.card(), 'reviewCommit:2'), 'no third commit row')
      t.check(!t.findChild(host.card(), 'reviewShowAll').visible, 'Show all is hidden for two commits')
      t.check(!t.findChild(host.card(), 'reviewUncommitted').visible, 'no uncommitted line for a clean checkout')
      t.equal(host.text('reviewAgentReport'), 'Agent reported: passed', 'the agent report is shown')
      t.equal(host.text('reviewChecks'), 'Your checks: not run', 'the checks line reads not run')
      t.check(host.button('reviewRunChecks').visible, 'Run checks is offered because a check action exists')
      t.equal(host.reviewCalls.length, 1, 'nothing else was read')
      t.equal(host.gitCalls.length, 0, 'showing the card ran no Git command')
      t.equal(host.launches.length, 0, 'showing the card launched nothing')
      t.equal(host.actionCalls.filter(function (a) {
        return a[0] === '/usr/bin/cat'
      }).length, 0, 'showing the card ran no check')
      checksFlow()
    })
  }
  // Run checks starts the action once for this checkout.
  function checksFlow() {
    host.button('reviewRunChecks').clicked()
    t.equal(host.actionCalls.filter(function (a) {
      return a[0] === '/usr/bin/cat'
    }).length, 1, 'Run checks starts one run')
    t.check(entry.actionClient.pending, 'the run is for the action client of this checkout')
    t.equal([entry.actionClient.projectId, entry.actionClient.checkoutId], ['p-a', 'c-l'], 'the run targets the selected pair')
    host.actionRequests.filter(function (r) {
      return r.argv[0] === '/usr/bin/cat'
    })[0].done(0, '4f0c2b1e-8a57-4c3d-9d6e-1a2b3c4d5e6f\n', '')
    var started = host.actionRequests.filter(function (r) {
      return r.argv.length === 2 && r.argv[1] === 'start'
    })
    t.equal(started.length, 1, 'Run checks sends exactly one start request')
    t.equal(started[0] ? JSON.parse(started[0].input).actionId : null, 'a-t', 'the start request names the saved check action')
    t.equal(started[0] ? [JSON.parse(started[0].input).projectId, JSON.parse(started[0].input).checkoutId] : null, ['p-a', 'c-l'], 'the start request names the selected pair')
    entry.actionClient.pending = false
    diffFlow()
  }
  // Open diff sends one exact launcher request.
  function diffFlow() {
    var client = entry.reviewClient
    var invalidBases = ['a'.repeat(39), 'a'.repeat(41), 'a'.repeat(63), 'a'.repeat(65), 'A'.repeat(64), 'a'.repeat(64) + '\n', 'HEAD;id']
    invalidBases.forEach(function (bad) {
      t.check(!client.openDiff(host.checkoutPath, bad, 'kitty'), 'malformed merge base is refused')
    })
    t.equal(host.launches.length, 0, 'invalid merge bases never dispatch')
    t.check(client.openDiff(host.checkoutPath, 'a'.repeat(64), 'kitty'), 'SHA-256 merge base dispatches')
    t.equal(JSON.parse(host.launches[0].input).mergeBase, 'a'.repeat(64), 'SHA-256 merge base is preserved')
    host.launches[0].done(0, JSON.stringify({
      ok: true
    }), '')
    host.launches = []
    host.button('reviewOpenDiff').clicked()
    t.equal(host.launches.length, 1, 'Open diff sends one launcher request')
    t.equal(JSON.parse(host.launches[0].input), {
      kind: 'diff',
      cwd: host.checkoutPath,
      mergeBase: host.mergeBase,
      terminalId: 'kitty'
    }, 'the request carries only the kind, folder, merge base and terminal')
    host.launches[0].done(1, JSON.stringify({
      ok: false,
      status: 'failed',
      code: 'TOOL_MISSING',
      message: 'Choose an installed application outside the checkout.'
    }), '')
    t.check(t.findChild(host.card(), 'reviewProblem').visible, 'a refused launch shows a problem')
    pushFlow()
  }
  // Push names the pair, shows progress, keeps the rejection message and re-reads on success.
  function pushFlow() {
    host.button('reviewPush').clicked()
    t.equal(host.gitCalls.length, 1, 'Push sends one command')
    t.equal(host.gitCalls[0].argv.slice(1), ['push', '--project', 'p-a', '--checkout', 'c-l', '--json'], 'Push names the pair and nothing else')
    t.equal(host.button('reviewPush').text, 'Pushing…', 'Push reads Pushing… while pending')
    host.gitCalls[0].done(1, JSON.stringify({
      ok: false,
      data: null,
      error: {
        code: 'PUSH_REJECTED',
        message: 'The remote has newer commits; fetch and update first.',
        recovery: 'Fetch, then try again.'
      }
    }), '')
    t.waitFor(function () {
      return t.findChild(host.card(), 'reviewProblem').visible && t.findChild(host.card(), 'reviewProblem').problem.details.code === 'PUSH_REJECTED'
    }, 3000, 'the rejection shows', function () {
      t.equal(t.findChild(host.card(), 'projectProblemBody').text, 'The remote has newer commits; fetch and update first.', 'the constant message is the body')
      t.equal(host.button('reviewPush').text, 'Push branch', 'Push is idle again')
      bannedFlow()
    })
  }
  // No visible text uses an internal word or an em dash.
  function bannedFlow() {
    var names = ['reviewTitle', 'reviewSummary', 'reviewChanges', 'reviewCommit:0', 'reviewAgentReport', 'reviewChecks', 'reviewRunChecks', 'reviewOpenDiff', 'reviewPush', 'reviewMark', 'reviewRemove', 'projectProblemTitle', 'projectProblemBody']
    names.forEach(function (name) {
      var item = t.findChild(host.card(), name)
      t.check(!!item && !Problems.bannedIn(item.text) && item.text.indexOf(String.fromCharCode(8212)) < 0, name + ' has no banned word or em dash')
    })
    refusedPushFlow()
  }
  // A push that cannot start leaves the earlier failure on screen.
  function refusedPushFlow() {
    host.answerReviews(null)
    var before = host.gitCalls.length
    t.check(surface.runGit('fetch'), 'a fetch starts')
    host.button('reviewPush').clicked()
    t.equal(host.gitCalls.length, before + 1, 'the refused push sent nothing')
    t.equal(t.findChild(host.card(), 'reviewProblem').problem.details.code, 'PUSH_REJECTED', 'a refused push keeps the earlier push failure')
    host.gitCalls[before].done(0, JSON.stringify({
      ok: true,
      data: {},
      error: null
    }), '')
    t.waitFor(function () {
      return host.reviewCalls.some(function (c) {
        return !c.answered
      })
    }, 3000, 'the fetch re-reads the review', successFlow)
  }
  // A successful push re-reads the review.
  function successFlow() {
    host.answerReviews(null)
    host.reviewCalls = []
    host.button('reviewPush').clicked()
    host.gitCalls[host.gitCalls.length - 1].done(0, JSON.stringify({
      ok: true,
      data: {
        projectId: 'p-a',
        checkoutId: 'c-l',
        remote: 'origin',
        branch: 'feat/x',
        upstream: 'origin/feat/x',
        pushed: true
      },
      error: null
    }), '')
    t.waitFor(function () {
      return host.reviewCalls.length > 0
    }, 3000, 'a successful push re-reads the review', function () {
      host.answerReviews(null)
      t.check(!t.findChild(host.card(), 'reviewProblem').problem || t.findChild(host.card(), 'reviewProblem').problem.details.code !== 'PUSH_REJECTED', 'success clears the rejection')
      pendingFetchFlow()
    })
  }
  // A pending fetch holds Push back, and a press sends nothing.
  function pendingFetchFlow() {
    var before = host.gitCalls.length
    t.check(surface.runGit('fetch'), 'a fetch starts')
    t.check(!host.button('reviewPush').enabled, 'Push is disabled while a fetch is pending')
    host.button('reviewPush').clicked()
    t.equal(host.gitCalls.length, before + 1, 'a press during a fetch sends no push')
    t.equal(host.gitCalls[before].argv[1], 'fetch', 'only the fetch is running')
    host.answerReviews(null)
    host.reviewCalls = []
    host.gitCalls[before].done(0, JSON.stringify({
      ok: true,
      data: {},
      error: null
    }), '')
    t.waitFor(function () {
      return host.reviewCalls.length > 0
    }, 3000, 'a finished fetch re-reads the review', function () {
      host.answerReviews(null)
      removeFlow()
    })
  }
  // Remove opens the existing removal card for this checkout.
  function removeFlow() {
    var before = host.gitCalls.length
    host.button('reviewRemove').clicked()
    t.equal(host.gitCalls[before].argv.slice(1), ['task-remove', '--project', 'p-a', '--checkout', 'c-l', '--check', '--json'], 'Remove starts the removal check')
    t.equal([surface.removeTarget.projectId, surface.removeTarget.checkoutId], ['p-a', 'c-l'], 'the removal card targets this checkout')
    host.gitCalls[before].done(1, JSON.stringify({
      ok: false,
      data: null,
      error: {
        code: 'GIT_ERROR',
        message: 'x',
        recovery: ''
      }
    }), '')
    surface.removeTarget = null
    markFlow()
  }
  // Mark reviewed sends the head and task time; a new head brings the card back.
  function markFlow() {
    host.button('reviewMark').clicked()
    t.equal(host.mutations.length, 1, 'Mark reviewed sends one registry request')
    var sent = JSON.parse(host.mutations[0].input)
    t.equal([sent.action, sent.args], ['review-mark',
      {
        projectId: 'p-a',
        checkoutId: 'c-l',
        head: host.head,
        taskFinishedAt: 100
      }
    ], 'the request carries the head and the task time')
    host.mutations[0].done(0, JSON.stringify({
      ok: true,
      state: host.state(2, {
        reviewedHead: host.head,
        reviewedTaskAt: 100,
        reviewedAt: 200
      })
    }), '')
    t.waitFor(function () {
      return !host.card().visible
    }, 3000, 'the card hides once marked', function () {
      host.answerReviews(null)
      host.reviewHead = host.newHead
      host.reviewCalls = []
      entry.reviewClient.refreshSelected()
      host.answerReviews(null)
      t.waitFor(function () {
        return host.card().visible
      }, 3000, 'a new head brings the card back', readErrorFlow)
    })
  }
  // A failed read shows a problem and keeps Remove.
  function readErrorFlow() {
    host.answerReviews(null)
    entry.projectController.state = host.state(3)
    entry.reviewClient.reviews = {}
    host.reviewCalls = []
    entry.reviewClient.refreshSelected()
    host.answerReviews({
      code: 'NO_DEFAULT_BRANCH',
      message: 'No default branch to compare with.',
      recovery: 'Fetch first.'
    })
    t.waitFor(function () {
      var problem = t.findChild(host.card(), 'reviewProblem')
      return problem.visible && problem.problem.details.code === 'NO_DEFAULT_BRANCH'
    }, 3000, 'the read failure shows', function () {
      t.check(host.button('reviewRemove').visible && host.button('reviewRemove').enabled, 'Remove stays available')
      otherProjectFlow()
    })
  }
  // Review state saved for another project's checkout of the same id is never shown here.
  function otherProjectFlow() {
    entry.reviewClient.diffError = null
    entry.reviewClient.reviews = {
      'c-l': {
        projectId: 'p-other',
        data: null,
        error: {
          code: 'NO_DEFAULT_BRANCH',
          message: 'No default branch to compare with.',
          recovery: ''
        }
      }
    }
    t.check(!t.findChild(host.card(), 'reviewProblem').visible, "another project's read failure is not shown")
    workingFlow()
  }
  // Working and needs-input show a line instead of the card.
  function workingFlow() {
    host.setTasks([host.task('working', 300)])
    t.waitFor(function () {
      return !host.card().visible && t.findChild(surface, 'reviewWorking').visible
    }, 3000, 'working shows the working line', function () {
      t.equal(t.findChild(surface, 'reviewWorking').text, 'Agent working', 'the working line reads Agent working')
      host.setTasks([host.task('needs-input', 301)])
      t.waitFor(function () {
        return t.findChild(surface, 'reviewWorking').text === 'Agent needs input'
      }, 3000, 'needs input shows its line', function () {
        t.check(!host.card().visible, 'no card while the agent needs input')
        host.setTasks([host.task('ready-for-review', 400)])
        t.waitFor(function () {
          return host.card().visible
        }, 3000, 'the card returns when the agent finishes', timerFlow)
      })
    })
  }
  // The timed re-read runs on Overview only.
  function timerFlow() {
    host.answerReviews(null)
    entry.reviewClient.refreshInterval = 100
    surface.section = 'agents'
    host.reviewCalls = []
    t.step(500, function () {
      t.equal(host.reviewCalls.length, 0, 'no timed re-read away from Overview')
      surface.section = 'overview'
      t.waitFor(function () {
        return host.reviewCalls.length > 0
      }, 3000, 'the timed re-read runs on Overview', function () {
        host.answerReviews(null)
        entry.reviewClient.refreshInterval = 600000
        longFlow()
      })
    })
  }
  // Long commit lists fold, and uncommitted work is named.
  function longFlow() {
    host.commitCount = 7
    host.dirty = true
    entry.reviewClient.refreshSelected()
    host.answerReviews(null)
    t.waitFor(function () {
      return host.text('reviewChanges') === '7 commits · 3 files'
    }, 3000, 'seven commits are counted', function () {
      t.check(t.findChild(host.card(), 'reviewCommit:4').visible && !t.findChild(host.card(), 'reviewCommit:5'), 'five subjects show at first')
      t.check(t.findChild(host.card(), 'reviewUncommitted').visible, 'uncommitted changes are named')
      host.button('reviewShowAll').clicked()
      t.check(!!t.findChild(host.card(), 'reviewCommit:6'), 'Show all lists every subject')
      summaryFlow()
    })
  }
  // The agent's summary and finish time show under the title; seconds are read as seconds.
  function summaryFlow() {
    var finishedAt = Math.floor(Date.now() / 1000) - 7200
    host.setTasks([host.task('ready-for-review', finishedAt, 'reported-pass', 'Added the parser', 'Write the parser')])
    t.waitFor(function () {
      return host.text('reviewTask') === 'Added the parser'
    }, 3000, 'the result is the summary', function () {
      t.equal(host.text('reviewFinished'), 'Finished 2h ago', 'the finish time reads as an age')
      host.setTasks([host.task('ready-for-review', finishedAt, 'reported-pass', '', 'Write the parser')])
      t.waitFor(function () {
        return host.text('reviewTask') === 'Write the parser'
      }, 3000, 'the description is the fallback', filesFlow)
    })
  }
  // Show all also lists every changed file; fewer folded files show five, and a binary file says so.
  function filesFlow() {
    host.manyFiles = true
    host.card().showAll = false
    entry.reviewClient.refreshSelected()
    host.answerReviews(null)
    t.waitFor(function () {
      return host.text('reviewChanges') === '7 commits · 8 files'
    }, 3000, 'eight files are counted', function () {
      t.equal(host.text('reviewFile:0'), 'a.js  +1 -0', 'a file row shows added and removed')
      t.check(!!t.findChild(host.card(), 'reviewFile:4') && !t.findChild(host.card(), 'reviewFile:5'), 'five files show at first')
      host.button('reviewShowAll').clicked()
      t.equal(host.text('reviewFile:7'), 'img.png  binary', 'Show all lists every file, and a binary file says so')
      staleMarkFlow()
    })
  }
  // Mark reviewed needs fresh data: a failed re-read leaves it off.
  function staleMarkFlow() {
    host.manyFiles = false
    var before = host.mutations.length
    entry.reviewClient.reviews = {
      'c-l': {
        projectId: 'p-a',
        data: host.reviewData(),
        error: {
          code: 'GIT_TIMEOUT',
          message: 'Git took too long.',
          recovery: ''
        }
      }
    }
    t.check(!host.button('reviewMark').enabled, 'Mark reviewed is off after a failed read')
    surface.markReviewed()
    t.equal(host.mutations.length, before, 'a failed read lets nothing be marked')
    entry.reviewClient.reviews = {
      'c-l': {
        projectId: 'p-a',
        data: host.reviewData(),
        error: null
      }
    }
    t.check(host.button('reviewMark').enabled, 'Mark reviewed returns with fresh data')
    switchFlow()
  }
  // A read still in flight for one project never shows on another project's checkout of the same id.
  function switchFlow() {
    var other = host.project()
    other.id = 'p-b'
    other.name = 'p-b'
    var task = host.task('ready-for-review', 100)
    var otherTask = host.task('ready-for-review', 100)
    otherTask.id = 't2'
    otherTask.taskId = 't2'
    otherTask.association = {
      status: 'registered',
      projectId: 'p-b',
      checkoutId: 'c-l'
    }
    host.setTasks([task, otherTask])
    entry.projectController.state = {
      revision: 9,
      projects: [host.project(), other],
      roots: [],
      ignored: []
    }
    entry.reviewClient.reviews = {}
    host.reviewCalls = []
    entry.reviewClient.refreshSelected()
    t.equal(host.reviewCalls.length, 1, 'a read for the first project is in flight')
    t.equal(host.reviewCalls[0].argv.slice(1, 5), ['review', '--project', 'p-a', '--checkout'], 'the held read belongs to the first project')
    entry.projectId = 'p-b'
    t.waitFor(function () {
      return surface.reviewModel.state === 'ready' && entry.selectedProject.id === 'p-b'
    }, 3000, 'the second project is selected and ready', function () {
      host.reviewCalls[0].answered = true
      host.reviewCalls[0].done(0, JSON.stringify({
        ok: true,
        data: host.reviewData(),
        error: null
      }), '')
      t.step(100, function () {
        t.equal(entry.reviewClient.reviews['c-l'].projectId, 'p-a', 'the late result is stored for the project it was read for')
        t.equal(surface.reviewModel.data, null, 'the late result shows nothing on the new project')
        t.check(!surface.reviewModel.readError && !surface.reviewModel.error, 'the late result shows no failure on the new project')
        t.check(!host.card().info, 'the card holds no data from the old project')
        entry.projectId = 'p-a'
        inertFlow()
      })
    })
  }
  // Capture mode disables every action and reads nothing.
  function inertFlow() {
    host.entryCounts = [host.reviewCalls.length, host.gitCalls.length, host.launches.length, host.mutations.length]
    entry.captureActive = true
    t.step(80, function () {
      ['reviewRunChecks', 'reviewOpenDiff', 'reviewPush', 'reviewMark', 'reviewRemove'].forEach(function (name) {
        t.check(!host.button(name).enabled, name + ' is disabled in capture')
        host.button(name).clicked()
      })
      t.check(!entry.reviewClient.refreshSelected(), 'capture refuses a review read')
      t.equal([host.reviewCalls.length, host.gitCalls.length, host.launches.length, host.mutations.length], host.entryCounts, 'capture sends nothing')
      t.done()
    })
  }
}
