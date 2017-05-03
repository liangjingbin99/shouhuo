
/* 
假如mkdb脚本位于windows环境下的d盘的根目录下
运行方法 sqlplus "/ as sysdba" @d:\mkdb.sql
*/

create user ljb identified by ljb;
alter user ljb default tablespace users;
grant dba to ljb;

spool mkdb.log

---表空间扩展过于频繁
DROP tablespace tbs_a including contents AND datafiles;
create tablespace TBS_A datafile '/oracle/scripts/sql/TBS_A.DBF' size 1M autoextend on uniform size 64k;
CREATE TABLE ljb.t_a (id int,contents varchar2(1000)) tablespace TBS_A;
insert into ljb.t_a select rownum,LPAD('1', 1000, '*') from dual connect by level<=20000;
COMMIT;

--全局临时表被收集统计信息
drop table ljb.g_tab_del purge;
drop table ljb.g_tab_pre purge;
create global temporary table ljb.g_tab_del on commit DELETE rows as select  * from dba_objects   WHERE 1=2;
create global temporary table ljb.g_tab_pre ON commit preserve rows as select  * from dba_objects WHERE 1=2;
COMMIT;
exec dbms_stats.gather_table_stats(ownname => 'LJB', tabname => 'g_tab_del',cascade => true);
exec dbms_stats.gather_table_stats(ownname => 'LJB', tabname => 'g_tab_pre',cascade => true);

--表有过时字段
DROP   TABLE ljb.t_char_long purge;
CREATE TABLE ljb.t_char_long (NAME CHAR(10), VALUE LONG);

--表未建任何索引
DROP   TABLE ljb.t_noidx purge;
CREATE TABLE ljb.t_noidx AS SELECT * FROM dba_objects;
INSERT INTO  ljb.t_noidx SELECT * FROM ljb.t_noidx;
INSERT INTO  ljb.t_noidx SELECT * FROM ljb.t_noidx;
INSERT INTO  ljb.t_noidx SELECT * FROM ljb.t_noidx;
COMMIT;

--表建在系统表空间
DROP TABLE   ljb.t_sys purge;
CREATE TABLE ljb.t_sys tablespace system AS SELECT * FROM dba_objects WHERE rownum<=100;

--表带并行属性
DROP TABLE   ljb.t_degree purge;
CREATE TABLE ljb.t_degree parallel 8 AS SELECT * FROM dba_objects WHERE rownum<=100;

--表被压缩
DROP TABLE   ljb.t_compress purge;
CREATE TABLE ljb.t_compress compress  AS SELECT * FROM dba_objects ;

--表的日志被关闭
DROP   TABLE  ljb.t_nolog purge;
CREATE TABLE  ljb.t_nolog nologging AS SELECT * FROM dba_objects WHERE rownum<=100;

