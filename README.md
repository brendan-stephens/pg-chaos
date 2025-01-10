# pg-chaos

**Tips and scripts to test the resilliency of a Postgres service.**<br>
As we are intentially trying to crash the service, for the purpsoes of testing, use the lightest machine possible. 

***There's no need to wait for a TB of disk to fill, if you can emulate with a GB.***

## Disk Full
**Failure Scenario:**<br>
Insufficient disk space prevents PostgreSQL from writing new data or creating temporary files.

**Emulation:** 
* **disk_full.sql**
  * Using `generate_series()`
  * 30M rows generates ~1GB table
  * Tables can be `TEMP` or persisted
* **pgbench**
  * Executing `pgbench --initialize --quiet --scale 100 --unlogged -I dtg --fillfactor 10 $DB`
  * 1 `scaling factor` = 100k rows
  * Calucate size via [formula](https://www.cybertec-postgresql.com/en/a-formula-to-calculate-pgbench-scaling-factor-for-target-db-size/)
  * Explicitly set the data generation [steps](https://www.postgresql.org/docs/current/pgbench.html#PGBENCH-INIT-OPTIONS)

**Aiven Handling**:<br>
Service will move to read-only at the high-watermark.<br>
The serivice can be returned to read-write for maintenance. 

```
[postgresql-16][29-1] pid=82,user=,db=,app=,client= LOG: parameter "default_transaction_read_only" changed to "on"
...
[postgresql-16][31-1] pid=82,user=,db=,app=,client= LOG: parameter "default_transaction_read_only" changed to "off"
```


## Out of Memory (OOM)
**Failure Scenario:**<br>
Queries or background processes consume excessive memory, causing the OS to terminate PostgreSQL.

**Emulation:**<br>
* **out_of_memory.sql**<br>
  * **work_mem:**<br>
  Maximize `work_mem`, ensuring PostgreSQL keeps intermediate results in memory.
  * **WITH RECURSIVE:**<br>
  Creates a recursive CTE that builds a large in-memory array structure.
  Each iteration appends to the data array, consuming more memory.
  * **pg_sleep(5):**<br>
  Delays the final result, allowing you to monitor the memory usage in real-time.
  * **COUNT(*):**
  Ensures the recursive CTE is fully evaluated.

**Aiven Handling**:<br>
Early OOM Detection will kill the process in the container before the OS hits OOM Killer. See: [Out of Memory Conditions](https://github.com/aiven/aiven-docs/blob/main/docs/platform/concepts/out-of-memory-conditions.md)

```
earlyoom: low memory! at or below SIGTERM limits: mem 10.00%, swap  4.00%                                  
earlyoom: mem avail:    31 of  1960 MiB ( 1.63%), swap free:   94 of 2455 MiB ( 3.84%)
earlyoom: escalating to SIGKILL after 0.5 seconds

postgresql-16: [32-1] pid=82,user=,db=,app=,client= LOG:  server process (PID 64684) was terminated by signal 9: Killed
```

## High CPU Usage
**Failure Scenario:** CPU-intensive queries or other Emulationes starve PostgreSQL of CPU resources.

**Emulation:** <br>
Queries can be executed in parallel, by multiple clients, for a computational high intesity.

* **high_put.sql**
  * **max_parallel_workers_per_gather:**<br>
  Configures the number of workers PostgreSQL can use for parallel execution.
  * **generate_series(1, 1e8):**<br>
  Generates a large series of numbers to process.
  Adjust the upper limit (1e8) to control the workload.
  Can be processed in parallel, distributing the workload across CPU cores.
  * **SQRT and LOG:**<br>
  Apply computationally expensive mathematical functions to each value in the series.
  * **SUM:**<br>
  Aggregates the results, further increasing CPU utilization.

**Aiven Handling**:<br>
The service exists in a container, with a constrained CPU quota of `90%`, ensuring there is always overhead remaining for platform orchestration. 

* Warning: `Load15 on service is at least 5 times the cpu count`
* Critical: `Load15 on service is at least 15 times the cpu count`

## Network Partition (existing sabotage)
**Failure Scenario:**<br>
A node loses connectivity to other nodes or clients.

**Emulation:**<br>
Use iptables to block or drop network traffic:<br>
`iptables -A INPUT -p tcp --dport 5432 -j DROP`

**Aiven Handling**:<br>
When a server unexpectedly disconnects, there is no certain way to know whether it really disappeared or whether there is a temporary glitch in the cloud provider's network. Aiven's management platform has different procedures in case of primary or replica nodes disconnections.

See: [Uncontrolled primary/replica disconnection](https://github.com/aiven/aiven-docs/blob/main/docs/products/postgresql/concepts/upgrade-failover.md?plain=1#L26)


## Postmaster Crash
**Failure Scenario:**<br>
Postmaster or child crashes due to a bug, misconfiguration, user termination or out-of-memory condition.

**Emulation:**<br>
Kill the Postgres service: `kill -9 $(pgrep postgres)`.<br>

**Aiven Handling**:<br>
We will restart the container process.<br>
Note that node monitor for `RUNNING` state and `pglookout` still apply.<br>
A node with service that does not return to expected state within thresholds will be replaced. 

```
postgresql-16: [36-1] pid=64817,user=postgres,db=_aiven,app=[unknown],client=[local] FATAL:  the database system is in recovery mode

InstanceManager       InstanceManager ERROR     Unexpected exception: Failed check, took 6.12s. Sleeping for 2.00s.

postgresql-16: [35-1] pid=64814,user=,db=,app=,client= LOG:  checkpoint starting: end-of-recovery immediate wait

postgresql-16: [35-1] pid=82,user=,db=,app=,client= LOG:  database system is ready to accept connections
```

## Logical Replication or Streaming Replication Breakage

**Failure Scenario:**<br>
Replication fails due to missing WAL files or network issues.

**Emulation:**<br>
* **Replication Lag**
  * **Logical Replication:**<br>
    * `ALTER SUBSCRIPTION <subscription_name> DISABLE;`
  * **Streaming Replication:**<br>
    * Using `pg_hba.conf`, comment out or modify the replication entry for the replica's IP.
* **WAL Corruption**
  * Identify and remove a WAL pending synchronization:
  * `SELECT * FROM pg_stat_replication;`
  * `rm -f /path/to/primary/data/pg_wal/<wal_file_name>`  

**Aiven Handling**:<br>
[pglookout](https://github.com/Aiven-Open/pglookout) is a PostgreSQL® replication monitoring and failover daemon. pglookout monitors PG database nodes and their replication status and acts according to that status, for example calling a predefined failover command to promote a new primary in case the previous one goes missing.<br>

The `max_failover_replication_time_lag` setting monitors lag after which `failover_command` will be executed.<br>

PGLookout, determines which of the standby nodes is the furthest along in replication (has the least potential for data loss) and does a controlled failover to that node.

## File Corruption
**Failure Scenario:**<br>
Relational data files become corrupted due to disk issues or faulty hardware.

**Emulation:**<br>
Manually edit or delete files in the data directory.

**Aiven Handling**:<br>
Errors will appear in postgres when attempting to read the file.

Example Errors:
```
WARNING: page verification failed, calculated checksum 20919 but expected 15254

ERROR: invalid page in block 4565901 of relation base/16427/837074

FATAL: relation mapping file "base/16427/pg_filenode.map" contains invalid data
```

The relfiles follow a path based on the `oid` for the database in `pg_database`...

```
defaultdb=> select oid,datname from pg_database where oid = '16427';
  oid  |  datname
-------+-----------
 16427 | defaultdb
(1 row)
```

And the `relfilenode` for the object in `pg_class`:

```
defaultdb=> select oid, relname, relfilenode
from pg_class where relfilenode = '837074';
  oid   |     relname      | relfilenode
--------+------------------+-------------
 837074 | pgbench_accounts |      837074
(1 row)
```

In most instances, it will be advisable to fail over to a replica.<br>
However, depending on the situation, it may also be possible to:
* `DROP` the object
* `REINDEX` a corrupted index
* `VACUUM` damaged pages
* Use PITR and export/import the corrupted data range
