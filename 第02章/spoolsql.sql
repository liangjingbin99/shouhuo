

set term off
set termout off
set heading on
set feedback off
set verify off
set echo off


/*
功能说明：
   输入SQL_ID、spool路径。
   输出与SQL相关的信息，spool到指定文件。
*/

set term on
set termout on
set heading off
set feedback off
set verify off
set echo off

SET markup html off spool ON pre off entmap off

set define ^
var sqlid varchar2(50);
var outputdir varchar2(256);
prompt "input sqlid:"
define tmp_sqlid=^SQL_ID
exec :sqlid := '^tmp_sqlid'
column outputdir_sqlid new_value outputfile
select './'||:sqlid||'.html' as outputdir_sqlid from dual;

SET markup html off spool ON pre off entmap off

set term off
set termout off
set heading off
set feedback off
set verify off
set trimspool on
set trim on
set echo off

set linesize 32767
set pagesize 999999
set serveroutput on

spool ^^outputfile
declare
  type refcursor is ref cursor;
  vCur          refcursor;
  vsqlid        varchar2(4000) := :sqlid;
  vOwnerstr     varchar2(32767) := '';
  vOwnerCnt     number(3) := 0;
  vTableStr     varchar2(32767) := '';
  vTableCnt     number(3) := 0;
  vtmpchldnum   number;
  vtmpplnval    number;
  type VARCHARTAB is table of varchar2(32767) index by BINARY_INTEGER;
  vPlanAddition VARCHARTAB;
  arr_iter BINARY_INTEGER;
  vsqltxt_c clob;
  vsqltxt_a dbms_sql.varchar2a;
  vsqltxt_lb number(1):= 0;
  vsqltxt_le number(12);
  vsqlcur number;
  vsqlmsg varchar2(4000);
