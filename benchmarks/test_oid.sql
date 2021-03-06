create temporary table acl_data (n bigint not null primary key, acl ace[]);

select setseed(0);

do $$
declare
  v_n integer;
  v_user name;
  v_role name;
begin
  set client_min_messages to warning;

  for v_n in 0..100 loop
    execute 'create role acl_test_' || v_n;
  end loop;

  for v_n in 1..10000 loop
    v_user = 'acl_test_' || (random() * 100)::bigint;
    v_role = 'acl_test_' || (random() * 100)::bigint;

    if not pg_has_role(v_role, v_user, 'MEMBER') then
      execute 'grant ' || quote_ident(v_role) || ' to ' || quote_ident(v_user);
    end if;
  end loop;

  set client_min_messages to notice;
end;
$$ language plpgsql;

insert into acl_data (n, acl)
select g1, t.acl
from generate_series(0, $unique_aces - 1) g1
  cross join lateral (
    select array_agg((t.type || '//' || r.rolname || '=' || a.rights)::ace) as acl
    from generate_series(1, (random() * $ace_count * (g1 + 1))::integer % $ace_count) g2
      cross join lateral (select * from pg_roles order by random() * g1 * g2 limit 1) r
      cross join lateral (select t as type from unnest(string_to_array('ad', null)) t order by random() * g1 * g2 limit 1) t
      cross join lateral (select string_agg(t, '') as rights from (select t from unnest(string_to_array('scdwr0123456789ABCDEFGHIJKLMNOPQ', null)) t order by random() * g1 * g2 limit (random() * 10 + 1)::integer) t) a
  ) t;

vacuum full analyze acl_data;

create temporary view acl_test as
select g, (select d.acl from acl_data d where d.n = g % $unique_aces)
from generate_series(1, $count) g;

do $$
declare
  v_role oid;
  v_count bigint;
  v_time1 timestamptz;
  v_time2 timestamptz;
begin
  v_time1 = clock_timestamp();
  select count(*) into v_count from acl_test where acl is not null;
  v_time2 = clock_timestamp();
  raise notice 'Full scan. Count: %, time: %', v_count, v_time2 - v_time1;

  v_role = (select oid from pg_roles where rolname = 'acl_test_42');

  v_time1 = clock_timestamp();
  select count(*) into v_count from acl_test where acl_check_access(acl, '011010000000000000000000'::bit(32)::int4, v_role, true) = '011010000000000000000000'::bit(32)::int4;
  v_time2 = clock_timestamp();
  raise notice 'ACL scan. Count: %, time: %', v_count, v_time2 - v_time1;
end;
$$ language plpgsql;

do $$
declare
  v_n integer;
begin
  for v_n in 0..100 loop
    execute 'drop role acl_test_' || v_n;
  end loop;
end;
$$ language plpgsql;
