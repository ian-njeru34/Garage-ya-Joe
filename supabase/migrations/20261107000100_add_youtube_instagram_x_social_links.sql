alter table public.business_social_links
  add column if not exists youtube_url text,
  add column if not exists instagram_url text,
  add column if not exists x_url text;
alter table public.business_social_links
  drop constraint if exists business_social_links_youtube_https,
  drop constraint if exists business_social_links_instagram_https,
  drop constraint if exists business_social_links_x_https;
alter table public.business_social_links
  add constraint business_social_links_youtube_https check (youtube_url is null or youtube_url ~ '^https://(www\\.)?(youtube\\.com|youtu\\.be)/'),
  add constraint business_social_links_instagram_https check (instagram_url is null or instagram_url ~ '^https://(www\\.)?instagram\\.com/'),
  add constraint business_social_links_x_https check (x_url is null or x_url ~ '^https://(www\\.)?(x\\.com|twitter\\.com)/');
