#!/usr/bin/env bash
# Runs the real test runners and checks the marker sets against what they print today.
#
#   tests/upstream.sh [--write] [ECOSYSTEM...]
#
# The gate compares markers with fixtures that were captured once. This compares them with
# the tools, which is the thing that moves. A marker has three ways to die and they need
# different questions:
#
#   the line was renamed upstream   the marker matches nothing any more, and the check it
#                                   stands for is gone without a word
#   a healthy run started saying it the marker reddens honest runs, and gets switched off
#   a new lie appeared              a situation exits 0 and no marker covers it
#
# So each ecosystem below declares the situations it can lie in, as a list written by hand
# the way tests/defects.sh is, and this runs them. A situation that exits 0 must be caught
# by a marker, or declared `silent` with the reason — Maven prints nothing at all for a
# module with no test class, and no marker can reach what the tool does not say.
#
# Not part of check.sh, and it must not be: it needs a network and half a gigabyte of
# toolchains, while the gate promises neither. CI runs it on a schedule, where a red run
# means the world moved rather than that somebody's commit is wrong.
#
# --write rewrites the fixtures under tests/fixtures/ so the drift arrives as a diff to
# read rather than as a message to interpret.
set -uo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$HERE" || exit 70

write=""
wanted=()
for arg in "$@"; do
  case "$arg" in
    --write) write=1 ;;
    -*)
      echo "upstream: no such flag: $arg" >&2
      exit 64
      ;;
    *) wanted+=("$arg") ;;
  esac
done

problems=0
note() {
  printf 'upstream: %s\n' "$1" >&2
  problems=$((problems + 1))
}

work=$(mktemp -d "${TMPDIR:-/tmp}/upstream.XXXXXX")
trap 'rm -rf "$work"' EXIT

wants() { # wants ECOSYSTEM
  ((${#wanted[@]} > 0)) || return 0
  local w
  for w in "${wanted[@]}"; do [[ "$w" == "$1" ]] && return 0; done
  return 1
}

# The markers of one set, comments and blank lines dropped, as t.sh reads them
markers_of() { # markers_of NAME
  grep -v '^[[:space:]]*#' "markers/$1.txt" | grep -v '^[[:space:]]*$' || :
}

# One situation: its output, its status, and what we claim about it. LIES means the tool
# exits 0 while the run answered about less than it appears to; HONEST means the status
# already says so and a marker would be a second opinion; SILENT means it lies and prints
# nothing a marker could match, which is a finding rather than a gap.
declare_situation() { # declare_situation KIND NAME STATUS OUTFILE [REASON]
  local kind="$1" name="$2" status="$3" out="$4" reason="${5:-}"
  case "$kind" in
    lies)
      ((status == 0)) ||
        note "$eco/$name is declared a lie but exited $status — the status already says so, so it is honest now"
      local hit="" m
      while IFS= read -r m; do
        [[ -n "$m" ]] || continue
        # Recorded, not just counted: a marker that matched nothing across every situation
        # of its ecosystem has died quietly, and a live neighbour would otherwise cover for
        # it. That is checked once per ecosystem, by every_marker_still_matches below
        grep -qiF -- "$m" "$out" && {
          hit="$m"
          printf '%s\n' "$m" >>"$work/$eco.seen"
        }
      done < <(markers_of "$eco")
      [[ -n "$hit" ]] ||
        note "$eco/$name exits 0 and no marker in markers/$eco.txt matches its output — either the line was renamed upstream or this is a lie nobody covers yet"
      ;;
    honest)
      ((status != 0)) ||
        note "$eco/$name was declared honest and exited 0 — the tool stopped refusing, and it needs a marker now"
      ;;
    silent)
      ((status == 0)) ||
        note "$eco/$name is declared a silent lie but exited $status — the status says so now, so the note is stale: $reason"
      local m2
      while IFS= read -r m2; do
        [[ -n "$m2" ]] || continue
        ! grep -qiF -- "$m2" "$out" ||
          note "$eco/$name is declared unmatchable, and the marker '$m2' matches it — the tool started saying something, so drop the declaration"
      done < <(markers_of "$eco")
      ;;
  esac
}

