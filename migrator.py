#!/usr/bin/env python3

import datetime
import os
import platform
import re
import shlex
import subprocess
import sys
import time


PGBOUNCER_CONNECT_TIMEOUT = 3
PGBOUNCER_RESUME = "RESUME"
PGBOUNCER_PAUSE = "PAUSE"

PRIMARY_RE = re.compile("Masters: \[ (.*) \]")
SYNC_REPLICA_RE = re.compile(".*Node (.*):.*Postgresql-data-status.*"
                             "STREAMING\|SYNC.*", re.MULTILINE | re.DOTALL)
PGBOUNCERVIP_RE = re.compile(".*PgBouncerVIP.*Started (.*)")
POSTGRESQLVIP_RE = re.compile(".*PostgresqlVIP.*Started (.*)")


def run_as(username, cmd):
    sudo_cmd = shlex.split("sudo -u {} {}".format(username, cmd))
    with subprocess.Popen(sudo_cmd, stdout=subprocess.PIPE) as proc:
        try:
            stdout, stderr = proc.communicate(timeout=5)
            if proc.returncode != 0:
                raise Exception(stderr)
            return stdout.decode("utf-8")
        except subprocess.TimeoutExpired:
            proc.kill()
            stdout, stderr = proc.communicate()
            raise Exception("Process ran into its time limit")


def hostname():
    return platform.node()


def pgbouncer_cmd(cmd):
    pgbouncer_cmd = "psql -p 6432 postgresql://pgbouncer@/pgbouncer?connect_timeout={} -c {}".format(PGBOUNCER_CONNECT_TIMEOUT, cmd)
    return run_as("postgres", pgbouncer_cmd)


def cluster_cmd(cmd):
    return run_as("root", "crm {}".format(cmd))


def cluster_mon_cmd(cmd):
    return run_as("root", "crm_mon {}".format(cmd))


def get_cluster_sync_node():
    output = cluster_mon_cmd("-1 -Afr")
    m = SYNC_REPLICA_RE.search(output)
    # sync node will be the first one if there are more than one
    if m is not None:
        return m.group(1).strip()
    return None


def get_cluster_primary_node():
    output = cluster_mon_cmd("-1 -Afr")
    m = PRIMARY_RE.search(output)
    if m is not None:
        return m.group(1).strip()
    return None


def get_vip_node(vip_re):
    output = cluster_cmd("status")
    m = vip_re.search(output)
    if m is not None:
        return m.group(1).strip()
    return None


def wait_for_primary(node):
    while get_vip_node(POSTGRESQLVIP_RE) != node:
        time.sleep(0.1)


def migrate_primary(node):
    print("{} Migrating to node {}".format(datetime.datetime.now(), node))
    cluster_cmd("resource migrate msPostgresql {}".format(node))
    wait_for_primary(node)
    print("{} Migrated to node {}".format(datetime.datetime.now(), node))
    cluster_cmd("resource unmigrate msPostgresql")


def running_on_pgbouncer_vip():
    return get_vip_node(PGBOUNCERVIP_RE) == hostname()


def pgbouncer_active_state():
    return "active" in pgbouncer_cmd("'SHOW SERVERS'")


def wait_for_conn_flush():
    time_limit = 3
    start = time.time()

    while pgbouncer_active_state():
        if time.time()-start > time_limit:
            return False
        time.sleep(0.1)
    return True


if __name__ == '__main__':
    os.chdir("/tmp")
    sync_node = get_cluster_sync_node()

    # TODO(nlopes): this serves no purpose yet!
    migrate_force = False
    if len(sys.argv) == 2 and sys.argv[1] == '--force':
        migrate_force = True

    if sync_node is None:
        print("Could not find synchronous postgresql node")
        sys.exit(1)

    if not running_on_pgbouncer_vip():
        print("You must run this script on the node with the PgBouncerVIP: {}".
              format(get_vip_node(PGBOUNCERVIP_RE)))
        sys.exit(1)

    print("Make sure you have the following command ready in another window\n"
          " in the server where this script is running:\n\n"
          " sudo -u postgres psql -p 6432 -U pgbouncer pgbouncer -c 'RESUME'\n\n")

    if input("Will migrate the resource to node '{}'."
             "\nIs this correct? [y/N]".format(sync_node)).lower() == 'y':
        pgbouncer_cmd("PAUSE")
        try:
            wait_for_conn_flush() and migrate_primary(sync_node)
        except Exception as exc:
            print(exc)
        pgbouncer_cmd("RESUME")