begin
  ----打开服务器output
  dbms_output.enable(10000000000000);
  
  ----打印html头和样式
  dbms_output.put_line('<html><title>Reports About SQL:'||vsqlid||'</title><head>');
  dbms_output.put_line('<style>');
  
  dbms_output.put_line('th {font:bold 8pt Arial,Helvetica,Geneva,sans-serif; color:White; background:#0066CC;padding-left:4px; padding-right:4px;padding-bottom:2px}');
  dbms_output.put_line('tr   {font:10pt SimSun,SimSun,SimSun,SimSun;}');
  dbms_output.put_line('td   {border:1px solid; font:10pt SimSun,SimSun,SimSun,SimSun;}');
  dbms_output.put_line('</style>');
  dbms_output.put_line('</head><body>');

  ----获取SQL文本
  dbms_output.put_line('<b>sql_text</b><br>');
  dbms_output.put_line('<table><tr><td>');
  select sqtxt
    into vsqltxt_c
    from (select sql_text sqtxt
            from dba_hist_sqltext
           where sql_id = vsqlid
          union all
          select sql_fulltext sqtxt from v$sqlarea where sql_id = vsqlid)
   where rownum = 1;
  vsqltxt_a.delete;
  vsqltxt_le := DBMS_LOB.GETLENGTH(vsqltxt_c) / 2000 + 1;
  for i in 1 .. vsqltxt_le loop
	vsqltxt_a(i) := substr(vsqltxt_c, 1900 * (i - 1) + 1, 1900);
    dbms_output.put_line(vsqltxt_a(i));
  end loop;
  dbms_output.put_line('</td></tr></table>');
  dbms_output.put_line('<br>');
  
  ----获取执行计划--explain plan for
  dbms_output.put_line('<b>explain plan for</b><table>');
  for v in (select distinct parsing_schema_name from dba_hist_sqlstat where sql_id = vsqlid) loop
    dbms_output.put_line('<tr><td><pre>');
    begin
	  execute immediate 'alter session set current_schema='||v.parsing_schema_name;
      vsqlcur := dbms_sql.open_cursor;
      vsqltxt_a(0) := 'explain plan for ';
      dbms_sql.parse(vsqlcur, vsqltxt_a, vsqltxt_lb, vsqltxt_le, false, dbms_sql.native);
      vsqltxt_le := dbms_sql.execute(vsqlcur);
      for v_in in (select plan_table_output as planline from table(dbms_xplan.display)) loop
        dbms_output.put_line(v_in.planline);
      end loop;
      dbms_sql.close_cursor(vsqlcur);
      exception
        when others then
	  	vsqlmsg := sqlerrm;
          dbms_output.put_line(vsqlmsg);
    end;
    dbms_output.put_line('</pre></td></tr>');
  end loop;
  dbms_output.put_line('</table>');
  dbms_output.put_line('<br>');

  ----获取执行计划--V$SQLPLAN
  dbms_output.put_line('<b>Execution Plan From V$SQLPLAN</b><br>');
  for hashval in (select distinct plan_hash_value from v$sql_plan where sql_id = vsqlid) loop
    dbms_output.put_line('SQL:'||vsqlid||', PLAN_HASH_VALUE:'||hashval.plan_hash_value);
    dbms_output.put_line('<table>');
    dbms_output.put_line('<tr><th>ID</th><th>DEP</th><th width="400px">OPERITION</th><th>NAME</th><th>ROWS</th><th>BYTES</th><th>COST(%CPU)</th><th>IO_COST</th><th>TIME</th></tr>');
    vPlanAddition.delete;
    arr_iter := 0;
    for v in (select decode(trim(predicates), '', '' || ID, '*' || ID) ID,
                     DEPTH,
                     OPERATION,
                     NAME,
                     PREDICATES,
                     "ROWS",
                     BYTES,
                     "COST(%CPU)",
                     IO_COST,
                     TIME
                from (select a.plan_hash_value || ' ' plan_hash_value,
               id ID,
               depth DEPTH,
               lpad(operation, length(operation) + depth * 6, '&nbsp;') || ' ' || options OPERATION,
               decode(OBJECT_NAME,
                  null,
                  '',
                  '[' || OBJECT_TYPE || ']' || OBJECT_OWNER || '.' ||
                  OBJECT_NAME) || '&nbsp;' NAME,
               case
               when (length(access_predicates) < 3 or access_predicates is null) then
                case
                when (length(filter_predicates) < 3 or filter_predicates is null) then
                 ' '
                else
                 '[filter]' || substr(filter_predicates, 1, 3990)
                end
               else
                '[access]' || substr(access_predicates, 1, 3990)
               end PREDICATES,
               decode(cardinality, null, '', cardinality) || '&nbsp;' "ROWS",
               decode(Bytes, null, '', Bytes) || '&nbsp;' BYTES,
               decode(io_cost,
                  null,
                  decode(cost, null, '', cost),
                  decode(cost, null, '', cost) || '(' ||
                  decode(cost, 0, 0, round((cost - io_cost) / cost * 100)) || ')') || '&nbsp;' "COST(%CPU)",
               --decode(cpu_cost, null, '', cpu_cost) || ' ' CPU_COST,
               decode(io_cost, null, '', io_cost) || ' ' IO_COST,
               trim(to_char(round(nvl(time, 0) / 3600), '00')) || ':' ||
               to_char(to_date('19000101', 'yyyymmdd') + nvl(time, 0) / 3600 / 24,
                   'mi:ss') TIME
            from v$sql_plan a,
               (select plan_hash_value, max(child_number) child_number, sql_id
                from v$sql_plan
               where sql_id = vsqlid
               group by sql_id, plan_hash_value) b
           where a.sql_id = b.sql_id
             and a.plan_hash_value = b.plan_hash_value
             and a.plan_hash_value = hashval.plan_hash_value
             and a.child_number = b.child_number
           order by a.plan_hash_value, id asc
          )) loop
		arr_iter := arr_iter+1;
        vPlanAddition(arr_iter) := case when trim(v.predicates)||' ' = ' ' then '' 
            else v.id||' => '||v.predicates || '<br>' end;
        dbms_output.put_line('<tr><td>' || v.ID || '</td><td>' || v.DEPTH ||
                             '</td><td width="400px">' || v.OPERATION || 
               '</td><td>'|| v.NAME || '</td><td>' || v."ROWS" ||
                              '</td><td>' || v.BYTES || '</td><td>' || v."COST(%CPU)" ||
                               '</td><td>' || v.IO_COST || '</td><td>' || v.TIME || '</td></tr>');
    end loop;
    dbms_output.put_line('</table><br>');
    dbms_output.put_line('<p style="font:10pt SimSun,SimSun,SimSun,SimSun">');
    dbms_output.put_line('Predicate Information (identified by operation id):<br>');
    dbms_output.put_line('---------------------------------------------------------------------------<br>');
    arr_iter := 0;
    for v1 in 1..vPlanAddition.count loop
      arr_iter := arr_iter+1;
      dbms_output.put_line(vPlanAddition(arr_iter));
     end loop;
     dbms_output.put_line('<p>');
  end loop;
  dbms_output.put_line('<br>');
  
  ----SQL统计信息（SQL STATISTICS - V$SQLSTATS)
  dbms_output.put_line('<b>SQL STATISTICS- V$SQLPLAN</b>');
  dbms_output.put_line('<table><tr><th>ID</th><th>HASH</th><th>DB_TIME</th><th>MEM</th><th>VERS</th><th>EXES</th><th>DISKS</th><th>GETS</th><th>ROWS</th><th>CPU</th><th>ELAPSED</th><th>CLUSTER_WAIT</th><th>CONCURRENCE_WAIT</th></tr>');
  for v in (select mem.SQL_ID "ID",
         mem.PLAN_HASH_VALUE "HASH",
         mem_dbtime.VAL DB_TIME,
         mem.SHARABLE_MEM MEM,
         mem.VERSION_COUNT VERS,
         mem.EXECUTIONS EXES,
         mem.PARSE_CALLS PARSE_CALLS,
         mem.DISK_READS "DISKS",
         mem.BUFFER_GETS GETS,
         mem.ROWS_PROCESSED "ROWS",
         mem.CPU_TIME "CPU",
         mem.ELAPSED_TIME ELAPSED,
         mem.CLWAIT CLUSTER_WAIT,
         mem.CCWAIT CONCURRENCE_WAIT
      from (select SQL_ID,
             PLAN_HASH_VALUE,
             SHARABLE_MEM,
             VERSION_COUNT,
             FETCHES,
             END_OF_FETCH_COUNT,
             SORTS,
             EXECUTIONS,
             PX_SERVERS_EXECUTIONS PX_SERVERS_EXECS,
             LOADS,
             INVALIDATIONS,
             PARSE_CALLS,
             DISK_READS,
             BUFFER_GETS,
             ROWS_PROCESSED,
             CPU_TIME,
             ELAPSED_TIME,
             CLUSTER_WAIT_TIME     CLWAIT,
             APPLICATION_WAIT_TIME APWAIT,
             CONCURRENCY_WAIT_TIME CCWAIT,
             DIRECT_WRITES,
             PLSQL_EXEC_TIME       PLSEXEC_TIME,
             JAVA_EXEC_TIME        JAVEXEC_TIME
          from v$sqlstats
         where sql_id = vsqlid) mem,(select sum(value) val from v$sysstat where name = 'DB time') mem_dbtime
      ) loop
    dbms_output.put_line('<tr>');
  dbms_output.put_line('<td>'||v."ID"||'</td>');
  dbms_output.put_line('<td>'||v."HASH"||'</td>');
  dbms_output.put_line('<td>'||v.DB_TIME||'</td>');
  dbms_output.put_line('<td>'||v.MEM||'</td>');
  dbms_output.put_line('<td>'||v.VERS||'</td>');
  dbms_output.put_line('<td>'||v.EXES||'</td>');
  dbms_output.put_line('<td>'||v."DISKS"||'</td>');
  dbms_output.put_line('<td>'||v.GETS||'</td>');
  dbms_output.put_line('<td>'||v."ROWS"||'</td>');
  dbms_output.put_line('<td>'||v."CPU"||'</td>');
  dbms_output.put_line('<td>'||v.ELAPSED||'</td>');
  dbms_output.put_line('<td>'||v.CLUSTER_WAIT||'</td>');
  dbms_output.put_line('<td>'||v.CONCURRENCE_WAIT||'</td>');
  dbms_output.put_line('</tr>');
  end loop;
  dbms_output.put_line('</table></br>');
  
  ----获取执行计划--AWR
  dbms_output.put_line('<b>Execution Plan From AWR</b><br><br>');
  for hashval in (select distinct plan_hash_value from dba_hist_sql_plan where sql_id = vsqlid) loop
    dbms_output.put_line('SQL:'||vsqlid||', PLAN_HASH_VALUE:'||hashval.plan_hash_value);
    dbms_output.put_line('<table>');
    dbms_output.put_line('<tr><th>ID</th><th>DEP</th><th width="400px">OPERITION</th><th>NAME</th><th>ROWS</th><th>BYTES</th><th>COST(%CPU)</th><th>IO_COST</th><th>TIME</th></tr>');
  vPlanAddition.delete;
  arr_iter := 0;
    for v in (select decode(trim(predicates), '', '' || ID, '*' || ID) ID,
                     DEPTH,
                     OPERATION,
                     NAME,
                     PREDICATES,
                     "ROWS",
                     BYTES,
                     "COST(%CPU)",
                     IO_COST,
                     TIME
                from (select a.plan_hash_value || ' ' plan_hash_value,
               id ID,
               depth DEPTH,
               lpad(operation, length(operation) + depth * 6, '&nbsp;') || ' ' || options OPERATION,
               decode(OBJECT_NAME,
                  null,
                  '',
                  '[' || OBJECT_TYPE || ']' || OBJECT_OWNER || '.' ||
                  OBJECT_NAME) || '&nbsp;' NAME,
               case
               when (length(access_predicates) < 3 or access_predicates is null) then
                case
                when (length(filter_predicates) < 3 or filter_predicates is null) then
                 ' '
                else
                 '[filter]' || substr(filter_predicates, 1, 3990)
                end
               else
                '[access]' || substr(access_predicates, 1, 3990)
               end PREDICATES,
               decode(cardinality, null, '', cardinality) || '&nbsp;' "ROWS",
               decode(Bytes, null, '', Bytes) || '&nbsp;' BYTES,
               decode(io_cost,
                  null,
                  decode(cost, null, '', cost),
                  decode(cost, null, '', cost) || '(' ||
                  decode(cost, 0, 0, round((cost - io_cost) / cost * 100)) || ')') || '&nbsp;' "COST(%CPU)",
               --decode(cpu_cost, null, '', cpu_cost) || ' ' CPU_COST,
               decode(io_cost, null, '', io_cost) || ' ' IO_COST,
               trim(to_char(round(nvl(time, 0) / 3600), '00')) || ':' ||
               to_char(to_date('19000101', 'yyyymmdd') + nvl(time, 0) / 3600 / 24,
                   'mi:ss') TIME
            from dba_hist_sql_plan a
           where a.sql_id = vsqlid
             and a.plan_hash_value = hashval.plan_hash_value
           order by a.plan_hash_value, id asc
          )) loop
    /*AWR里没有Predicate信息
    arr_iter := arr_iter+1;
        vPlanAddition(arr_iter) := case when trim(v.predicates)||' ' = ' ' then '' 
            else '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;'|| v.id||' => '||v.predicates || '<br>' end;
    */
        dbms_output.put_line('<tr><td>' || v.ID || '</td><td>' || v.DEPTH ||
                             '</td><td width="400px">' || v.OPERATION || 
               '</td><td>'|| v.NAME || '</td><td>' || v."ROWS" ||
                              '</td><td>' || v.BYTES || '</td><td>' || v."COST(%CPU)" ||
                               '</td><td>' || v.IO_COST || '</td><td>' || v.TIME || '</td></tr>');
      end loop;
    dbms_output.put_line('</table><br>');
  /*AWR里没有Predicate信息
  dbms_output.put_line('<p style="font:10pt SimSun,SimSun,SimSun,SimSun">');
  dbms_output.put_line('&nbsp;&nbsp;&nbsp;&nbsp;Predicate Information (identified by operation id):<br>');
  dbms_output.put_line('&nbsp;&nbsp;&nbsp;&nbsp;---------------------------------------------------------------------------<br>');
  arr_iter := 0;
  for v1 in 1..vPlanAddition.count loop
    arr_iter := arr_iter+1;
    dbms_output.put_line(vPlanAddition(arr_iter));
  end loop;
  */
  dbms_output.put_line('<p>');
  end loop;