# The healthy run, held to exactly what the gate holds the stored fixture to: every default
# marker must stay quiet on it, and so must this ecosystem's own set. Not the other sets —
# they are opted into with -m, and `skipped` from the pytest set matching a .NET run's
# `Skipped: 0` is not a fault of either. Checking all of them was this script's first
# finding, about itself.
check_healthy() { # check_healthy OUTFILE STATUS
  local out="$1" status="$2" m set
  ((status == 0)) || note "$eco: the healthy run exited $status — the fixture project no longer passes"
  for set in markers/default.txt "markers/$eco.txt"; do
    [[ -f "$set" ]] || continue
    while IFS= read -r m; do
      [[ -n "$m" ]] || continue
      ! grep -qiF -- "$m" "$out" ||
        note "$eco: '$m' from $set matches the healthy run — a marker that reddens an honest run gets the whole check switched off"
    done < <(grep -v '^[[:space:]]*#' "$set" | grep -v '^[[:space:]]*$' || :)
  done
}

run() { # run OUTFILE CMD... -> writes the output, returns the command's status
  local out="$1"
  shift
  "$@" >"$out" 2>&1
}

# Called once an ecosystem's situations have all run. A marker that matched none of them is
# the quiet death this script exists for: the line was renamed upstream, the check it stood
# for is gone, and every run stays green because the neighbouring markers still match.
every_marker_still_matches() {
  local m
  while IFS= read -r m; do
    [[ -n "$m" ]] || continue
    grep -qxF -- "$m" "$work/$eco.seen" 2>/dev/null ||
      note "$eco: the marker '$m' matched none of the situations below it — it has stopped catching anything, and nothing else will say so"
  done < <(markers_of "$eco")
}

# ---------------------------------------------------------------- php

if wants php; then
  eco=php
  echo "== php: PHPUnit"
  d="$work/php"
  mkdir -p "$d/tests" "$d/src" "$d/empty" "$d/skipped" "$d/nomethods"
  cat >"$d/src/Clamp.php" <<'PHP'
<?php
function clampToZero(int $n): int { return $n < 0 ? 0 : $n; }
PHP
  cat >"$d/tests/ClampTest.php" <<'PHP'
<?php
use PHPUnit\Framework\TestCase;
require_once __DIR__ . '/../src/Clamp.php';

final class ClampTest extends TestCase
{
    public function testNegativeBecomesZero(): void { $this->assertSame(0, clampToZero(-5)); }
    public function testPositiveIsKept(): void { $this->assertSame(7, clampToZero(7)); }
}
PHP
  cat >"$d/skipped/AllSkippedTest.php" <<'PHP'
<?php
use PHPUnit\Framework\TestCase;
final class AllSkippedTest extends TestCase
{
    public function testOne(): void { $this->markTestSkipped('needs a database'); }
    public function testTwo(): void { $this->markTestSkipped('needs a network'); }
}
PHP
  cat >"$d/nomethods/NoMethodsTest.php" <<'PHP'
