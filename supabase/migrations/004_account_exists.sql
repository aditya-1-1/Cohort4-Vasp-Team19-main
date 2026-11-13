-- Lets the login say "no account with this email" instead of a wrong
-- password. Answers only yes or no for one email at a time.
create or replace function public.account_exists(p_email text)
returns boolean
language sql
stable
security definer set search_path = ''
as $$
  select exists (
    select 1 from auth.users where lower(email) = lower(trim(p_email))
  );
$$;

revoke execute on function public.account_exists(text) from public;
grant execute on function public.account_exists(text) to anon, authenticated;
