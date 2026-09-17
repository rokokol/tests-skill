#!/usr/bin/env bash
# The defect list for this repository, read by `t.sh falsify`.
#
# Needs bash 3.2, since falsify sources it wherever t.sh runs, macOS included
#
# COPYING THIS FILE PROVES NOTHING. The mechanism travels; the knowledge does not. What
# makes falsification worth running is entirely in the entries below, and they can only be
# written by someone who knows what this code is supposed to guarantee. A harness that has
# only ever printed "caught" may simply be matching nothing.
#
#   defect NAME FILE FIND REPLACE CONSEQUENCE
#   defect NAME FILE FIND REPLACE CONSEQUENCE expect survived REASON
#   defect NAME FILE FIND REPLACE CONSEQUENCE expect caught FRAGMENT
#
# `defect` replaces text. The edits a replacement cannot express — there is nothing unique
# to find in a file that does not exist yet — are written with the second verb, which takes
# the same two endings:
#
#   plant NAME FILE append TEXT     CONSEQUENCE   add TEXT to the end of FILE
#   plant NAME FILE create CONTENT  CONSEQUENCE   create FILE, which the repository lacks
#   plant NAME FILE write  CONTENT  CONSEQUENCE   replace FILE whole
#   plant NAME FILE rm              CONSEQUENCE   delete FILE
#
# Each has its own way of having stopped being an edit, reported `stale` exactly as a find
# text that no longer matches once: text already in the file, a file already there, content
# already in place, a file already gone
#
# Either verb may end with `--and FILE FIND REPLACE`, any number of times, before its
# expectation. That is one defect made of several edits, applied together and reported under
# one name — for a guard whose halves are both needed, where breaking one of them proves
# nothing because the other still holds the behaviour up
#
# A text of several lines, or one holding quotes, goes in single quotes with its newlines
# as they are and each ' inside written '"'"' — never as "$(cat <<'EOF' ... EOF)". The
# parser of bash 3.2, the bash macOS ships, looks for the closing parenthesis inside the
# heredoc's body: an unpaired ' there fails the whole list, and an unpaired ) ends the
# substitution early, so the entry quietly looks for a text that is not in the file. A list
# that goes through shellcheck says once, above its first entry, `# shellcheck
# disable=SC2016 # every $ in a single-quoted text here is text to find, never an expansion`
#
# NAME         short, groupable — `t.sh falsify escape -- ...` runs every name containing
#              "escape"
# FILE         the source file the edit lands in, relative to the repository root. Never a
#              test, vendored or generated file: an edit there is "caught" by whatever it
#              breaks and proves nothing about the suite, and falsify refuses it
# FIND         text that must appear EXACTLY ONCE in FILE. Zero or many is reported as
#              `stale` rather than guessed at: that is how this list tells you it has
#              drifted away from the code it describes
# REPLACE      what FIND becomes for the length of one run
# CONSEQUENCE  what goes wrong in the world if this guard stops working, in the terms
#              whoever operates the thing would care about. When the suite survives the
#              edit, this sentence is the report: it names what nobody checks
# expect survived REASON
#              declares an edit nothing can catch — one that changes the code without
#              changing anything a caller can observe — with the reason where the claim
#              is. It is reported `expected` rather than SURVIVED, and the day the suite
#              does catch it the declaration is `stale`, so it cannot outlive its truth
# expect caught FRAGMENT
#              names what should do the catching: a test name, an assertion message,
#              whatever the suite prints when that guard is the one that fails. "The suite
#              went red" and "the suite noticed this" are different claims, and one flaky
#              test failing through a whole run credits every defect to a suite that saw
#              none of them. Caught with FRAGMENT nowhere in that run's output is `stale`
#
# WHICH DEFECTS TO WRITE, in order of what they find:
#
# 1. The whole body of a function replaced by a constant of the right type: a `return
#    nil`, a `return 0`, a `pass`, an empty list. A function whose body can go without a
#    test failing is covered by nothing, and studies of real code bases put that between
#    six and fifty percent of the methods a coverage tool calls covered. It is also the
#    edit that keeps FIND unique: a body is long, an operator is one character in twenty
#    places.
# 2. One guard neutered: `if x < 0` becomes `if false`, a filter dropped, a comparison
#    widened (`>=` to `>`), an early return removed, `any` swapped for `all`, an error
#    branch replaced with a plain return. These ask about one behaviour each.
#
# NEUTER, DO NOT BREAK. An edit that breaks the syntax is caught by the parser or the
# compiler, and a parser is not a test — the harness reports that as `unusable` rather than
# crediting the suite for it. Run with `-b` in any compiled language, or every such edit
# is invisible.
#
# What is not worth an entry: logging, formatting, comments, trivial accessors, anything
# whose survival teaches nothing and trains everyone to skim the report. About seven per
# file is where the reports that changed what people wrote stopped growing; one per
# behaviour, never two on the same line.
#
# Write one entry as each guard is written, and the list doubles as prose documentation of
# what every guard is actually for.

# >>> EXAMPLE: replace everything below with this repository's own guards

# Tier 1: a body that can vanish. The whole rendering falls back to an empty page, and
# the suite has to notice that a page rendered nothing.
defect 'render/body' 'src/render.py' \
  '    return f"<p>{html.escape(text)}</p>"' \
  '    return ""' \
  'every page renders empty and every caller carries on as if it had content'

# Tier 2: one guard at a time
defect 'escape/raw-text' 'src/render.py' \
  'return f"<p>{html.escape(text)}</p>"' \
  'return f"<p>{text}</p>"' \
  'a label chosen by whoever supplies it becomes live HTML in the reader'

defect 'counters/negative-window' 'src/metrics.py' \
  '    return new - old if new >= old else new' \
  '    return new - old' \
  'a counter reset turns into a negative window instead of a fresh one'

defect 'alerts/silent-absence' 'src/alerts.py' \
  '    for name, reason in data.get("unreachable", []):' \
  '    for name, reason in []:' \
  'something that did not answer reads as healthy and quiet'

# The shapes a replacement cannot write down. A configuration file the deployment reads,
# taken away: nothing in the suite asks what happens when it is not there
plant 'config/absent' 'config/limits.yml' rm \
  'with the file gone every limit falls back to its built-in default and the service accepts ten times the load it should'

# A line appended where the last one wins, which is how a real configuration gets broken
plant 'config/last-wins' 'config/limits.yml' append \
  'max_in_flight: 100000
' \
  'a later key silently overrides the reviewed one and nothing compares the file with what was agreed'

# An edit nothing can observe, declared as such rather than left out of the list: the
# sort key only orders a report, and no caller depends on the order
defect 'report/order' 'src/report.py' \
  '    rows.sort(key=lambda r: r.name)' \
  '    rows.sort(key=lambda r: r.name, reverse=True)' \
  'the report lists hosts in another order' \
  expect survived 'the order is cosmetic and no caller reads the report by position'

# <<< EXAMPLE
