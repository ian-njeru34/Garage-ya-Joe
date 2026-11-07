-- The auth provisioning function is trigger-only and must never be callable over the Data API.
revoke all on function public.provision_auth_profile() from public, anon, authenticated;
