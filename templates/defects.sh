#!/usr/bin/env bash
# The defect list for this repository, read by `t.sh falsify`.
#
# COPYING THIS FILE PROVES NOTHING. The mechanism travels; the knowledge does not. What
# makes falsification worth running is entirely in the entries below, and they can only be
# written by someone who knows what this code is supposed to guarantee. A harness that has
# only ever printed "caught" may simply be matching nothing.
#
#   defect NAME FILE FIND REPLACE CONSEQUENCE
#
# NAME         short, groupable — `t.sh falsify escape -- ...` runs every name containing
#              "escape"
# FILE         the source file the edit lands in, relative to the repository root
# FIND         text that must appear EXACTLY ONCE in FILE. Zero or many is reported as
#              `stale` rather than guessed at: that is how this list tells you it has
#              drifted away from the code it describes
# REPLACE      what FIND becomes for the length of one run
# CONSEQUENCE  what goes wrong in the world if this guard stops working, in the terms
#              whoever operates the thing would care about. When the suite survives the
#              edit, this sentence is the report: it names what nobody checks
#
# NEUTER, DO NOT BREAK. Good edits leave the code valid and change what it does: `if
# False:`, a dropped filter, a widened comparison, a hardcoded return. An edit that breaks
# the syntax is caught by the parser or the compiler, and a parser is not a test — the
# harness reports that case as `unusable` rather than crediting the suite for it.
#
# Write one entry as each guard is written, and the list doubles as prose documentation of
# what every guard is actually for.

# >>> EXAMPLE: replace everything below with this repository's own guards

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

# <<< EXAMPLE
