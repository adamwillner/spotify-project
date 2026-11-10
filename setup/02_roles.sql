--One-time setup: role-based access for dbt (least privilege) 

use role securityadmin;

create role if not exists transformer;

grant usage on warehouse my_wh to role transformer;
grant usage on database spotify_db to role transformer;
grant usage on schema spotify_db.raw to role transformer;
grant select on all tables in schema spotify_db.raw to role transformer;
grant select on future tables in schema spotify_db.raw to role transformer;
grant create table on schema spotify_db.raw to role transformer;
grant create schema on database spotify_db to role transformer;

grant role transformer to role sysadmin;
grant role transformer to user "<your_user>";  -- replace with your Snowflake username