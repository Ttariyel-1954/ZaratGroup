#!/bin/bash
# Zarat Faza 2 — zavod_edge_db serverini dayandırır (port 5434)
export LC_ALL="en_US.UTF-8"
PGBIN="/usr/local/opt/postgresql@18/bin"
PGDATA="/usr/local/var/zavod_edge_pgdata"

"$PGBIN/pg_ctl" -D "$PGDATA" stop
