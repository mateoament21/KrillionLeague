# Krillion League & Cup

Log your daily Krillion score, compete in leagues (up to 20 players) and World Cup-style tournaments.
A static site (one `index.html`) with Supabase for accounts and data. No build step.

## Files
- `index.html` – the whole app
- `config.js` – your Supabase URL and anon key
- `supabase/schema.sql` – database table, security rules and live updates

## Set-up
1. **Supabase**: create a free project at supabase.com. Open *SQL Editor*, paste `supabase/schema.sql`, run it.
2. **Keys**: *Project Settings → API*: copy the Project URL and the Publishable key (sb_publishable_...) into `config.js`.
3. **Email settings**: *Authentication → Sign In / Providers → Email*. Either turn off "Confirm email"
   (friends can sign up instantly), or add your own SMTP under *Authentication → Emails*.
   Supabase's built-in email only sends a handful of emails per hour.
4. **GitHub**: create a repo, upload these files, commit.
5. **Vercel**: *Add New → Project*, import the repo, Framework preset "Other", no build command, Deploy.
6. **Redirect URL**: back in Supabase, *Authentication → URL Configuration*: set Site URL to your
   Vercel address (e.g. `https://krillion-league.vercel.app`) and add it under Redirect URLs.
7. **Admin**: sign up on the site, then run
   `insert into public.admins (email) values ('your@email');` in the SQL editor.
