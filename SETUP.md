# Email login setup (Supabase)

Files: `index.html`, `config.js` (your own, with your URL and publishable key), `vercel.json`, `supabase/schema.sql`.
Put them all in your project and deploy to Vercel as before.

## 1. Create the tables (run the whole `schema.sql`, it now has 5 parts)
(One run creates accounts, memes, reactions and the picture storage. It is safe to run again.)
Supabase dashboard > **SQL Editor** > New query > paste `supabase/schema.sql` > **Run**.

## 2. Turn on email verification
Dashboard > **Authentication**:
- **Sign In / Providers > Email**: Email ON, **Confirm email ON**.
- Same page, password rules: minimum length **10**, require lower case, upper case and digits.
- **URL Configuration**: set **Site URL** to your Vercel address (https://your-site.vercel.app) and add it
  under **Redirect URLs** too. Verification and reset links only work for addresses listed here.

## 3. Make emails actually arrive
Supabase's built-in email service is only for testing: it is heavily limited and sends only to
your own team's addresses. For real users set up **Authentication > SMTP Settings** with a free
email service (for example Resend or Brevo) and use its details there.

## 4. Extra protection (recommended)
- **Authentication > Rate Limits**: keep the defaults or lower them.
- **Authentication > Attack Protection**: you can enable CAPTCHA (Cloudflare Turnstile).
  This needs extra code on the page that is not included yet.

## 5. Test it
Open your site > Sign up with a real email > click the link in the email > Log in.
Also try: wrong password, forgot password, resend verification email.

## What is secured, and what is not
- Passwords are hashed and stored by Supabase Auth. The page never saves them anywhere.
- Email must be verified before anyone counts as logged in.
- Login errors do not reveal whether an email has an account. The page also slows repeated
  wrong attempts, but that is only a courtesy. The real limits are Supabase's.
- `vercel.json` adds browser security headers (HTTPS only, no framing, restricted scripts).
- The key in `config.js` is the publishable key and is meant to be public. NEVER put a
  `service_role` or secret key in this site.
- Not included yet: two-factor login and CAPTCHA.

## Shared memes
- Everyone can look at memes without an account. Posting, reacting and deleting need a verified login.
- Pictures are shrunk in the browser (max 500 px) and stored in Supabase Storage in a folder named after
  the user's id. People can only add or delete pictures in their own folder.
- Nicknames are set by the server from the account, so nobody can post under someone else's name.
- Each person can post at most 10 memes per hour.
- New posts and reactions appear for everyone live.

## Where to connect the site to Supabase
The site connects through one small file: **`config.js`**. It needs two values:
1. Open https://supabase.com/dashboard and open your project.
2. Go to **Project Settings** (gear icon) > **API** (or **API Keys**).
3. Copy the **Project URL** (it ends in `.supabase.co`) into `SUPABASE_URL`.
4. Copy the **Publishable key** (older projects call it the `anon` key) into `SUPABASE_ANON_KEY`.
5. Save, upload to Vercel again.

Never paste the **secret** or **service_role** key anywhere in the site.
How to tell it worked: the login page no longer shows the "Demo mode" note.
Your `config.js` already has a project URL and key, so this step may already be done.

## Make yourself the admin (only you)
Admins can delete any meme, reaction and picture. Nobody can make themselves admin from the website:
the list lives in a table the website cannot read or change.
1. Sign up on your live site with your own email and verify it (so your account exists).
2. Supabase dashboard > **SQL Editor** > New query. Paste this with YOUR email, then Run:

```sql
insert into public.admins (user_id)
select id from auth.users where email = 'PUT-YOUR-EMAIL-HERE';
```
3. Log out and log in again on the site. The button will say "Log out (yourname · admin)" and every
   meme will show a ✕ for you.

To remove an admin later: `delete from public.admins where user_id in (select id from auth.users where email = '...');`
Keep your Supabase dashboard login safe too (use a strong password and two-step verification there),
because anyone with dashboard access can make admins.

## Trust this device and device recognition
- The login form has a **Trust this device** box. It is OFF by default.
  - **Ticked**: you stay logged in on that device, even after closing the browser.
  - **Not ticked**: you are logged out when you close the browser (or its tab), and also after 30 minutes
    of no activity.
- Every browser gets a random device ID. After login the site saves a short device name such as
  "Chrome on Windows" with the time it was last used.
- The first time an account is used on a new device, a yellow notice appears:
  "New device: ... If this was not you, change your password and sign out other devices."
- On the **Profile** page there is a **Your devices** list. For each device you can see whether it is trusted,
  switch trust on or off, or remove it. **Sign out other devices** logs the account out everywhere else.

Please read this honestly: device recognition shows you what is happening and lets you react, but it does
not block anyone who has the right password. The strongest protection is still a strong, unique password.
Supabase also offers two-factor login (an authenticator app) which can be added later.

## 2-step login (2FA), mobile number and the Accounts centre
There is a new **Account** button (the Accounts centre). It shows your security checkup and lets you:
- **Set up an authenticator app** (Google Authenticator, Microsoft Authenticator, Authy). Scan the QR code,
  type the 6-digit code, done. This works as soon as you run `schema.sql`; nothing else to set up.
- **Add a mobile number** to receive a text-message code. This needs an **SMS provider** connected in Supabase
  (Authentication > Sign In / Providers > Phone, with a service such as Twilio). Texts cost money, and phone
  2FA may need a paid Supabase plan, so check the dashboard. Until it is set up the site says
  "Text messages may not be set up yet". The authenticator app is free and works without it.
- **Change your password** and manage **devices** (moved here from the Profile page).

How it works at login: after the right password, people with 2FA are asked for a 6-digit code before they
count as logged in. Part 5 of `schema.sql` also makes the DATABASE refuse posting, reacting, deleting and
uploads for 2FA accounts unless the code was entered, so a stolen password alone is not enough.

After sign-up (and email verification) you are logged in, and a red **caution box** at the top tells you to
turn on 2FA. It disappears once 2FA is on. You can dismiss it, but it comes back the next time you log in.

Good to know:
- Turning on a 2FA method logs the account out of all other devices. This is Supabase's own safety rule.
- Supabase has no recovery codes. If someone loses their phone, you (the owner) can remove their 2FA method in
  the dashboard: Authentication > Users > open the user > remove the factor.
- Keep your own Supabase dashboard account protected with two-step verification too.

