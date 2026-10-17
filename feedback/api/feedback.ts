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
  const about = [
    replyTo ? `From ${replyTo} (Reply answers them)` : 'No email given',
    version ? `Perch ${version}${macos ? `, macOS ${macos}` : ''}` : 'Versions not included',
  ]
  const attachments = await Promise.all(
    files.map(async (f) => ({
      filename: f.name.replace(/[\r\n"]/g, '').slice(0, 120) || 'file',
      content: Buffer.from(await f.arrayBuffer()).toString('base64'),
      contentType: f.type || undefined,
    })),
  )

  const { error } = await new Resend(key).emails.send({
    from: process.env.FEEDBACK_FROM || 'Perch feedback <onboarding@resend.dev>',
    to,
    replyTo,
    subject: subject(text),
    text: `${text || '(Only files.)'}\n\n--\n${about.join('\n')}\n`,
    attachments,
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
