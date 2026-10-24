-- One duration per activity instead of a short and a long version.
-- Dropping long_min also drops the "long_min >= short_min" check. Existing rows keep their short value.
alter table public.activities drop column long_min;
alter table public.activities rename column short_min to duration_min;
