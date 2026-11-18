#!/bin/sh
# Simulate lock and unlock without locking the screen or starting a LaunchAgent.
set -eu

bin=${1:-build/lock-mute}
name="local.lock-mute.test.$$"

before=$("$bin" status) || { echo "SKIP: default output has no mute control"; exit 0; }
if [ "$before" = muted ] && [ "${LOCK_MUTE_TEST_FORCE:-}" != 1 ]; then
	echo "SKIP: output is already muted. Set LOCK_MUTE_TEST_FORCE=1 to unmute it for a moment."
	exit 0
fi

LOCK_MUTE_TEST_NOTIFICATION_PREFIX=$name "$bin" &
pid=$!
restore() {
	kill "$pid" 2>/dev/null || true
	wait "$pid" 2>/dev/null || true
	"$bin" "$([ "$before" = muted ] && echo mute || echo unmute)" || true
}
trap restore EXIT

post() {
	osascript -l JavaScript -e "ObjC.import('Foundation'); \$.NSDistributedNotificationCenter.defaultCenter.postNotificationNameObjectUserInfoDeliverImmediately('$name.$1', \$(), \$(), true)" >/dev/null
}

expect_output() {
	expected=$1
	i=0
	while [ "$("$bin" status)" != "$expected" ]; do
		i=$((i + 1))
		[ "$i" -lt 20 ] || { echo "FAIL: expected output to be $expected"; exit 1; }
		sleep 0.1
	done
}

sleep 0.5
"$bin" unmute
expect_output unmuted

post lock
expect_output muted
post lock
post unlock
expect_output unmuted
echo "PASS: lock muted the output and unlock restored sound after a duplicate lock event."

"$bin" mute
expect_output muted
post lock
post unlock
sleep 0.5
[ "$("$bin" status)" = muted ] || { echo "FAIL: unlock changed a manual mute"; exit 1; }
echo "PASS: unlock kept manually muted sound muted."
