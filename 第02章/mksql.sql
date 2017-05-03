

/* 运行方法 
 假如mksql脚本位于windows环境下的d盘的根目录下
 sqlplus "/ as sysdba" @d:\mksql.sql
*/

create user hj identified by hj;
alter user hj default tablespace users;
grant dba to hj;

drop table hj.spoolsql_dba_objects purge;
create table hj.spoolsql_dba_objects as select * from dba_objects nologging;

drop table hj.spoolsql_dba_objects purge;
create global temporary table hj.spoolsql_dba_objects
on commit delete rows
as (select * from dba_objects where 1=2)
;

drop table hj.spoolsql_dba_users purge;
create table hj.spoolsql_dba_users as select * from dba_users nologging;

drop table hj.spoolsql_dba_segments purge;
create table hj.spoolsql_dba_segments as select * from dba_segments nologging;
begin
  for i in 1 .. 8 loop
    insert /*+ append */
    into hj.spoolsql_dba_segments
      select * from hj.spoolsql_dba_segments nologging;
    commit;
  end loop;
end;
/

create index hj.idx_spoolsql_dba_segments_name on hj.spoolsql_dba_segments(segment_name) nologging;

exec dbms_stats.gather_table_stats(ownname => 'HJ', tabname => 'spoolsql_dba_objects',cascade => true);
exec dbms_stats.gather_table_stats(ownname => 'HJ', tabname => 'spoolsql_dba_users',cascade => true);
exec dbms_stats.gather_table_stats(ownname => 'HJ', tabname => 'spoolsql_dba_segments',cascade => true);

set linesize 1000
set pagesize 3000
set trim on
set trimspool on

set autot traceonly statistics;
set timing on;

exec dbms_workload_repository.create_snapshot;

insert into hj.spoolsql_dba_objects select * from dba_objects nologging;

variable vbeginid number;
variable vendid number;

exec :vbeginid := 4900;
exec :vendid := 5000;

select t1.owner,
       t1.object_name,
       t1.subobject_name,
       t1.last_ddl_time,
       t2.user_id,
       t2.account_status,
       t3.segment_name,
       t3.partition_name,
       t3.bytes,
       t3.blocks
  from hj.spoolsql_dba_objects  t1,
       hj.spoolsql_dba_users    t2,
       hj.spoolsql_dba_segments t3
 where t1.owner = t2.username
   and t1.object_name = t3.segment_name
   and t1.object_id between :vbeginid and :vendid
;

exec :vbeginid := 1;
exec :vendid := 5000;

select t1.owner,
       t1.object_name,
       t1.subobject_name,
       t1.last_ddl_time,
       t2.user_id,
       t2.account_status,
       t3.segment_name,
       t3.partition_name,
       t3.bytes,
       t3.blocks
  from hj.spoolsql_dba_objects  t1,
       hj.spoolsql_dba_users    t2,
       hj.spoolsql_dba_segments t3
 where t1.owner = t2.username
   and t1.object_name = t3.segment_name
   and t1.object_id between :vbeginid and :vendid
;

exec :vbeginid := 1;
exec :vendid := 10000;

select t1.owner,
       t1.object_name,
       t1.subobject_name,
       t1.last_ddl_time,
       t2.user_id,
       t2.account_status,
       t3.segment_name,
       t3.partition_name,
       t3.bytes,
       t3.blocks
  from hj.spoolsql_dba_objects  t1,
       hj.spoolsql_dba_users    t2,
       hj.spoolsql_dba_segments t3
 where t1.owner = t2.username
   and t1.object_name = t3.segment_name
   and t1.object_id between :vbeginid and :vendid
;

exec :vbeginid := 4990;
exec :vendid := 5000;

select /*+ index(t3 idx_spoolsql_dba_segments_name) */
       t1.owner,
       t1.object_name,
       t1.subobject_name,
       t1.last_ddl_time,
       t2.user_id,
       t2.account_status,
       t3.segment_name,
       t3.partition_name,
       t3.bytes,
       t3.blocks
  from hj.spoolsql_dba_objects  t1,
       hj.spoolsql_dba_users    t2,
       hj.spoolsql_dba_segments t3
 where t1.owner = t2.username
   and t1.object_name = t3.segment_name
   and t1.object_id between :vbeginid and :vendid
;
exec :vbeginid := 1;
exec :vendid := 10000;

select /*+ no_index(t3) */
       t1.owner,
       t1.object_name,
       t1.subobject_name,
       t1.last_ddl_time,
       t2.user_id,
       t2.account_status,
       t3.segment_name,
       t3.partition_name,
       t3.bytes,
       t3.blocks
  from hj.spoolsql_dba_objects  t1,
       hj.spoolsql_dba_users    t2,
       hj.spoolsql_dba_segments t3
 where t1.owner = t2.username
   and t1.object_name = t3.segment_name
   and t1.object_id between :vbeginid and :vendid
