-- Add commonly used import-sourcing currencies.
insert into public.currencies (code,name,symbol,minor_units,is_active)
values ('CNY','Chinese Yuan','¥',2,true),('JPY','Japanese Yen','¥',0,true),('AED','UAE Dirham','د.إ',2,true)
on conflict (code) do update set name=excluded.name,symbol=excluded.symbol,minor_units=excluded.minor_units,is_active=true;
