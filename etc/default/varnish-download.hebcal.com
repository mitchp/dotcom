# Configuration file for Varnish Cache.
#
# /etc/init.d/varnish expects the variables $DAEMON_OPTS, $NFILES and $MEMLOCK
# to be set from this shell script fragment.
#
# Note: If systemd is installed, this file is obsolete and ignored.  You will
# need to copy /lib/systemd/system/varnish.service to /etc/systemd/system/ and
# edit that file.

# Should we start varnishd at boot?  Set to "no" to disable.
START=yes

# Maximum number of open files (for ulimit -n)
NFILES=131072

# Maximum locked memory size (for ulimit -l)
# Used for locking the shared memory log in memory.  If you increase log size,
# you need to increase this number as well
MEMLOCK=82000

# Default varnish instance name is the local nodename.  Can be overridden with
# the -n switch, to have more instances on a single server.
INSTANCE=$(uname -n)

DAEMON_OPTS="-a :80 \
             -T localhost:6082 \
             -f /etc/varnish/default.vcl \
             -S /etc/varnish/secret \
             -s file,/var/lib/varnish/$INSTANCE/varnish_storage.bin,16G"