;

exec dbms_workload_repository.create_snapshot;

alter index hj.idx_spoolsql_dba_segments_name unusable;

exec :vbeginid := 4900;
exec :vendid := 5000;

select t1.owner,
       t1.object_name,
       t1.subobject_name,
       t1.last_ddl_time,
       t2.user_id,
       t2.account_status,
       t3.segment_name,
       t3.partition_name,
       t3.bytes,
       t3.blocks
  from hj.spoolsql_dba_objects  t1,
       hj.spoolsql_dba_users    t2,
       hj.spoolsql_dba_segments t3
 where t1.owner = t2.username
   and t1.object_name = t3.segment_name
   and t1.object_id between :vbeginid and :vendid
;

set autot off;

variable v_dbid number;
variable v_inst_num number;
variable v_beginsnap number;
variable v_endsnap number;

begin
    with params as
     (select beginsnap, endsnap, dbid, instance_number
      from (select sum(decode(rn, 2, snap_id, 0)) beginsnap,
             sum(decode(rn, 1, snap_id, 0)) endsnap
          from (select snap_id,
                 row_number() over(order by end_interval_time desc) rn
              from dba_hist_snapshot)
           where rn < 3) t1,
         (select dbid from v$database where rownum = 1) t2,
         (select instance_number from v$instance where rownum = 1) t3)
    select dbid, instance_number, beginsnap, endsnap
	  into :v_dbid, :v_inst_num, :v_beginsnap, :v_endsnap
	  from params;
end;
/

col module format a30
col text format a30

select *
  from (select sqt.sql_id,
               to_char(nvl((round(sqt.elap / 1000000, 3)), to_number(null)),
                       '9999990.999') elapsed,
               to_char(nvl((round(sqt.cput / 1000000, 3)), to_number(null)),
                       '9999990.999') cputime,
               sqt.exec execs,
               to_char(decode(sqt.exec,
                              0,
                              to_number(null),
                              round(sqt.elap / sqt.exec / 1000000, 3)),
                       '9999990.999') "elapsed/exec",
               to_char(decode(dbt.dbtime,
                              0,
                              100,
                              100 * (sqt.elap / 10000 / dbt.dbtime)),
                       '9999990.999') "%DB time",
               nvl(sqt.module, '') module,
               decode(dbms_lob.substr(st.sql_text, 100,1),
                      null,
                      '**********************',
					  '',
					  '**********************',
                      substr(st.sql_text, 1, 50)) sqltxt
          from (select sql_id,
                       max(module) module,
                       sum(elapsed_time_delta) elap,
                       sum(cpu_time_delta) cput,
                       sum(executions_delta) exec
                  from dba_hist_sqlstat
                 where dbid = :v_dbid
                   and instance_number = :v_inst_num
                   and :v_beginsnap < snap_id
                   and snap_id <= :v_endsnap
                 group by sql_id) sqt,
               dba_hist_sqltext st,
               (SELECT nvl(sum(e.VALUE) - sum(b.value), 0) dbtime
                  FROM DBA_HIST_SYSSTAT b, DBA_HIST_SYSSTAT e
                 WHERE B.SNAP_ID = :v_beginsnap
                   AND E.SNAP_ID = :v_endsnap
                   AND B.DBID = :v_dbid
                   AND E.DBID = B.DBID
                   AND B.INSTANCE_NUMBER = :v_inst_num
                   AND E.INSTANCE_NUMBER = B.INSTANCE_NUMBER
                   and e.STAT_NAME = 'DB time'
                   and b.stat_name = 'DB time') dbt
         where st.sql_id(+) = sqt.sql_id
           and st.dbid(+) = :v_dbid
         order by nvl(sqt.elap, -1) desc, sqt.sql_id)
 where rownum < 10;

col username format a15
col event format a30
col sql_txt format a50

select c.USERNAME, a.event, a.cnt as "TIME(SECOND)", a.sql_id, substr(b.SQL_TEXT,1,50) sql_txt
  from (select rownum rn, t.*
          from (select decode(s.session_state,
                              'WAITING',
                              s.event,
                              'Cpu + Wait For Cpu') Event,
                       s.sql_id,
                       s.user_id,
                       count(*) CNT
                  from v$active_session_history s
                 where sample_time > sysdate - 15 / 1440
                 group by s.user_id,
                          decode(s.session_state,
                                 'WAITING',
                                 s.event,
                                 'Cpu + Wait For Cpu'),
                          s.sql_id
                 order by CNT desc) t
         where rownum < 20) a,
       v$sqlarea b,
       dba_users c
 where a.sql_id = b.sql_id
   and a.user_id = c.user_id
 order by CNT desc
;

exit