--表的列过多(比如超过100个列）
DROP TABLE ljb.t_col_max purge;
DECLARE
  l_sql VARCHAR2(32767);
BEGIN
  l_sql := 'CREATE TABLE ljb.t_col_max (';
  FOR i IN 1..100 
  LOOP
    l_sql := l_sql || 'n' || i || ' NUMBER,';
  END LOOP;
  l_sql := l_sql || 'pad VARCHAR2(1000)) PCTFREE 10';
  EXECUTE IMMEDIATE l_sql;
END;
/

--表的列过少(比如少于2个列）
DROP TABLE ljb.t_col_min1 purge;
DROP TABLE ljb.t_col_min2 purge;
CREATE TABLE ljb.t_col_min1 (id INT);
CREATE TABLE ljb.t_col_min2 (id INT,NAME varchar2(100));

--表的高水平位没释放
DROP   table ljb.t_high purge;
create table ljb.t_high as select * from dba_objects WHERE rownum<=10000;
insert into  ljb.t_high select * from ljb.t_high;
insert into  ljb.t_high select * from ljb.t_high;
insert into  ljb.t_high select * from ljb.t_high;
insert into  ljb.t_high select * from ljb.t_high;
insert into  ljb.t_high select * from ljb.t_high;
commit;
delete from ljb.t_high ;
COMMIT;

--表有触发器
DROP table ljb.t1_tri purge;
drop table ljb.t2_tri purge;

CREATE table ljb.t1_tri AS SELECT object_name, object_id, object_type FROM dba_objects WHERE rownum<=30;

CREATE table ljb.t2_tri
as
SELECT object_type, count(*) as cnt
FROM ljb.t1_tri
group by object_type;

CREATE or replace trigger ljb.tri_t2_trigger
after insert on ljb.t1_tri
for each row
begin
insert into ljb.t2_tri(object_type,cnt) values (:new.object_type,1);
end tri_t2_trigger;
/

--表分区数过多，比如超过100个
DROP TABLE   ljb.T_PART1 PURGE;
CREATE TABLE ljb.t_part1 partition BY range(dates) (partition P_MAX VALUES less than(maxvalue))
AS SELECT rownum id ,trunc(sysdate-rownum) AS DATES, ceil(dbms_random.value(0,100000)) nbr  FROM dual CONNECT BY level<=10000;
CREATE or replace procedure proc_1 AS
v_next_day DATE;
v_prev_day DATE;
v_sql_p_split_part varchar2(4000);
begin
for i in 1 .. 100 loop
       select add_months(trunc(sysdate), i) into v_next_day from dual;
       select add_months(trunc(sysdate), -i) into v_prev_day from dual;
       v_sql_p_split_part := 'alter table ljb.t_part1 split partition p_MAX at ' ||
               '(to_date(''' || to_char(v_next_day, 'yyyymmdd') ||
               ''',''yyyymmdd''))' || 'into (partition T_PART_' ||
               to_char(v_prev_day, 'yyyymm') || ' tablespace users ,partition p_MAX)';
               execute immediate v_sql_p_split_part;
end loop;
END;
/
exec proc_1;

--分区不均匀
drop   table ljb.t_part2 purge;
create table ljb.t_part2 (id INT,VALUE number)
    partition by range (id)
    (
    partition p1  values less than (1000),
    partition p2  values less than (2000),
    partition p3  values less than (3000),
    partition p4  values less than (4000),
    partition p5  values less than (5000),
    partition p6  values less than (6000),
    partition p7  values less than (7000),
    partition p8  values less than (8000),
    partition p9  values less than (9000),
    partition p10 values less than (maxvalue)
    )
    ;
INSERT INTO ljb.t_part2 SELECT rownum ,ceil(dbms_random.value(0,10000)) FROM dual CONNECT BY rownum<=10000;
INSERT INTO ljb.t_part2 SELECT rownum ,9999 FROM dual CONNECT BY rownum<=100000;
COMMIT;
exec dbms_stats.gather_table_stats('LJB', 't_part2');

--分区索引失效
---DROP INDEX ljb.idx_t_part1_id;
---DROP INDEX ljb.idx_t_part1_nbr;
CREATE INDEX ljb.idx_t_part1_id ON ljb.t_part1(id) ;
CREATE INDEX ljb.idx_t_part1_nbr ON ljb.t_part1(nbr) local;
--全局索引失效
ALTER INDEX ljb.idx_t_part1_id unusable;
--局部索引失效
alter table ljb.t_part1  move partition T_PART_201410;

--普通索引失效
DROP TABLE   ljb.t1 purge;
CREATE TABLE ljb.t1 AS SELECT * FROM dba_objects WHERE rownum<=2000;
CREATE INDEX ljb.idx_t1_obj_id ON ljb.t1(object_id);
ALTER INDEX  ljb.idx_t1_obj_id unusable;

--单表索引过多(比如超过6个）
DROP   TABLE ljb.t2 purge;
CREATE TABLE ljb.t2 AS SELECT * FROM dba_objects WHERE rownum<=2000;
CREATE INDEX ljb.idx_t2_obj_id   ON ljb.t2(object_id);
CREATE INDEX ljb.idx_t2_obj_type ON ljb.t2(object_type);
CREATE INDEX ljb.idx_t2_obj_name ON ljb.t2(object_name);
CREATE INDEX ljb.idx_t2_data_obj_id ON ljb.t2(data_object_id);
CREATE INDEX ljb.idx_t2_status ON ljb.t2(STATUS);
CREATE INDEX ljb.idx_t2_created ON ljb.t2(created);
CREATE INDEX ljb.idx_t2_last_ddl_time ON ljb.t2(last_ddl_time);

--索引被压缩
DROP TABLE   ljb.t_idx_compress purge;
CREATE TABLE ljb.t_idx_compress AS SELECT * FROM dba_objects ;
CREATE INDEX ljb.idx_id_compress ON ljb.t_idx_compress(object_id) compress;

--单表索引组合列过多
DROP   TABLE ljb.t3 purge;
CREATE TABLE ljb.t3 AS SELECT * FROM dba_objects WHERE rownum<=2000;
CREATE INDEX ljb.idx_t3_union ON ljb.t3(object_id,object_type,object_name,last_ddl_time);

--聚合因子明显不好的
drop table   ljb.colocated purge;
create table ljb.colocated ( x int, y varchar2(80) );
begin
    for i in 1 .. 10000
    loop
        insert into ljb.colocated(x,y)
        values (i, rpad(dbms_random.random,75,'*') );
    end loop;
end;
/
alter table ljb.colocated
add constraint colocated_pk
primary key(x);
begin
dbms_stats.gather_table_stats(ownname => 'LJB', tabname => 'COLOCATED',cascade => true);
END;
/

drop table   ljb.disorganized purge;
create table ljb.disorganized AS select x,y from ljb.colocated order by y;
alter table  ljb.disorganized add constraint disorganized_pk primary key (x);
begin
dbms_stats.gather_table_stats(ownname => 'LJB', tabname => 'DISORGANIZED',cascade => true);
END;
/

--索引建在系统表空间
DROP   TABLE ljb.t_idx_sys purge;
CREATE TABLE ljb.t_idx_sys tablespace system AS SELECT * FROM dba_objects WHERE rownum<=100;
CREATE INDEX ljb.idx_t_sys ON ljb.t_idx_sys(object_id) tablespace system;

--索引带并行属性
DROP   TABLE   ljb.t_idx_degree  purge;
CREATE TABLE   ljb.t_idx_degree  AS SELECT * FROM dba_objects WHERE rownum<=100;
CREATE index   ljb.idx_t_degree  ON ljb.t_idx_degree(object_id) parallel 8;


--外键未建索引
drop table   ljb.t_p cascade constraints purge;
drop table   ljb.t_c cascade constraints purge;
CREATE TABLE ljb.T_P (ID NUMBER, NAME VARCHAR2(30));
ALTER TABLE  ljb.T_P ADD CONSTRAINT  T_P_ID_PK  PRIMARY KEY (ID);
CREATE TABLE ljb.T_C (ID NUMBER, FID NUMBER, NAME VARCHAR2(30));
ALTER TABLE  ljb.T_C ADD CONSTRAINT FK_T_C FOREIGN KEY (FID) REFERENCES ljb.T_P (ID);
INSERT INTO  ljb.T_P SELECT ROWNUM, TABLE_NAME FROM ALL_TABLES;
INSERT INTO  ljb.T_C SELECT ROWNUM, MOD(ROWNUM, 1000) + 1, OBJECT_NAME  FROM ALL_OBJECTS WHERE rownum<=100;
COMMIT;
--create index ljb.idx_IND_T_C_FID on T_C(FID);


--有位图索引
DROP TABLE   ljb.t_bit  purge;
CREATE TABLE ljb.t_bit AS SELECT * FROM dba_objects WHERE rownum<=100;
CREATE INDEX ljb.idx_bit_status ON ljb.t_bit(STATUS);

--有函数索引
DROP TABLE   ljb.t_fun purge;
CREATE TABLE ljb.t_fun AS SELECT * FROM dba_objects WHERE rownum<=100;
CREATE INDEX ljb.idx_func_objname ON ljb.t_fun(upper(object_name));

--有反向键索引
DROP TABLE   ljb.t_rev purge;
--DROP INDEX   ljb.idx_rev_objid;
CREATE TABLE ljb.t_rev AS SELECT * FROM dba_objects WHERE rownum<=100;
CREATE INDEX ljb.idx_rev_objid ON ljb.t_fun(object_id) REVERSE;

--组合和单列索引存在交叉
DROP   TABLE ljb.t_cross purge;
CREATE TABLE ljb.t_cross AS SELECT * FROM dba_objects WHERE rownum<=100;
CREATE INDEX ljb.idx_obj_id_name ON ljb.t_cross(object_id,object_name);
CREATE INDEX ljb.idx_obj_id ON ljb.t_cross(object_id);


--sql长度超过100行
DROP TABLE   ljb.t_sql purge;
CREATE TABLE ljb.t_sql AS SELECT * FROM dba_objects;
SELECT * FROM ljb.t_sql WHERE 
object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND
object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND
object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND
object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND
object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND
object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND
object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 AND object_id=1 ;

--未使用绑定变量
drop   table ljb.t_unbind purge;
create table ljb.t_unbind ( x int );
create or replace procedure ljb.proc_unbind
as
begin
    for i in 1 .. 20000
    loop
        execute immediate
        'insert into ljb.t_unbind values ( '||i||')';
    end loop;
   COMMIT;
end;
/ 
exec ljb.proc_unbind;


--未使用批量提交
drop   table ljb.t_unbatch purge;
create table ljb.t_unbatch ( x int );
create or replace procedure ljb.proc_unbatch
as
begin
    for i in 1 .. 20000
    loop
     insert into ljb.t_unbatch values (i);   
     commit;
    end loop;
end;
/
exec ljb.proc_unbatch;


--失效的过程包等
drop   table ljb.t_proc purge;
CREATE table ljb.t_proc (id number,col2 number);
INSERT into  ljb.t_proc select rownum, ceil(dbms_random.value(1,10)) from dual connect by level<=10;
COMMIT;


-----有效的
Create or replace 
procedure ljb.p_insert1_t_proc (p in number ) is
begin
	insert into ljb.t_proc (id,col2) VALUES(rownum,p);
	commit;
end ;
/

-----失效的
Create or replace 
procedure ljb.p_insert2_t_proc (p in number ) is
begin
	insert into ljb.t_proc (id,col3) VALUES(rownum,p);
	commit;
end ;
/

---构造CACHE小于20的序列
DROP SEQUENCE ljb.seqtest1;
CREATE  SEQUENCE ljb.seqtest1
INCREMENT BY 1 
START WITH 1 
NOMAXvalue 
NOCYCLE 
CACHE 20; 

spool off

EXIT
