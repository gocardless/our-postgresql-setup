postgresql-cluster-testing
==========================

# Purpose
Set up 3 virtual machines running a corosync/pacemaker cluster with postgresql running in `sync` mode.
The Postgresql VIP is at 172.28.33.10. pgBouncer connects to that VIP.

This is useful to test doing maintenance operations on the cluster. We don't present a pgBouncer VIP as the first
iteration of the tool will be to test adding a VIP to pgBouncer and trying to rebalance the cluster.

# Dependencies
1. [Virtualbox](https://www.virtualbox.org/wiki/Downloads)
2. [Vagrant](http://www.vagrantup.com/downloads.html)
3. ``` git clone https://github.com/gocardless/psql-cluster-testing.git ```
4. [Optional] [tmux](https://tmux.github.io)

# Getting started
1.  On 3 separate windows:
2.  ``` vagrant up pg01 ```
3.  ``` vagrant up pg02 ```
4.  ``` vagrant up pg03 ```
5. [Optional] Assuming you have pgbench, you can run it against 172.28.33.10 on port 6432.
or
1.  ``` ./tmux-session.sh start ```

# Further reading
* [Pacemaker CRM shell Quick Reference](https://github.com/ClusterLabs/pacemaker/blob/master/doc/pcs-crmsh-quick-ref.md)

# References
* [PostgreSQL](https://www.postgresql.org)
* [tmux](https://tmux.github.io)
* [Vagrant](http://vagrantup.com)
* [VirtualBox](http://www.virtualbox.org)
