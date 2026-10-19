# Perch feedback

The one function behind Send feedback (Settings, the last row). Perch posts the words, an email if one was given, the
files on the card and, while that switch is on, Perch's and macOS's versions; this emails them to you through
[Resend](https://resend.com), with Reply-To set to the sender's email so Reply answers them. Nothing is stored.

## Set it up

1. A Resend account and an API key (Resend: API Keys, sending access is enough).
2. A Vercel project from this folder: `vercel --cwd feedback` (or import the repo in Vercel with Root Directory `feedback`).
3. Environment variables in that project (Settings: Environment Variables, Production):
   - `RESEND_API_KEY`: the key from step 1.
   - `FEEDBACK_TO`: your inbox.
   - `FEEDBACK_FROM` (optional): a sender on a domain you verified in Resend, like `Perch feedback <feedback@yourdomain>`.
     Without it, mail comes from `onboarding@resend.dev`, which Resend lets you send only to your own account's email.
4. A rate limit (Vercel: Firewall, Rate Limiting): `/api/feedback`, POST, a handful per IP per minute. The address is
   in the app, so anyone can post to it.
5. Deploy to production. If the URL is not `https://perch-feedback.vercel.app/api/feedback`, change
   `FeedbackSender.endpoint` in `Sources/Perch/FeedbackSender.swift`. `PERCH_FEEDBACK_URL` overrides it for one run.

## hello@perchapp.dev

Email it instead writes to `hello@perchapp.dev`. Resend receives mail for perchapp.dev (its MX records point at Resend)
and calls `api/inbound.ts` through its `email.received` webhook; that sends it on to `FEEDBACK_TO` with its words,
pictures and files, from "Dana via hello@perchapp.dev", Reply-To Dana. Resend keeps what it received, so a failed call
can be replayed from its dashboard. It needs, besides the above:

- `RESEND_INBOUND_KEY`: a Full access key (reading received mail needs it; `RESEND_API_KEY` only sends).
- `RESEND_WEBHOOK_SECRET`: the signing secret of the webhook (Resend: Webhooks, endpoint `/api/inbound`, event
  `email.received`). Calls without a valid signature get 400 or 401 and are never read.
- perchapp.dev added in Resend with Receiving on, and its records in Vercel DNS (`vercel dns add perchapp.dev ...`).

## What it checks

At most 6 files and 4 MB of them (a function takes 4.5 MB per request), 20,000 characters of words, something to send.
Reply-To only for an email that looks like one. The app checks the same (`Sources/PerchCore/Feedback.swift`).

Answers: 200 sent, 400 nothing or not a form, 413 too much, 502 Resend refused it (the reason is in the function's
logs), 503 not set up. Perch shows anything but 200 as Couldn't send, with Email it instead.

## Try it

`npm install`, then `npm run check` type-checks. To see the email without sending one, run the handler with `fetch`
stubbed, or point a test build at a `vercel dev` here: `PERCH_FEEDBACK_URL=http://localhost:3000/api/feedback`.