<?php
use PHPUnit\Framework\TestCase;
final class NoMethodsTest extends TestCase { public function helper(): void {} }
PHP
  pu() { (cd "$d" && nix shell nixpkgs#phpunit -c phpunit --cache-directory .cache "$@"); }

  run "$work/php.healthy" pu tests
  check_healthy "$work/php.healthy" "$?"

  run "$work/php.empty" pu empty
  declare_situation lies "a directory holding no test file" "$?" "$work/php.empty"
  run "$work/php.skipped" pu skipped
  declare_situation lies "every test skipped" "$?" "$work/php.skipped"
  run "$work/php.nomethods" pu nomethods
  declare_situation honest "a class with no test method" "$?" "$work/php.nomethods"
  run "$work/php.filter" pu --filter nosuchtest tests
  declare_situation honest "a filter matching nothing" "$?" "$work/php.filter"
  run "$work/php.bootstrap" pu --bootstrap no-such-file.php tests
  declare_situation honest "a bootstrap that does not exist" "$?" "$work/php.bootstrap"
  every_marker_still_matches

  if [[ -n "$write" ]]; then
    {
      # shellcheck disable=SC2016  # markdown backticks in a fixture header, not a substitution
      printf 'A healthy `phpunit tests` on a suite where every test runs and asserts, captured from a real run. No entry in markers/php.txt may match anything here.\n\n'
      cat "$work/php.healthy"
    } >tests/fixtures/clean/php.log
    {
      printf 'A log carrying one realistic line per entry in markers/php.txt, captured from real runs that exited 0.\n\n'
      cat "$work/php.empty" "$work/php.skipped"
    } >tests/fixtures/lying/php.log
  fi
fi

# ---------------------------------------------------------------- dotnet

if wants dotnet; then
  eco=dotnet
  echo "== dotnet: dotnet test, VSTest"
  d="$work/dn"
  mkdir -p "$d/home"
  export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1
  dn() { (cd "$d" && HOME="$d/home" nix shell nixpkgs#dotnet-sdk -c dotnet "$@"); }
  dn new xunit -o Demo >/dev/null 2>&1 ||
    note "dotnet: could not create the fixture project — the rest of this section says nothing"
  if [[ -d "$d/Demo" ]]; then
    cp -r "$d/Demo" "$d/NoTests"
    sed -i 's/\[Fact\]//' "$d/NoTests"/*.cs 2>/dev/null || :

    run "$work/dn.healthy" dn test Demo
    check_healthy "$work/dn.healthy" "$?"

    run "$work/dn.filter" dn test Demo --filter 'FullyQualifiedName~NoSuchTest'
    declare_situation lies "a --filter matching nothing" "$?" "$work/dn.filter"
    run "$work/dn.notests" dn test NoTests
    declare_situation lies "an assembly the adapter sees no test in" "$?" "$work/dn.notests"
    every_marker_still_matches

    if [[ -n "$write" ]]; then
      {
        # shellcheck disable=SC2016  # markdown backticks in a fixture header, not a substitution
        printf 'A healthy `dotnet test` on an xunit project where the tests run, captured from a real run. No entry in markers/dotnet.txt may match anything here.\n\n'
        cat "$work/dn.healthy"
      } >tests/fixtures/clean/dotnet.log
      {
        printf 'A log carrying one realistic line per entry in markers/dotnet.txt, captured from real runs that exited 0.\n\n'
        cat "$work/dn.filter" "$work/dn.notests"
      } >tests/fixtures/lying/dotnet.log
    fi
  fi
fi

# ---------------------------------------------------------------- jvm

if wants jvm; then
  eco=jvm
  echo "== jvm: Maven, surefire"
  d="$work/jvm"
  mkdir -p "$d/src/main/java/demo" "$d/src/test/java/demo"
  cat >"$d/pom.xml" <<'POM'
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <groupId>demo</groupId>
  <artifactId>demo</artifactId>
  <version>1.0</version>
  <properties>
    <maven.compiler.source>21</maven.compiler.source>
    <maven.compiler.target>21</maven.compiler.target>
    <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
  </properties>
  <dependencies>
    <dependency>
      <groupId>org.junit.jupiter</groupId>
      <artifactId>junit-jupiter</artifactId>
      <version>5.11.3</version>
      <scope>test</scope>
    </dependency>
  </dependencies>
</project>
POM
  cat >"$d/src/main/java/demo/Clamp.java" <<'JAVA'
package demo;
public final class Clamp {
    public static int toZero(int n) { return n < 0 ? 0 : n; }
}
JAVA
  cat >"$d/src/test/java/demo/ClampTest.java" <<'JAVA'
package demo;
import static org.junit.jupiter.api.Assertions.assertEquals;
import org.junit.jupiter.api.Test;
class ClampTest {
    @Test void negativeBecomesZero() { assertEquals(0, Clamp.toZero(-5)); }
    @Test void positiveIsKept() { assertEquals(7, Clamp.toZero(7)); }
}
JAVA
  mvn_() { (cd "$d" && nix shell nixpkgs#maven nixpkgs#jdk -c mvn -Dmaven.repo.local="$d/.m2" "$@"); }

  run "$work/jvm.healthy" mvn_ test
  check_healthy "$work/jvm.healthy" "$?"

  run "$work/jvm.skip" mvn_ -DskipTests test
  declare_situation lies "-DskipTests left in the command" "$?" "$work/jvm.skip"

  # A class that exists and holds nothing runnable
  mv "$d/src/test/java/demo/ClampTest.java" "$d/ClampTest.java.away"
  cat >"$d/src/test/java/demo/EmptyTest.java" <<'JAVA'
package demo;
class EmptyTest { void helper() {} }
JAVA
  run "$work/jvm.zero" mvn_ test
  declare_situation lies "a test class with nothing runnable in it" "$?" "$work/jvm.zero"
  rm -f "$d/src/test/java/demo/EmptyTest.java"

  # And the one no marker can reach
  run "$work/jvm.none" mvn_ test
  declare_situation silent "a module with no test class at all" "$?" "$work/jvm.none" \
    "surefire prints its plugin header and BUILD SUCCESS and nothing else, so failIfNoTests is the only guard"
  mv "$d/ClampTest.java.away" "$d/src/test/java/demo/ClampTest.java"

  run "$work/jvm.filter" mvn_ -Dtest=NoSuchTest test
  declare_situation honest "-Dtest matching nothing" "$?" "$work/jvm.filter"
  every_marker_still_matches

  if [[ -n "$write" ]]; then
    {
      # shellcheck disable=SC2016  # markdown backticks in a fixture header, not a substitution
      printf 'A healthy `mvn test` on a module whose test class runs, captured from a real run. No entry in markers/jvm.txt may match anything here.\n\n'
      sed -n '/T E S T S/,/BUILD SUCCESS/p' "$work/jvm.healthy"
    } >tests/fixtures/clean/jvm.log
    {
      printf 'A log carrying one realistic line per entry in markers/jvm.txt, captured from real runs that printed BUILD SUCCESS and exited 0.\n\n'
      grep -E 'Tests run: 0|Tests are skipped|BUILD SUCCESS|surefire' "$work/jvm.zero" "$work/jvm.skip" | sed 's/^[^:]*://'
    } >tests/fixtures/lying/jvm.log
  fi
fi

# ---------------------------------------------------------------- playwright

if wants playwright; then
  eco=playwright
  echo "== playwright: no marker set, and the run below is why"
  d="$work/pw"
  mkdir -p "$d/tests" "$d/empty"
  cat >"$d/tests/clamp.spec.js" <<'JS'
const { test, expect } = require('@playwright/test');
function clampToZero(n) { return n < 0 ? 0 : n; }
test('a negative reading becomes zero', async () => { expect(clampToZero(-5)).toBe(0); });
test('a positive reading is kept', async () => { expect(clampToZero(7)).toBe(7); });
JS
  pw() { (cd "$d" && nix shell nixpkgs#playwright-test -c playwright "$@"); }

  # There is no markers/playwright.txt, so `silent` is asserted against every other set:
  # the day one of these shapes starts printing something a marker catches, the reference
  # saying "there is no set, and here is why" has stopped being true
  run "$work/pw.pass" pw test --grep NoSuchTitle --pass-with-no-tests --reporter=list
  st=$?
  ((st == 0)) || note "playwright: --pass-with-no-tests exited $st — it refuses now, and the reference is stale"
  # A blank line is what it prints; the claim is that there is no content, not no bytes
  [[ -z "$(tr -d '[:space:]' <"$work/pw.pass")" ]] ||
    note "playwright: --pass-with-no-tests printed something — the reference says a blank line and nothing else:"$'\n'"$(cat "$work/pw.pass")"

  run "$work/pw.grep" pw test --grep NoSuchTitle --reporter=list
  declare_situation honest "a --grep matching nothing" "$?" "$work/pw.grep"

  if [[ -n "$write" ]]; then
    run "$work/pw.healthy" pw test --reporter=list
    printf 'Playwright ships no marker set; this is kept only so a healthy run is on record. See references/ecosystems/playwright.md.\n\n' >tests/fixtures/clean/playwright.log
    cat "$work/pw.healthy" >>tests/fixtures/clean/playwright.log
  fi
fi

echo
if ((problems == 0)); then
  echo "upstream: every marker still matches a real lie, and none of them matches a healthy run"
else
  echo "upstream: $problems finding(s) above — the tools moved, not the repository" >&2
  exit 1
fi
