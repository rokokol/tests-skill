#!/usr/bin/env bash
# Needs bash 3.2 and POSIX tools only
set -euo pipefail

usage() {
  cat <<'EOF'
The mechanical half of the create-readme skill's rules, checked on any markdown

  check-prose.sh DOC...

  -h, --help   print this and exit

The rules are the readme's, and they hold over every document a repository ships — a
SKILL.md and a changelog are read on the same page by the same reader. Only what a
script can decide is here: whether a paragraph ends bare, whether it occupies one line,
whether an admonition is shaped the way GitHub wants it, whether a quotation mark is the
typographic one, and whether a section duplicates a file that already exists. Tone,
structure and honesty about versions stay a reading job. A finding is one line on
stderr, DOC:LINE: what, so an editor can jump to it

A YAML frontmatter block is data rather than prose, and is skipped: its keys are not
paragraphs, and two of them in a row are not a hard wrap

Nothing here reaches the network
Exit 0 when every document keeps the rules, 1 with one line per finding, 2 on a usage
error or a document that does not exist
EOF
}

die() { # the request itself is wrong
  printf 'check-prose: %s\n' "$1" >&2
  exit 2
}

while (($#)); do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    -*)
      usage >&2
      exit 2
      ;;
    *) break ;;
  esac
done
# No readme is nothing to check, and nothing checked must not read as a clean readme
(($# > 0)) || {
  usage >&2
  exit 2
}
# Every path is looked at before any is read, so a typo is a refusal rather than a
# half-checked run whose findings hide it
for file in "$@"; do
  [[ -f "$file" ]] || die "$file: no such file"
done

fail=0
file=''
n=0
report() { # report MESSAGE — about $file, at line $n
  printf '%s:%s: %s\n' "$file" "$n" "$1" >&2
  fail=1
}

for file in "$@"; do
  inside=0
  prev_prose=0
  front=0
  n=0
  while IFS= read -r line; do
    n=$((n + 1))
    # A frontmatter block is data, not prose: its keys are neither paragraphs nor a hard
    # wrap, and a description ending on a full stop is a sentence in a field. Only a block
    # opening on the first line is one — a --- further down is a horizontal rule
    if [ "$n" -eq 1 ] && [ "$line" = "---" ]; then
      front=1
      continue
    fi
    if [ "$front" -eq 1 ]; then
      if [ "$line" = "---" ]; then front=0; fi
      continue
    fi
    case $line in
      '```'*)
        inside=$((1 - inside))
        prev_prose=0
        continue
        ;;
    esac
    [ "$inside" -eq 1 ] && continue

    # An indented block is code as much as a fenced one is, and the rules below are about
    # prose: a line of shell that ends in a full stop was being reported as a paragraph
    if [ "${line#    }" != "$line" ] || [ "${line#	}" != "$line" ]; then
      prev_prose=0
      continue
    fi

    # A rule has to be able to show the character it forbids, and a code span is how prose
    # says "this one, as a character" rather than using it. The quotation rule below reads
    # the line without its spans for that reason alone. The full stop rule does not: a
    # span closing a paragraph is still the last thing the reader sees, so a stop inside
    # it is a stop at the end of the paragraph
    nospan=$line
    while case $nospan in *'`'*'`'*) true ;; *) false ;; esac do
      rest=${nospan#*\`}
      nospan=${nospan%%\`*}${rest#*\`}
    done

    # Rule 4: sections that have their own file at the root of a repository. The level-one
    # heading is the readme's own title, the project's name, which may well be a contributing
    # skill or a changelog tool; the sections below it are what the rule is about. The
    # heading has to be the word rather than contain it: "Before contributing to someone
    # else's project" is a section about contributing, not a copy of CONTRIBUTING.md
    case $line in
      '# '*) ;;
      '#'*)
        title=$line
        while case $title in '#'*) true ;; *) false ;; esac do
          title=${title#\#}
        done
        title=${title# }
        case $title in
          [Ll]icense | LICENSE | [Cc]ontributing | CONTRIBUTING | [Cc]hangelog | CHANGELOG)
            report "a heading for something that has its own file: ${line}"
            ;;
        esac
        ;;
    esac

    # A quotation mark is the plain one. The pairs are written here as the bytes they are,
    # since a source file carrying the character it forbids teaches the wrong thing to
    # whoever copies a line out of it: U+00AB/BB, U+201C/201D and U+2018/2019. The single
    # pair catches an apostrophe and the eyes of a kaomoji as well as a quotation, and
    # that is the point — none of the three belongs in a document that is read as plain
    # text somewhere
    case $nospan in
      *$'\xc2\xab'* | *$'\xc2\xbb'* | *$'\xe2\x80\x9c'* | *$'\xe2\x80\x9d'* | *$'\xe2\x80\x98'* | *$'\xe2\x80\x99'*)
        report "a typographic quotation mark — quote with the plain \" instead"
        ;;
    esac

    # Rule 5: the admonition keyword takes its line alone, or GitHub renders a
    # plain quote instead of the box
    case $line in
      '> [!'*']'?*)
        report "text on the admonition keyword's line — it belongs below"
        ;;
    esac

    # Rule 6: one paragraph is one line. Badge rows, tables, lists, headings and
    # html are not paragraphs; two prose lines in a row are a hard wrap. A numbered
    # list is a list: `1.` and `2.` on consecutive lines were being read as one
    # paragraph broken in two, and any document with an ordered list was reddened
    if [[ "$line" =~ ^[0-9]+[.\)][[:space:]] ]]; then
      prev_prose=0
    else
      case $line in
        '' | '#'* | '-'* | '*'* | '|'* | '>'* | '<'* | '!['* | '['* | ' '*)
          prev_prose=0
          ;;
        *)
          [ "$prev_prose" -eq 1 ] && report "a hard-wrapped paragraph — one paragraph is one line"
          prev_prose=1
          ;;
      esac
    fi

    # Rule 7: a paragraph, a list item and a table cell all end bare — read through the
    # markup that can close after the stop, since `.**`, `.)` and `` .` `` end on one too
    bare=$line
    while case $bare in *[*_\)\`\"]) true ;; *) false ;; esac do
      bare=${bare%?}
    done
    case $bare in
      *..) ;;
      *[!.].)
        report "ends with a full stop"
        ;;
    esac
  done <"$file"
done

((fail == 0)) || exit 1
printf 'check-prose: %s document(s) keep every rule a script can decide\n' "$#"
