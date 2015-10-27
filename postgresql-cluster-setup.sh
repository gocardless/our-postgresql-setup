#!/bin/bash

PG01="172.28.33.11"
PG02="172.28.33.12"
PG03="172.28.33.13"

POSTGRESQL_VERSION=9.4

function setup_ssh_keys() {
    cp -rp /vagrant/.ssh/* /root/.ssh
    cp -rp /root/.ssh/id_rsa.pub /root/.ssh/authorized_keys
    chmod 700 /root/.ssh
    chmod 600 /root/.ssh/id_rsa
    chmod 644 /root/.ssh/id_rsa.pub
    chown -R root /root/.ssh
    chgrp -R root /root/.ssh
}

function setup_pgbouncer() {
    apt-get -y install pgbouncer=1.5.4-4

    cat > /etc/pgbouncer/pgbouncer.ini <<EOF
[databases]
postgres = host=172.28.33.10 pool_size=6
template1 = host=172.28.33.10 pool_size=6

[pgbouncer]
logfile = /var/log/postgresql/pgbouncer.log
pidfile = /var/run/postgresql/pgbouncer.pid
listen_addr = *
listen_port = 6432
unix_socket_dir = /var/run/postgresql
auth_type = trust
auth_file = /etc/pgbouncer/userlist.txt
admin_users = postgres
stats_users =
pool_mode = transaction
server_reset_query =
server_check_query = select 1
server_check_delay = 10
max_client_conn = 1000
default_pool_size = 12
reserve_pool_size = 5
log_connections = 1
log_disconnections = 1
log_pooler_errors = 1
EOF

    cat > /etc/pgbouncer/userlist.txt <<EOF
"postgres" "whatever_we_trust"
EOF

    cat > /etc/default/pgbouncer <<EOF
START=1
EOF
    service pgbouncer start
}

function setup_fresh_postgresql() {
    su -s /bin/bash -c "/usr/lib/postgresql/${POSTGRESQL_VERSION}/bin/initdb -D /var/lib/postgresql/${POSTGRESQL_VERSION}/main -E utf-8" postgres

    # start postgresql to set things up before copying
    service postgresql start
    service postgresql stop

    rsync -avz -e 'ssh -oStrictHostKeyChecking=no' /var/lib/postgresql/${POSTGRESQL_VERSION}/main/ $PG02:/var/lib/postgresql/${POSTGRESQL_VERSION}/main
    rsync -avz -e 'ssh -oStrictHostKeyChecking=no' /var/lib/postgresql/${POSTGRESQL_VERSION}/main/ $PG03:/var/lib/postgresql/${POSTGRESQL_VERSION}/main
}

function setup_postgresql_repo() {
    # Setup postgresql repo
    echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list

    # Setup postgresql repo key
    apt-get -y install wget ca-certificates
    wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -

    # Update package info
    apt-get update
    # Upgrade all the (safe) packages to start from a clean slate
    apt-get -y upgrade
}


function setup_postgresql() {
    # Install postgresql
    apt-get -y install postgresql-${POSTGRESQL_VERSION}

    # disable postgresql from auto starting
    update-rc.d -f postgresql remove

    service postgresql stop

    cat > /etc/postgresql/${POSTGRESQL_VERSION}/main/pg_hba.conf <<EOF
    local   all             postgres                                peer

    # TYPE  DATABASE        USER            ADDRESS                 METHOD

    # "local" is for Unix domain socket connections only
    local   all             all                                     peer
    # IPv4 local connections:
    host    all             all             127.0.0.1/32            md5
    # IPv6 local connections:
    host    all             all             ::1/128                 md5
    # Allow replication connections from localhost, by a user with the
    # replication privilege.
    #local   replication     postgres                                peer
    #host    replication     postgres        127.0.0.1/32            md5
    host    replication     postgres        ::1/128                 md5
    hostssl    replication     postgres 172.28.33.11/32                 trust
    hostssl    replication     postgres 172.28.33.12/32                 trust
    hostssl    replication     postgres 172.28.33.13/32                 trust
    # for user connections
    host       all     postgres 172.28.33.1/32                 trust
    hostssl    all     postgres 172.28.33.1/32                 trust
    # for pgbouncer
    host       all     postgres 172.28.33.10/32                 trust
    hostssl    all     postgres 172.28.33.10/32                 trust
EOF

    cat > /etc/postgresql/${POSTGRESQL_VERSION}/main/postgresql.conf <<EOF
archive_command = 'cd .'
archive_mode = 'on'
autovacuum = 'on'
checkpoint_completion_target = 0.6
checkpoint_segments = 10
checkpoint_warning = 300
data_directory = '/var/lib/postgresql/${POSTGRESQL_VERSION}/main'
datestyle = 'iso, mdy'
default_text_search_config = 'pg_catalog.english'
effective_cache_size = '128MB'
external_pid_file = '/var/run/postgresql/${POSTGRESQL_VERSION}-main.pid'
hba_file = '/etc/postgresql/${POSTGRESQL_VERSION}/main/pg_hba.conf'
hot_standby = 'on'
ident_file = '/etc/postgresql/${POSTGRESQL_VERSION}/main/pg_ident.conf'
include_if_exists = 'repmgr_lib.conf'
lc_messages = 'C'
listen_addresses = '*'
log_autovacuum_min_duration = 0
log_checkpoints = 'on'
logging_collector = 'on'
log_filename = 'postgresql.log'
log_connections = 'on'
log_directory = '/var/log/postgresql'
log_disconnections = 'on'
log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a '
log_lock_waits = 'on'
log_min_duration_statement = 500
log_temp_files = 0
maintenance_work_mem = '128MB'
max_connections = 100
max_wal_senders = 5
port = 5432
shared_buffers = '128MB'
shared_preload_libraries = 'pg_stat_statements'
ssl = on
ssl_cert_file = '/etc/ssl/certs/ssl-cert-snakeoil.pem'
ssl_key_file = '/etc/ssl/private/ssl-cert-snakeoil.key'
unix_socket_directories = '/var/run/postgresql'
wal_buffers = '8MB'
wal_keep_segments = '200'
wal_level = 'hot_standby'
work_mem = '128MB'
EOF

    # we will recreate this later in preparation for pacemaker
    rm -rf /var/lib/postgresql/${POSTGRESQL_VERSION}/main/
}

function setup_cluster() {
    # Install cluster packages
    apt-get -y install corosync pacemaker

    # Setup corosync config
    cp /vagrant/corosync/corosync.conf /etc/corosync/corosync.conf
    cp /vagrant/corosync/authkey /etc/corosync/authkey

    # Make sure corosync can start
    cat > /etc/default/corosync <<EOF
START=yes
EOF

    # Make sure pacemaker is setup
    cat > /etc/corosync/service.d/pacemaker <<EOF
service {
    name: pacemaker
    ver: 1
}
EOF

    # start corosync / pacemaker
    service corosync start
    # TODO: check output of corosync-cfgtool -s says "no faults"
    service pacemaker start
}

function build_cluster() {
    printf "Waiting for cluster to have quorum"
    while [ -z "$(crm status | grep '3 Nodes configured')" ]; do
        sleep 1
        printf "."
    done
    echo " done"

    # setup new postgresql instance that is exactly the same in all boxes
    setup_fresh_postgresql

    # TODO: primitive pgbouncerVIP ocf:heartbeat:IPaddr2 params ip=172.28.33.9 cidr_netmask=32 op monitor interval=5s

    cat <<EOF | crm configure
property stonith-enabled=false
primitive PostgresqlVIP ocf:heartbeat:IPaddr2 params ip=172.28.33.10 cidr_netmask=32 op monitor interval=5s
primitive Postgresql ocf:heartbeat:pgsql \
    params pgctl="/usr/lib/postgresql/${POSTGRESQL_VERSION}/bin/pg_ctl" psql="/usr/bin/psql" pgdata="/var/lib/postgresql/${POSTGRESQL_VERSION}/main/" start_opt="-p 5432" rep_mode="sync" node_list="pg01 pg02 pg03" primary_conninfo_opt="keepalives_idle=60 keepalives_interval=5 keepalives_count=5" master_ip="172.28.33.10" repuser="postgres" tmpdir="/var/lib/postgresql/${POSTGRESQL_VERSION}/tmp" config="/etc/postgresql/${POSTGRESQL_VERSION}/main/postgresql.conf" logfile="/var/log/postgresql/postgresql-crm.log" restore_command="cp /data/archive/%f %p" \
    op start timeout="60s" interval="0s" on-fail="restart" \
    op monitor timeout="60s" interval="4s" on-fail="restart" \
    op monitor timeout="60s" interval="3s" on-fail="restart" role="Master" \
    op promote timeout="60s" interval="0s" on-fail="restart" \
    op demote timeout="60s" interval="0s" on-fail="stop" \
    op stop timeout="60s" interval="0s" on-fail="block" \
    op notify timeout="60s" interval="0s"
ms msPostgresql Postgresql params master-max=1 master-node-max=1 clone-max=3 clone-node-max=1 notify=true
colocation vip-with-master inf: PostgresqlVIP msPostgresql:Master
order start-vip-after-postgres inf: msPostgresql:promote PostgresqlVIP:start symmetrical=false
order stop-vip-after-postgres 0: msPostgresql:demote PostgresqlVIP:stop symmetrical=false
commit
end
EOF
}

if [ ! -f /root/.ssh/id_rsa ]; then
    setup_ssh_keys
fi

if [ ! -f /etc/apt/sources.list.d/pgdg.list ]; then
    setup_postgresql_repo
fi

if [ ! -f /etc/postgresql/${POSTGRESQL_VERSION}/main/postgresql.conf ]; then
    setup_postgresql
fi

if [ ! -f /etc/pgbouncer/pgbouncer.ini ]; then
    setup_pgbouncer
fi

if [ ! -f /etc/corosync/corosync.conf ]; then
    setup_cluster
fi

# we only build the cluster on one of the nodes
if [ "$(hostname)" == "pg01" ]; then
    # TODO: don't run this if we already have a cluster formed
    build_cluster
fi
