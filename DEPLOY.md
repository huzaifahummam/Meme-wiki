# Put Meme Wiki online (Linux Mint)

Folder contents: index.html, config.js, vercel.json, SETUP.md, supabase/schema.sql

## Step 0. Try it on your own computer first (optional, 2 minutes)
1. Open the folder in the file manager, right-click an empty space > **Open in Terminal**.
2. Run:  python3 -m http.server 8000
3. Open Firefox and go to http://localhost:8000
4. Stop it later with Ctrl + C in the terminal.
(For email links to work from localhost, add http://localhost:8000 under Supabase > Authentication > URL Configuration > Redirect URLs.)

## Step 1. Set up Supabase (once)
Follow SETUP.md: run supabase/schema.sql in the SQL Editor, turn on "Confirm email", and set up email sending (SMTP).
Check that config.js has your Project URL and Publishable key.

## Step 2. Put the folder on GitHub (no terminal needed)
1. Make a free account at https://github.com and click **New repository**. Name it meme-wiki. Choose Public or Private. Create it.
2. On the new repository page click **uploading an existing file**.
3. Drag EVERYTHING from the meme-wiki folder into the page (including the supabase folder). Click **Commit changes**.

## Step 3. Publish with Vercel
1. Go to https://vercel.com and choose **Sign Up > Continue with GitHub**.
2. Click **Add New > Project**, pick your meme-wiki repository, click **Import**.
3. Leave the settings alone (Framework Preset: Other). Click **Deploy**.
4. After about a minute you get an address like https://meme-wiki-yourname.vercel.app . That is your website.

## Step 4. Tell Supabase your website address
Supabase > Authentication > URL Configuration:
- Site URL: your Vercel address
- Redirect URLs: add the same address
Without this, verification and password-reset emails will not bring people back to your site.

## Step 5. Test
Sign up with a real email, click the link in the email, log in, post a meme. Then make yourself admin (SETUP.md).

## Updating the site later
On GitHub open the file, click the pencil, paste the new version, Commit. Vercel publishes it automatically.

## Own domain name (optional, costs about $10-15 a year)
Buy a name from a registrar, then Vercel > your project > Settings > Domains > Add, and follow the instructions.
After that, put the new address in Supabase URL Configuration too.
