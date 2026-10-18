import { Resend } from 'resend'

// Perch's Send feedback lands here (Sources/Perch/FeedbackSender.swift posts it) and goes on to the maker of Perch by
// email, through Resend, with Reply-To set to the sender's email so Reply answers them. The form is multipart:
// `text`, `email` when given, `version` and `macos` while that switch is on, and each file as `file`.
// The same rules as the app (Sources/PerchCore/Feedback.swift), checked again: the app is not the only thing that can post.

const MAX_FILES = 6
const MAX_BYTES = 4 * 1024 * 1024 // a function takes 4.5 MB per request; the words fit in the rest
const MAX_TEXT = 20_000
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@.]{2,}$/

const say = (status: number, error: string) => Response.json({ ok: false, error }, { status })

export async function POST(request: Request) {
  const key = process.env.RESEND_API_KEY
  const to = process.env.FEEDBACK_TO
  if (!key || !to) return say(503, 'not set up')

  let form: FormData
  try {
    form = await request.formData()
  } catch {
    return say(400, 'not a form')
  }
  // a form sends its line breaks as \r\n; the email reads better with plain ones
  const field = (name: string, max: number) => String(form.get(name) ?? '').replace(/\r\n/g, '\n').slice(0, max).trim()
  const text = field('text', MAX_TEXT)
  const email = field('email', 320)
  const version = field('version', 40)
  const macos = field('macos', 20)
  const files = form.getAll('file').filter((f): f is File => f instanceof File)

  if (!text && files.length === 0) return say(400, 'nothing to send')
  if (files.length > MAX_FILES) return say(413, 'too many files')
  if (files.reduce((n, f) => n + f.size, 0) > MAX_BYTES) return say(413, 'too big')

  const replyTo = EMAIL.test(email) ? email : undefined
  const attached = await Promise.all(
    files.map(async (f, i) => ({
      name: f.name.replace(/[\r\n"]/g, '').slice(0, 120) || 'file',
      size: f.size,
      type: f.type,
      // a picture is shown in the message itself, by this id; anything else is only attached
      id: f.type.startsWith('image/') ? `file${i}` : undefined,
      content: Buffer.from(await f.arrayBuffer()).toString('base64'),
    })),
  )
  const mail = render({ text, replyTo, version, macos, files: attached })

  const { error } = await new Resend(key).emails.send({
    from: process.env.FEEDBACK_FROM || 'Perch feedback <onboarding@resend.dev>',
    to,
    replyTo,
    subject: subject(text),
    html: mail.html,
    text: mail.text,
    attachments: attached.map((f) => ({ filename: f.name, content: f.content, contentType: f.type || undefined, contentId: f.id })),
  })
  if (error) {
    console.error('feedback not sent', error)
    return say(502, 'not sent')
  }
  return Response.json({ ok: true })
}

// "Perch feedback: <the first line>", cut at a word near 60 characters, as the app's Mail draft has it
function subject(text: string) {
  const first = text.split(/\r?\n/)[0]?.trim() ?? ''
  if (!first) return 'Perch feedback'
  if (first.length <= 60) return `Perch feedback: ${first}`
  const cut = first.slice(0, 60)
  const at = cut.lastIndexOf(' ')
  return `Perch feedback: ${(at > 0 ? cut.slice(0, at) : cut).trim()}…`
}

type Shown = { name: string; size: number; type: string; id?: string }

// The email, as Perch's own pages look: the words first, a picture shown where it was attached, then who to answer and
// which build it came from, quiet and small. Tables and inline styles, so every mail app draws it the same; a plain
// text version beside it.
export function render(m: { text: string; replyTo?: string; version?: string; macos?: string; files: Shown[] }) {
  const font = `-apple-system, BlinkMacSystemFont, 'Inter', 'Segoe UI', Helvetica, Arial, sans-serif`
  const esc = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')
  const size = (b: number) => (b >= 1048576 ? `${(b / 1048576).toFixed(1)} MB` : `${Math.max(1, Math.round(b / 1024))} KB`)
  const build = m.version ? `Perch ${m.version}${m.macos ? ` \u00b7 macOS ${m.macos}` : ''}` : 'Versions not included'
  const words = m.text
    ? m.text.split(/\n{2,}/).map((p) => `<p style="margin:0 0 14px;">${esc(p).replace(/\n/g, '<br>')}</p>`).join('')
    : `<p style="margin:0 0 14px;color:#a1a1aa;">Only files, no words.</p>`
  const pictures = m.files.filter((f) => f.id).map((f) =>
    `<img src="cid:${f.id}" alt="${esc(f.name)}" width="512" style="display:block;width:100%;max-width:512px;height:auto;border:1px solid #ececef;border-radius:10px;margin:6px 0 0;">` +
    `<div style="font:400 12px/18px ${font};color:#a1a1aa;margin:6px 0 10px;">${esc(f.name)} \u00b7 ${size(f.size)}</div>`).join('')
  const others = m.files.filter((f) => !f.id).map((f) =>
    `<div style="font:400 13px/20px ${font};color:#52525b;">${esc(f.name)} <span style="color:#a1a1aa;">\u00b7 ${size(f.size)}, attached</span></div>`).join('')
  const answer = m.replyTo
    ? `Reply to answer <a href="mailto:${esc(m.replyTo)}" style="color:#18181b;text-decoration:none;font-weight:500;">${esc(m.replyTo)}</a>`
    : `No email given, so there is no way to answer.`
  const html = `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light only"><meta name="supported-color-schemes" content="light"><title>Perch feedback</title></head>
<body style="margin:0;padding:0;background:#f4f4f5;-webkit-font-smoothing:antialiased;">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;">${esc(m.text.slice(0, 110))}</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#f4f4f5;"><tr><td align="center" style="padding:28px 14px 36px;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:560px;">
<tr><td style="padding:0 6px 12px;font:500 13px/20px ${font};color:#71717a;">
<img src="https://perchapp.dev/apple-touch-icon.png" width="20" height="20" alt="" style="display:inline-block;vertical-align:-5px;border-radius:5px;margin-right:8px;">Perch feedback</td></tr>
<tr><td style="background:#ffffff;border-radius:14px;padding:24px 24px 22px;">
<div style="font:400 15px/24px ${font};color:#18181b;">${words}</div>
${pictures}${others ? `<div style="margin:4px 0 6px;">${others}</div>` : ''}
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin-top:14px;"><tr><td style="background:#f4f4f5;border-radius:10px;padding:12px 14px;font:400 13px/21px ${font};color:#52525b;">${answer}<br><span style="color:#a1a1aa;">${esc(build)}</span></td></tr></table>
</td></tr>
<tr><td style="padding:14px 6px 0;font:400 12px/18px ${font};color:#a1a1aa;">Sent from Send feedback, in Perch\u2019s Settings.</td></tr>
</table></td></tr></table></body></html>`
  const text = [
    m.text || '(Only files, no words.)',
    '',
    m.replyTo ? `Reply to answer ${m.replyTo}` : 'No email given, so there is no way to answer.',
    build,
    ...(m.files.length ? ['', ...m.files.map((f) => `${f.name} (${size(f.size)})`)] : []),
  ].join('\n')
  return { html, text }
}

