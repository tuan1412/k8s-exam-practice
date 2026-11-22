#!/usr/bin/env bash
# Runs in the background on a CI runner (as root): when an apt-get, on the runner or in an
# exam host, runs for more than two minutes, write down what it is doing to /tmp/apt-watchdog.log.
out=/tmp/apt-watchdog.log
while sleep 30; do
  for pid in $(pgrep -x apt-get); do
    age=$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ')
    [ "${age:-0}" -ge 120 ] && [ $((age % 120)) -lt 30 ] || continue
    {
      echo "== $(date -u +%T) apt-get $pid running for ${age}s: $(tr '\0' ' ' < "/proc/$pid/cmdline")"
      kids=$(pgrep -P "$pid" | tr '\n' ' ')
      for k in $kids; do kids+=" $(pgrep -P "$k" | tr '\n' ' ')"; done
      [ -z "${kids// }" ] || ps -o pid,ppid,etimes,stat,wchan:22,args -p "$(echo $kids | tr ' ' ',')"
      for k in $kids; do   # sockets of its helpers (download methods), also inside a container
        nsenter -t "$k" -n ss -tnpi 2>/dev/null | grep -A1 "pid=$k," || true
      done
      ls -l /proc/"$pid"/fd 2>/dev/null | grep -E 'lock|partial' || true
    } >> "$out" 2>&1
  done
done
