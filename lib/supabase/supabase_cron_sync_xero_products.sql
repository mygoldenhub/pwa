-- Enable extensions once (safe to run multiple times)
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- 1. Remove the old broken job
select cron.unschedule('xero_sync_items_from8_to8');

-- 2. Re-create the job with correct authorization headers
select cron.schedule(
  'xero_sync_items_from8_to8',
  '0 20-23,0-8 * * *',
  $$
  select
    net.http_post(
      url := 'https://xegupowytmmqlrdtille.supabase.co/functions/v1/sync_xero_items',
      headers := jsonb_build_object(
        'content-type', 'application/json',
        -- Use Authorization Bearer header so the Edge Function accepts the incoming trigger
        'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhlZ3Vwb3d5dG1tcWxyZHRpbGxlIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3OTMxNTY3NywiZXhwIjoyMDk0ODkxNjc3fQ.hM-0w_1cvy2kKpa6rbAkVL6kWAOLZfK4fArqH8P3bz8'
      ),
      body := '{}'::jsonb
    );
  $$
);
