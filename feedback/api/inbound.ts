import { Resend } from 'resend'

// hello@perchapp.dev, the address Perch's Email it instead writes to. Resend receives mail for perchapp.dev (its MX
// records point there) and tells this route through its email.received webhook; the message goes on to FEEDBACK_TO with
// its words, pictures and files, Reply-To the person who wrote, so Reply answers them. Resend keeps what it received,
// so a failure here can be replayed from its dashboard.
//
// RESEND_WEBHOOK_SECRET: the webhook's signing secret. RESEND_INBOUND_KEY: a full-access key, which reading received
// mail needs (RESEND_API_KEY only sends). FEEDBACK_FROM: a sender on the verified domain, if there is one.

export async function POST(request: Request) {
  const key = process.env.RESEND_INBOUND_KEY || process.env.RESEND_API_KEY
  const secret = process.env.RESEND_WEBHOOK_SECRET
  const to = process.env.FEEDBACK_TO
  if (!key || !secret || !to) return say(503, 'not set up')

  // only Resend can call this: its signature over the exact body, checked before anything is read
  const payload = await request.text()
  const id = request.headers.get('svix-id')
  const timestamp = request.headers.get('svix-timestamp')
  const signature = request.headers.get('svix-signature')
  if (!id || !timestamp || !signature) return say(400, 'not signed')
  const resend = new Resend(key)
  let event
  try {
    event = resend.webhooks.verify({ payload, headers: { id, timestamp, signature }, webhookSecret: secret })
  } catch {
    return say(401, 'bad signature')
  }
  if (event.type !== 'email.received') return Response.json({ ok: true, ignored: event.type })

  // never a loop: mail to the inbox it forwards to is left alone
  const received = event.data.to.concat(event.data.received_for ?? []).map((a) => address(a).toLowerCase())
  if (received.includes(address(to).toLowerCase())) return Response.json({ ok: true, ignored: 'loop' })

  const { data: email, error } = await resend.emails.receiving.get(event.data.email_id)
  if (error || !email) {
    console.error('inbound: could not read', event.data.email_id, error)
    return say(502, 'could not read')
  }
  const { data: list, error: listError } = await resend.emails.receiving.attachments.list({ emailId: email.id })
  if (listError) {
    console.error('inbound: could not list files', email.id, listError)
    return say(502, 'could not read files')
  }
  const attachments = await Promise.all(
    (list?.data ?? []).map(async (a) => ({
      filename: a.filename || 'file',
      content: Buffer.from(await (await fetch(a.download_url)).arrayBuffer()).toString('base64'),
      contentType: a.content_type || undefined,
      contentId: a.content_id || undefined,
    })),
  )

  // "Dana via hello@perchapp.dev <the verified sender>": who wrote, at a glance, from an address Resend may send from
  const sender = email.reply_to?.[0] || email.from
  const via = event.data.to[0] ? address(event.data.to[0]) : 'perchapp.dev'
  const fromAddress = address(process.env.FEEDBACK_FROM || 'onboarding@resend.dev')
  const who = (name(sender) || address(sender)).replace(/["<>\r\n]/g, '').slice(0, 60)
  const { error: sendError } = await resend.emails.send({
    from: `"${who} via ${via}" <${fromAddress}>`,
    to,
    replyTo: sender,
    subject: email.subject || '(no subject)',
    ...(email.html ? { html: email.html } : {}),
    text: email.text || '',
    attachments,
  })
  if (sendError) {
    console.error('inbound: not forwarded', email.id, sendError)
    return say(502, 'not forwarded')
  }
  return Response.json({ ok: true })
}

const say = (status: number, error: string) => Response.json({ ok: false, error }, { status })

// "Dana Levi <dana@example.com>" -> "dana@example.com" and "Dana Levi"
export function address(a: string) {
  return (a.match(/<([^>]+)>/)?.[1] ?? a).trim()
}
export function name(a: string) {
  const m = a.match(/^\s*"?([^"<]*?)"?\s*</)
  return m ? m[1].trim() : ''
}
