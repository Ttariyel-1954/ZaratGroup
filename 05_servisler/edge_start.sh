#!/bin/bash
# Zarat Faza 2 — zavod_edge_db serverini başladır (port 5434)
export LC_ALL="en_US.UTF-8"
PGBIN="/usr/local/opt/postgresql@18/bin"
PGDATA="/usr/local/var/zavod_edge_pgdata"

"$PGBIN/pg_ctl" -D "$PGDATA" -l "$PGDATA/server.log" start
echo "Status:"
"$PGBIN/pg_ctl" -D "$PGDATA" status