/*
  ----SQL统计信息（SQL STATISTICS - AWR)
  dbms_output.put_line('<b>SQL STATISTICS</b>');
  dbms_output.put_line('<table><tr><th>ID</th><th>HASH</th><th>DB_TIME_TOTAL</th><th>DB_TIME_CURRENT</th><th>MEM</th><th>VERS</th><th>EXES</th><th>DISKS</th><th>GETS</th><th>ROWS</th><th>CPU</th><th>ELAPSED</th><th>CCWAIT</th></tr>');
  for v in (select mem.SQL_ID "ID",
         mem.PLAN_HASH_VALUE "HASH",
         mem_dbtime.VAL - awr_dbtime.VAL DB_TIME_TOTAL,
         mem_dbtime.VAL - (select max(value) VAL
                   from dba_hist_sysstat
                  where stat_name = 'DB time') DB_TIME_CURRENT,
         mem.SHARABLE_MEM MEM,
         mem.VERSION_COUNT VERS,
         mem.EXECUTIONS - awr.EXECUTIONS EXES,
         mem.PARSE_CALLS - awr.PARSE_CALLS PARSE_CALLS,
         mem.DISK_READS - awr.DISK_READS "DISKS",
         mem.BUFFER_GETS - awr.BUFFER_GETS GETS,
         mem.ROWS_PROCESSED - awr.ROWS_PROCESSED "ROWS",
         mem.CPU_TIME - awr.CPU_TIME "CPU",
         mem.ELAPSED_TIME - awr.ELAPSED_TIME ELAPSED,
         mem.CCWAIT - awr.CCWAIT CCWAIT
      from (select SQL_ID,
             PLAN_HASH_VALUE,
             SHARABLE_MEM,
             VERSION_COUNT,
             FETCHES,
             END_OF_FETCH_COUNT,
             SORTS,
             EXECUTIONS,
             PX_SERVERS_EXECUTIONS PX_SERVERS_EXECS,
             LOADS,
             INVALIDATIONS,
             PARSE_CALLS,
             DISK_READS,
             BUFFER_GETS,
             ROWS_PROCESSED,
             CPU_TIME,
             ELAPSED_TIME,
             --IOWAIT,
             CLUSTER_WAIT_TIME     CLWAIT,
             APPLICATION_WAIT_TIME APWAIT,
             CONCURRENCY_WAIT_TIME CCWAIT,
             DIRECT_WRITES,
             PLSQL_EXEC_TIME       PLSEXEC_TIME,
             JAVA_EXEC_TIME        JAVEXEC_TIME
          from v$sqlstats
         where sql_id = vsqlid) mem,
         (select max(SNAP_ID) SNAP_ID,
             SQL_ID,
             PLAN_HASH_VALUE,
             max(SHARABLE_MEM) SHARABLE_MEM,
             max(VERSION_COUNT) VERSION_COUNT,
             max(FETCHES_TOTAL) FETCHES,
             max(END_OF_FETCH_COUNT_TOTAL) END_OF_FETCH_COUNT,
             max(SORTS_TOTAL) SORTS,
             max(EXECUTIONS_TOTAL) EXECUTIONS,
             max(PX_SERVERS_EXECS_TOTAL) PX_SERVERS_EXECS,
             max(LOADS_TOTAL) LOADS,
             max(INVALIDATIONS_TOTAL) INVALIDATIONS,
             max(PARSE_CALLS_TOTAL) PARSE_CALLS,
             max(DISK_READS_TOTAL) DISK_READS,
             max(BUFFER_GETS_TOTAL) BUFFER_GETS,
             max(ROWS_PROCESSED_TOTAL) ROWS_PROCESSED,
             max(CPU_TIME_TOTAL) CPU_TIME,
             max(ELAPSED_TIME_TOTAL) ELAPSED_TIME,
             max(CLWAIT_TOTAL) CLWAIT,
             max(APWAIT_TOTAL) APWAIT,
             max(CCWAIT_TOTAL) CCWAIT,
             max(DIRECT_WRITES_TOTAL) DIRECT_WRITES,
             max(PLSEXEC_TIME_TOTAL) PLSEXEC_TIME,
             max(JAVEXEC_TIME_TOTAL) JAVEXEC_TIME
          from dba_hist_sqlstat
         where snap_id >
             (select min(snap_id)
              from dba_hist_snapshot
             where startup_time =
                 (select max(startup_time) from dba_hist_snapshot))
           and sql_id = vsqlid
         group by sql_id, plan_hash_value) awr,
         (select sum(value) val from v$sysstat where name = 'DB time') mem_dbtime,
         (select a.snap_id, a.value val
          from dba_hist_sysstat a
         where a.snap_id >
             (select min(snap_id)
              from dba_hist_snapshot
             where startup_time =
                 (select max(startup_time) from dba_hist_snapshot))
           and a.stat_name = 'DB time') awr_dbtime
     where awr.sql_id(+) = mem.sql_id
       and awr.plan_hash_value(+) = mem.plan_hash_value
       and awr.snap_id = awr_dbtime.snap_id
      ) loop
    dbms_output.put_line('<tr>');
  dbms_output.put_line('<td>'||v."ID"||'</td>');
  dbms_output.put_line('<td>'||v."HASH"||'</td>');
  dbms_output.put_line('<td>'||v.DB_TIME_TOTAL||'</td>');
  dbms_output.put_line('<td>'||v.DB_TIME_CURRENT||'</td>');
  dbms_output.put_line('<td>'||v.MEM||'</td>');
  dbms_output.put_line('<td>'||v.VERS||'</td>');
  dbms_output.put_line('<td>'||v.EXES||'</td>');
  dbms_output.put_line('<td>'||v."DISKS"||'</td>');
  dbms_output.put_line('<td>'||v.GETS||'</td>');
  dbms_output.put_line('<td>'||v."ROWS"||'</td>');
  dbms_output.put_line('<td>'||v."CPU"||'</td>');
  dbms_output.put_line('<td>'||v.ELAPSED||'</td>');
  dbms_output.put_line('<td>'||v.CCWAIT||'</td>');
  dbms_output.put_line('</tr>');
  end loop;
  dbms_output.put_line('</table></br>');
*/

  ----获取SQL语句所涉及的表
  vOwnerCnt := 0;
  vOwnerstr := '';
  vTableCnt := 0;
  vTablestr := '';
  for v in (select OBJECT_OWNER, object_name
              from v$sql_plan
             where sql_id = vsqlid
               and operation like '%TABLE%'
       union
      select OBJECT_OWNER, object_name from dba_hist_sql_plan
       where sql_id = vsqlid
               and operation like '%TABLE%'
	   union
	  select OBJECT_OWNER, object_name from PLAN_TABLE
	   where operation like '%TABLE%'
      ) loop
    vTablestr := vTablestr || v.OBJECT_NAME || ',';
    vTableCnt := vTableCnt + 1;
    vOwnerstr := vOwnerstr || v.OBJECT_OWNER || ',';
    vOwnerCnt := vOwnerCnt + 1;
  end loop;
  vOwnerstr := substr(vOwnerstr, 1, length(vOwnerstr) - 1);
  vTablestr := substr(vTablestr, 1, length(vTablestr) - 1);
  
  ----SQL涉及所有表的尺寸（Table Segment Size)
  dbms_output.put_line('<b>Table Segment Size</b>');
  dbms_output.put_line('<table><tr><th>owner</th><th>segment_name</th><th>MB</th>');
  for v in (select owner, segment_name, to_char(sum(bytes) / 1024 / 1024, '9999990.99') MB
              from dba_segments
             where segment_name in
                   (SELECT REGEXP_SUBSTR(vTablestr, '[^,]+', 1, LEVEL) AS value_str
                      FROM DUAL
                    CONNECT BY LEVEL <= vTableCnt)
					and owner in (SELECT REGEXP_SUBSTR(vOwnerstr, '[^,]+', 1, LEVEL) AS value_str
                      FROM DUAL
                    CONNECT BY LEVEL <= vOwnerCnt)
             group by owner, segment_name
             order by owner, segment_name) loop
    dbms_output.put_line('<tr><td>' || v.OWNER || '</td><td>' ||
                         v.segment_name || '</td><td>' || v.MB ||
                         '</td></tr>');
  end loop;
  dbms_output.put_line('</table></br>');
  
  ----SQL涉及所有表的相关信息(Table Statistics)
  dbms_output.put_line('<b>Table Statistics</b>');
  dbms_output.put_line('<table><tr>' || '<th>OWNER</th>' ||
                       '<th>table_name</th>' || '<th>num_rows</th>' ||
                       '<th>blocks</th>' || '<th>degree</th>' ||
                       '<th>last_analyzed</th>' || '<th>temporary</th>' ||
                       '<th>partitioned</th>' || '<th>pct_free</th>' ||
                       '<th>tablespace_name</th>');
  for v in (select t.OWNER,
                   t.table_name,
                   t.num_rows,
                   t.blocks,
                   t.degree,
                   t.last_analyzed,
                   t.temporary,
                   t.partitioned,
                   t.pct_free,
                   t.tablespace_name
              from dba_tables t
             where table_name in
                   (SELECT REGEXP_SUBSTR(vtablestr, '[^,]+', 1, LEVEL) AS value_str
                      FROM DUAL
                    CONNECT BY LEVEL <= vTableCnt)
               and owner in (SELECT REGEXP_SUBSTR(vOwnerstr, '[^,]+', 1, LEVEL) AS value_str
                      FROM DUAL
                    CONNECT BY LEVEL <= vOwnerCnt)
             order by owner, table_name) loop
    dbms_output.put_line('<tr><td>' || v.OWNER || '</td><td>' ||
                         v.table_name || '</td><td>' || v.num_rows ||
                         '</td><td>' || v.blocks || '</td><td>' ||
                         v.degree || '</td><td>' || v.last_analyzed ||
                         '</td><td>' || v.temporary || '</td><td>' ||
                         v.partitioned || '</td><td>' || v.pct_free ||
                         '</td><td>' || v.tablespace_name || '</td></tr>');
  end loop;
  dbms_output.put_line('</table></br>');

  ----SQL涉及所有表的列信息(Table Column Statistics)
  dbms_output.put_line('<b>Table Column Statistics</b>');
  dbms_output.put_line('<table><tr>' || '<th>OWNER</th>' ||
                       '<th>table_name</th>' || '<th>column_name</th>' ||
                       '<th>data_type</th>' || '<th>nullable</th>' ||
                       '<th>last_analyzed</th>' || '<th>avg_col_len</th></tr>');
  for v in (select owner,
                   table_name,
                   column_name,
                   data_type,
                   nullable,
                   to_char(last_analyzed, 'mm/dd/yy hh24:mi:ss') analyzed,
                   avg_col_len
              from dba_tab_cols
             where table_name in (SELECT REGEXP_SUBSTR(vTABLESTR, '[^,]+', 1, LEVEL) AS value_str
                                    FROM DUAL
                                  CONNECT BY LEVEL <= vTABLECNT)
               and owner in (SELECT REGEXP_SUBSTR(vOwnerstr, '[^,]+', 1, LEVEL) AS value_str
                      FROM DUAL
                    CONNECT BY LEVEL <= vOwnerCnt)
          order by owner, table_name, column_name) loop
    dbms_output.put_line('<tr><td>' || v.OWNER || '</td><td>' ||
                         v.table_name || '</td><td>' || v.column_name ||
                         '</td><td>' || v.data_type || '</td><td>' ||
                         v.nullable || '</td><td>' || v.analyzed ||
                         '</td><td>' || v.avg_col_len || '</td></tr>');
  end loop;
  dbms_output.put_line('</table></br>'); 

  ----SQL涉及所有表的触发器信息(Table Triggers)
  dbms_output.put_line('<b>Table Triggers</b>');
  dbms_output.put_line('<table><tr>' || '<th>table_owner</th>' ||
                       '<th>table_name</th>' || '<th>base_object_type</th>' ||
                       '<th>tiggger_owner</th>' || '<th>trigger_name</th>' ||
                       '<th>trigger_type</th>' || '<th>triggering_event</th></tr>');
  for v in (select table_owner,
                   table_name,
                   base_object_type,
                   owner tiggger_owner,
                   trigger_name,
                   trigger_type,
                   triggering_event
              from dba_triggers
             where table_name in (SELECT REGEXP_SUBSTR(vTABLESTR, '[^,]+', 1, LEVEL) AS value_str
                                    FROM DUAL
                                  CONNECT BY LEVEL <= vTABLECNT)
               and owner in (SELECT REGEXP_SUBSTR(vOwnerstr, '[^,]+', 1, LEVEL) AS value_str
                      FROM DUAL
                    CONNECT BY LEVEL <= vOwnerCnt)
             order by table_owner, table_name) loop
    dbms_output.put_line('<tr><td>' || v.table_owner || '</td><td>' ||
                         v.table_name || '</td><td>' || v.base_object_type ||
                         '</td><td>' || v.tiggger_owner || '</td><td>' ||
                         v.trigger_name || '</td><td>' || v.trigger_type ||
                         '</td><td>' || v.triggering_event || '</td></tr>');
  end loop;
  dbms_output.put_line('</table></br>'); 
  
  ----SQL涉及的分区表的相关信息(Partition Statistics)
  dbms_output.put_line('<b>Partition Statistics</b>');
  dbms_output.put_line('<table><tr>' || '<th>OWNER</th>' ||
                       '<th>table_name</th>' ||
                       '<th>partitioning_type</th>' ||
                       '<th>partition_count</th>');
  for v in (select t.owner,
                   t.table_name,
                   t.partitioning_type,
                   t.partition_count
              from dba_part_tables t
             where table_name in
                   (SELECT REGEXP_SUBSTR(vtablestr, '[^,]+', 1, LEVEL) AS value_str
                      FROM DUAL
                    CONNECT BY LEVEL <= vtablecnt)
               and owner in (SELECT REGEXP_SUBSTR(vOwnerstr, '[^,]+', 1, LEVEL) AS value_str
                      FROM DUAL
                    CONNECT BY LEVEL <= vOwnerCnt)) loop
    dbms_output.put_line('<tr><td>' || v.OWNER || '</td><td>' ||
                         v.table_name || '</td><td>' ||
                         v.partitioning_type || '</td><td>' ||
                         v.partition_count || '</td></tr>');
  end loop;
  dbms_output.put_line('</table></br>');
  
  ----分区表的分区列相关信息(Partition Key Statistics)
  dbms_output.put_line('<b>Partition Key Statistics</b>');
  dbms_output.put_line('<table><tr>' || '<th>owner</th>' ||
                       '<th>name</th>' || '<th>object_type</th>' ||
                       '<th>column_name</th>');
  for v in (select owner, name, object_type, column_name
              from dba_part_key_columns
             where name in (SELECT REGEXP_SUBSTR(vtablestr, '[^,]+', 1, LEVEL) AS value_str
                              FROM DUAL
                            CONNECT BY LEVEL <= vtablecnt)
               and owner in (SELECT REGEXP_SUBSTR(vOwnerstr, '[^,]+', 1, LEVEL) AS value_str
                      FROM DUAL
                    CONNECT BY LEVEL <= vOwnerCnt)) loop
    dbms_output.put_line('<tr><td>' || v.OWNER || '</td><td>' || v.name ||
                         '</td><td>' || v.object_type || '</td><td>' ||
                         v.column_name || '</td></tr>');
  end loop;
  dbms_output.put_line('</table>');
  
  ----分区表分区范围信息(Partition Range Statistics)
  dbms_output.put_line('<b>Partition Range Statistics</b>');
  dbms_output.put_line('<table><tr>' || '<th>owner</th>' ||
                       '<th>table_name</th>' || '<th>partition_name</th>' ||
                       '<th>high_value</th>' || '<th>tablespace_name</th>');
  for v in (SELECT table_owner owner,
                   table_name,
                   partition_name,
                   high_value,
                   tablespace_name
              FROM dba_tab_partitions t
             where table_name in
                   (SELECT REGEXP_SUBSTR(vtablestr, '[^,]+', 1, LEVEL) AS value_str
                      FROM DUAL
                    CONNECT BY LEVEL <= vtablecnt)
               and table_owner in (SELECT REGEXP_SUBSTR(vOwnerstr, '[^,]+', 1, LEVEL) AS value_str
                      FROM DUAL
                    CONNECT BY LEVEL <= vOwnerCnt)
             order by table_owner, table_name, t.partition_position) loop
    dbms_output.put_line('<tr><td>' || v.OWNER || '</td><td>' ||
                         v.table_name || '</td><td>' || v.partition_name ||
                         '</td><td>' || v.high_value || '</td><td>' ||
                         v.tablespace_name || '</td></tr>');
  end loop;
  dbms_output.put_line('</table></br>');
  
  ----索引的大小(Index Segments)
  dbms_output.put_line('<b>Index Segments</b>');
  dbms_output.put_line('<table><tr>' || '<th>OWNER</th>' ||
                       '<th>table_name</th>' || '<th>segment_name</th>' ||
                       '<th>MB</th></tr>');
  for v in (select t1.owner,
                   t2.table_name,
                   t1.segment_name,
                   to_char(sum(t1.bytes) / 1024 / 1024, '9999990.99') MB
              from dba_segments t1, dba_indexes t2
             where t1.segment_name = t2.index_name
               and t1.segment_type like '%INDEX%'
			   and t1.owner = t2.owner
               and t2.table_name in
                   (SELECT REGEXP_SUBSTR(vtablestr, '[^,]+', 1, LEVEL) AS value_str
                      FROM DUAL
                    CONNECT BY LEVEL <= vtablecnt)
               and t1.owner in (SELECT REGEXP_SUBSTR(vOwnerstr, '[^,]+', 1, LEVEL) AS value_str
                      FROM DUAL
                    CONNECT BY LEVEL <= vOwnerCnt)
			   and t2.owner in (SELECT REGEXP_SUBSTR(vOwnerstr, '[^,]+', 1, LEVEL) AS value_str
                      FROM DUAL
                    CONNECT BY LEVEL <= vOwnerCnt)
             group by t1.owner, t2.table_name, t1.segment_name
             order by owner, table_name) loop
    dbms_output.put_line('<tr><td>' || v.owner || '</td><td>' ||
                         v.table_name || '</td><td>' || v.segment_name ||
                         '</td><td>' || v.MB || '</td></tr>');
  end loop;
  dbms_output.put_line('</table></br>');
  
  ----索引相关信息(Index Statistics)
  dbms_output.put_line('<b>Index Statistics</b>');
  dbms_output.put_line('<table><tr>' || '<th>OWNER</th>' ||
                       '<th>table_name</th>' || '<th>name</th>' ||
                       '<th>rows</th>' || '<th>type</th>' ||
                       '<th>status</th>' || '<th>factor</th>' ||
                       '<th>blevel</th>' || '<th>distinct</th>' ||
                       '<th>leaf</th>' || '<th>unique</th>' ||
                       '<th>degree</th>' || '<th>analyzed</th></tr>');
  for v in (select t.owner,
                   t.table_name,
                   t.index_name        "name",
                   t.num_rows          "rows",
                   t.index_type        "type",
                   t.status,
                   t.clustering_factor factor,
                   t.blevel,
                   t.distinct_keys     "distinct",
                   t.leaf_blocks       leaf,
                   t.uniqueness        "unique",
                   t.degree,
                   to_char(t.last_analyzed, 'mm/dd/yy hh24:mi:ss') analyzed
              from dba_indexes t
             where table_name in
                   (SELECT REGEXP_SUBSTR(vtablestr, '[^,]+', 1, LEVEL) AS value_str
                      FROM DUAL
                    CONNECT BY LEVEL <= vtablecnt)
               and owner in (SELECT REGEXP_SUBSTR(vOwnerstr, '[^,]+', 1, LEVEL) AS value_str
                      FROM DUAL
                    CONNECT BY LEVEL <= vOwnerCnt)
             order by owner, table_name) loop
    dbms_output.put_line('<tr><td>' || v.owner || '</td><td>' ||
                         v.table_name || '</td><td>' || v."name" ||
                         '</td><td>' || v."rows" || '</td><td>' ||
                         v."type" || '</td><td>' || v.status ||
                         '</td><td>' || v.factor || '</td><td>' ||
                         v.blevel || '</td><td>' || v."distinct" ||
                         '</td><td>' || v.leaf || '</td><td>' ||
                         v."unique" || '</td><td>' || v.degree ||
                         '</td><td>' || v.analyzed || '</td><tr>');
  end loop;
  dbms_output.put_line('</table></br>');
  
  ----索引列信息，在哪些列有索引(Index columns)
  dbms_output.put_line('<b>Index columns</b>');
  dbms_output.put_line('<table><tr>' || '<th>OWNER</th>' ||
                       '<th>table_name</th>' || '<th>table_name</th>' ||
                       '<th>column_name</th>' ||
                       '<th>column_position</th>' ||
                       '<th>DESCEND</th></tr>');
  for v in (select t.index_owner owner,
                   t.table_name,
                   t.index_name,
                   t.column_name,
                   t.column_position,
                   t.DESCEND
              from dba_ind_columns t
             where table_name in
                   (SELECT REGEXP_SUBSTR(vtablestr, '[^,]+', 1, LEVEL) AS value_str
                      FROM DUAL
                    CONNECT BY LEVEL <= vtablecnt)
               and index_owner in (SELECT REGEXP_SUBSTR(vOwnerstr, '[^,]+', 1, LEVEL) AS value_str
                      FROM DUAL
                    CONNECT BY LEVEL <= vOwnerCnt)
             order by owner, table_name, index_name, column_position) loop
    dbms_output.put_line('<tr><td>' || v.owner || '</td><td>' ||
                         v.table_name || '</td><td>' || v.index_name ||
                         '</td><td>' || v.column_name || '</td><td>' ||
                         v.column_position || '</td><td>' || v.DESCEND ||
                         '</td></tr>');
  end loop;
  dbms_output.put_line('</table></br>');
  
  ----分区索引的分区个数(Partition Indexes nums)
  dbms_output.put_line('<b>Partition Indexes Summary</b>');
  dbms_output.put_line('<table><tr>' || '<th>OWNER</th>' ||
                       '<th>table_name</th>' || '<th>table_name</th>' ||
                       '<th>partitioning_type</th>' ||
                       '<th>partition_count</th></tr>');
  for v in (select owner,
                   table_name,
                   index_name,
                   partitioning_type,
                   partition_count
              from dba_part_indexes
             where table_name in
                   (SELECT REGEXP_SUBSTR(vtablestr, '[^,]+', 1, LEVEL) AS value_str
                      FROM DUAL
                    CONNECT BY LEVEL <= vtablecnt)
               and owner in (SELECT REGEXP_SUBSTR(vOwnerstr, '[^,]+', 1, LEVEL) AS value_str
                      FROM DUAL
                    CONNECT BY LEVEL <= vOwnerCnt)
             order by owner, table_name, index_name) loop
    dbms_output.put_line('<tr><td>' || v.owner || '</td><td>' ||
                         v.table_name || '</td><td>' || v.index_name ||
                         '</td><td>' || v.partitioning_type || '</td><td>' ||
                         v.partition_count || '</td></tr>');
  end loop;
  dbms_output.put_line('</table></br>');
  
  ----分区索引的详细信息(Partition Indexes details)
  dbms_output.put_line('<b>Partition Indexes Details</b>');
  dbms_output.put_line('<table><tr>' || '<th>OWNER</th>' ||
                       '<th>index_name</th>' || '<th>partition_name</th>' ||
                       '<th>status</th>' || '<th>blevel</th>' ||
                       '<th>leaf_blocks</th>' ||
                       '<th>tablespace_name</th></tr>');
  for v in (select index_owner owner,
                   index_name,
                   partition_name,
                   status,
                   blevel,
                   leaf_blocks,
                   tablespace_name
              from dba_ind_partitions
             where index_name in
                   (select index_name
                      from dba_indexes
                     where table_name in
                           (SELECT REGEXP_SUBSTR(vtablestr, '[^,]+', 1, LEVEL) AS value_str
                              FROM DUAL
                            CONNECT BY LEVEL <= vtablecnt)
					   and owner in (SELECT REGEXP_SUBSTR(vOwnerstr, '[^,]+', 1, LEVEL) AS value_str
							  FROM DUAL
							CONNECT BY LEVEL <= vOwnerCnt))
			   and index_owner in (SELECT REGEXP_SUBSTR(vOwnerstr, '[^,]+', 1, LEVEL) AS value_str
                               FROM DUAL
				   CONNECT BY LEVEL <= vOwnerCnt)
             order by owner, index_name, partition_name) loop
    dbms_output.put_line('<tr><td>' || v.owner || '</td><td>' ||
                         v.index_name || '</td><td>' || v.partition_name ||
                         '</td><td>' || v.status || '</td><td>' ||
                         '</td><td>' || v.blevel || '</td><td>' ||
                         '</td><td>' || v.leaf_blocks || '</td><td>' ||
                         '</td><td>' || v.tablespace_name || '</td></tr>');
  end loop;
  dbms_output.put_line('</table></br>');
  
  ----嵌入awrsqrpt
  dbms_output.put_line('<b>Awrsqrpt Contents</b>');
  dbms_output.put_line('<div>');
  begin
    for v in (select max(maxsnap_id) maxsnap_id,
                     max(maxsnap_id) - 1 as minsnap_id
                from (select startup_time,
                             max(a.snap_id) maxsnap_id,
                             min(a.snap_id) minsnap_id
                        from dba_hist_snapshot a, dba_hist_sqlstat b
                       where a.snap_id = b.snap_id
                         and b.sql_id = vsqlid
                       group by startup_time)
               where maxsnap_id <> minsnap_id) loop
      dbms_output.put_line('<div>');
	  begin
		for v_in in (select output
                     from table(dbms_workload_repository.awr_sql_report_html((select dbid
                                                                               from v$database
                                                                              where rownum = 1),
                                                                             (select instance_number
                                                                                from v$instance
                                                                               where rownum = 1),
                                                                             v.minsnap_id,
                                                                             v.maxsnap_id,
                                                                             vsqlid))) loop
		  dbms_output.put_line(v_in.output);
		end loop;
	  Exception
      when others then
        vsqlmsg := sqlerrm;
		dbms_output.put_line('在DBA_HIST_XXXX中找不到SQL:' || vsqlid || '的信息.');
        dbms_output.put_line(vsqlmsg);
	  end;
      dbms_output.put_line('</div>');
    end loop;
  Exception
    when others then
      vsqlmsg := sqlerrm;
      dbms_output.put_line(vsqlmsg);
  end;
  dbms_output.put_line('</div>');
  
  dbms_output.put_line('</body></html>');
  rollback;
end;
/
set termout on
spool off;
exit
