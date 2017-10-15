our-postgresql-setup
====================

# Overview

This repo is an extracted version of how we run PostgreSQL clusters at GoCardless.

It helps you quickly spin up a 3-node cluster of PostgreSQL, managed by Pacemaker, and proxied by PgBouncer.

It's intended as a playground for us, and a learning resource that we wanted to share with the community.

You can hear more about how the cluster works in our talk - [Zero-downtime Postgres upgrades](https://www.youtube.com/watch?v=SAkNBiZzEX8).

# What's in the cluster?

When you start the cluster, you get 3 nodes, each running:

  - PostgreSQL
  - Pacemaker
  - PgBouncer

All packages are from Ubuntu 14.04, except for PostgreSQL itself, which is at version 9.4.

The cluster is configured with a single primary, one synchronous replica, and one asynchronous replica.

# Dependencies
1. [Virtualbox](https://www.virtualbox.org/wiki/Downloads)
2. [Vagrant](http://www.vagrantup.com/downloads.html)
3. ` git clone https://github.com/gocardless/our-postgresql-setup.git`
4. [Recommended] [tmux](https://tmux.github.io)

# Getting started

## With tmux (recommended)
1.  `./tmux-session.sh start`

## By hand
1.  On 3 separate windows:
2.  `vagrant up pg01 && vagrant ssh pg01`
3.  `vagrant up pg02 && vagrant ssh pg02`
4.  `vagrant up pg03 && vagrant ssh pg03`

# Viewing cluster status

You can run `crm_mon -Afr` on any node to see the current state of the cluster and all resources in it. Press `^c` to quit.

# Connecting to PostgreSQL

Once the cluster is up, you have two options:

  - Connect directly to Postgres on the PostgresqlVIP at 172.28.33.10
  - Connect via PgBouncer at 172.28.33.9

*Note*: The migrator.py script will only give you zero-downtime migrations if you connect via PgBouncer.

# Running a zero-downtime migration

1. Ensure clients are connected to the PgBouncerVIP.
2. Run `/vagrant/migrator.py` on the node that has the PgBouncerVIP (you can find out where the PgBouncerVIP is by viewing the cluster status).
3. Follow the prompts.
    1. It is safe to ignore the `Make sure you have the following command ready...` prompt. This is aimed at cases where you'd want to quickly re-enable traffic, and doesn't matter when running locally.
4. Assuming everything went well, the primary will migrate to the synchronous replica, and the clients won't have received any connection resets.

# I have a question!

We're happy to receive questions as issues on this repo, so don't be shy!

It's hard to know exactly what documentation/guidance is useful to people, so we'll use the questions we answer to improve this README and link out to more places you can read up on the technologies we're using.

# Further reading
* [Pacemaker CRM shell Quick Reference](https://github.com/ClusterLabs/pacemaker/blob/master/doc/pcs-crmsh-quick-ref.md)

# References
* [PostgreSQL](https://www.postgresql.org)
* [tmux](https://tmux.github.io)
* [Vagrant](http://vagrantup.com)
* [VirtualBox](http://www.virtualbox.org)
