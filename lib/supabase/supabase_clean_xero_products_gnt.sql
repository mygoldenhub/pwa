-- Run this in your Supabase SQL editor or as a migration
-- Creates the RPC function called by the Edge Function

CREATE OR REPLACE FUNCTION clean_xero_products_gnt()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  affected_rows integer;
BEGIN
  UPDATE "xero_products"
  SET
    "description" = regexp_replace(
      regexp_replace(
        regexp_replace("description", '\(\s*GNT\s*\)', '', 'g'),
        '\mGNT\M', '', 'g'
      ),
      '\(?\s*G&T\s*\)?', '', 'g'
    ),
    "purchase_description" = regexp_replace(
      regexp_replace(
        regexp_replace("purchase_description", '\(\s*GNT\s*\)', '', 'g'),
        '\mGNT\M', '', 'g'
      ),
      '\(?\s*G&T\s*\)?', '', 'g'
    ),
    "code" = regexp_replace(
      regexp_replace(
        regexp_replace("code", '\(\s*GNT\s*\)', '', 'g'),
        '\mGNT\M', '', 'g'
      ),
      '\(?\s*G&T\s*\)?', '', 'g'
    ),
    "name" = regexp_replace(
      regexp_replace(
        regexp_replace("name", '\(\s*GNT\s*\)', '', 'g'),
        '\mGNT\M', '', 'g'
      ),
      '\(?\s*G&T\s*\)?', '', 'g'
    )
  WHERE
    "description"          ILIKE '%GNT%' OR "description"          ILIKE '%G&T%' OR
    "purchase_description" ILIKE '%GNT%' OR "purchase_description" ILIKE '%G&T%' OR
    "code"                 ILIKE '%GNT%' OR "code"                 ILIKE '%G&T%' OR
    "name"                 ILIKE '%GNT%' OR "name"                 ILIKE '%G&T%';

  GET DIAGNOSTICS affected_rows = ROW_COUNT;

  RETURN json_build_object('rows_updated', affected_rows);
END;
$$;