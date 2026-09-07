#!/usr/bin/env bash
# The defect list for this repository, read by `t.sh falsify`.
#
# COPYING THIS FILE PROVES NOTHING. The mechanism travels; the knowledge does not. What
# makes falsification worth running is entirely in the entries below, and they can only be
# written by someone who knows what this code is supposed to guarantee. A harness that has
# only ever printed "caught" may simply be matching nothing.
#
#   defect NAME FILE FIND REPLACE CONSEQUENCE
#   defect NAME FILE FIND REPLACE CONSEQUENCE expect survived REASON
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

# An edit nothing can observe, declared as such rather than left out of the list: the
# sort key only orders a report, and no caller depends on the order
defect 'report/order' 'src/report.py' \
  '    rows.sort(key=lambda r: r.name)' \
  '    rows.sort(key=lambda r: r.name, reverse=True)' \
  'the report lists hosts in another order' \
  expect survived 'the order is cosmetic and no caller reads the report by position'

# <<< EXAMPLE
