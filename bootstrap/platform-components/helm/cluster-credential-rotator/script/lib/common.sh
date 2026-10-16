#!/bin/sh

log() (
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"
)

duration_to_seconds() (
  awk -v value="$1" '
    function fail() { exit 1 }
    BEGIN {
      rest = value
      total = 0

      if (rest == "") {
        fail()
      }

      while (rest != "") {
        if (match(rest, /^[0-9]+[smhd]/) == 0) {
          fail()
        }

        part = substr(rest, RSTART, RLENGTH)
        amount = substr(part, 1, length(part) - 1) + 0
        unit = substr(part, length(part), 1)

        if (unit == "s") {
          multiplier = 1
        } else if (unit == "m") {
          multiplier = 60
        } else if (unit == "h") {
          multiplier = 3600
        } else if (unit == "d") {
          multiplier = 86400
        } else {
          fail()
        }

        total += amount * multiplier
        rest = substr(rest, RLENGTH + 1)
      }

      print total
    }
  ' </dev/null
)

rfc3339_to_epoch() (
  value=$1

  case "$value" in
    ????-??-??T??:??:??*Z)
      ;;
    *)
      return 1
      ;;
  esac

  normalized="$(
    printf '%s' "$value" |
      sed 's/\.[0-9][0-9]*Z$/Z/; s/T/ /; s/Z$//'
  )"

  date -u -d "$normalized" +%s 2>/dev/null
)

json_escape() (
  printf '%s' "$1" | awk '
    BEGIN { ORS = "" }
    {
      if (NR > 1) {
        printf "\\n"
      }
      gsub(/\\/, "\\\\")
      gsub(/"/, "\\\"")
      gsub(/\r/, "\\r")
      gsub(/\t/, "\\t")
      printf "%s", $0
    }
  '
)

refresh_due() (
  expires_at=$1
  refresh_after_epoch=$2

  case "$expires_at" in
    ''|*[!0-9]*)
      return 0
      ;;
  esac

  [ "$refresh_after_epoch" -ge "$expires_at" ]
)
