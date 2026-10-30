/// The files Live status adds to OpenCode and pi. They post to Perch's socket in the same words Claude Code's hooks use
/// (UserPromptSubmit, PostToolUse, PermissionRequest, Stop, StopFailure, Interrupt), so Perch reads every agent the same way.
/// Each starts with HookInstaller.pluginMark, which is how Perch knows the file is its own.
enum PerchPlugins {
    static let body: [String: String] = ["opencode": opencode, "pi": pi]

    /// OpenCode loads it from ~/.config/opencode/plugins. It never waits on Perch: OpenCode's own prompt shows as usual,
    /// and a request Perch can answer is held open beside it. Whichever answers first wins; an answer from Perch goes
    /// back through OpenCode itself, and one given in OpenCode lets Perch's request go.
    /// One file serves both OpenCode 1 and 2: a default export with an id, OpenCode 1's `server` (read since 1.4) and
    /// OpenCode 2's `setup`. Each ignores the other's key. Before 1.4, OpenCode called every export as a function.
    static let opencode = #"""
    // Perch: tells Perch what OpenCode is doing, so the notch knows the moment it needs you and can answer it.
    // Perch wrote this file and removes it when you turn Live status off in its Settings. It does nothing while Perch is not running.
    import { existsSync } from "node:fs";
    import { homedir } from "node:os";
    import { execFile } from "node:child_process";

    const sock = homedir() + "/.config/perch/perch.sock";

    function post(event, body, signal) {
      if (!existsSync(sock)) return Promise.resolve("");
      return fetch("http://perch/opencode/" + event, {
        method: "POST", unix: sock, signal, headers: { "Content-Type": "application/json" }, body: JSON.stringify(body),
      }).then((r) => r.text()).catch(() => "");
    }

    // A request Perch can answer: held open until you answer it there, or here (then it is let go).
    function requests(send) {
      const held = new Map();
      return {
        hold(id, body, answer) {
          const stop = new AbortController();
          held.set(id, stop);
          send("PermissionRequest", body, stop.signal).then((text) => {
            held.delete(id);
            let d;
            try { d = JSON.parse(text).hookSpecificOutput.decision; } catch (e) { return; }
            if (d) answer(d);
          });
        },
        settle(id) { const c = held.get(id); if (c) { held.delete(id); c.abort(); } },
        clear() { for (const c of held.values()) c.abort(); held.clear(); },
      };
    }

    // What a permission is about, in the shape Perch reads: the command, the file, the address.
    function input(kind, meta, patterns, title) {
      const first = patterns[0] || "";
      if (kind === "bash" || kind === "shell") return { command: meta.command || patterns.join(" && ") };
      if (kind === "webfetch") return { url: meta.url || first };
      if (["edit", "write", "read", "external_directory"].includes(kind)) return { filePath: meta.filepath || meta.filePath || meta.path || first };
      return { description: title || patterns.join(", ") };
    }

    // OpenCode 1 calls this with its client and hands every event to `event`.
    async function PerchPlugin({ client }) {
      const busy = new Set(), roles = new Map(), said = new Map();
      const send = (event, body, signal) => post(event, { ...body, pid: process.pid }, signal);
      const { hold, settle } = requests(send);
      const raw = client._client || client.client;
      const call = (url, path, body) => raw ? raw.post({ url, path, body, headers: { "Content-Type": "application/json" } }).catch(() => {}) : undefined;
      const finished = (id) => { if (busy.delete(id)) send("Stop", { session_id: id, last_assistant_message: said.get(id) }); };
      return {
        event: async ({ event }) => {
          const p = event.properties || {};
          switch (event.type) {
            case "session.status": {
              const t = p.status && p.status.type;
              if (t === "busy" && !busy.has(p.sessionID)) { busy.add(p.sessionID); send("UserPromptSubmit", { session_id: p.sessionID }); }
              if (t === "idle") finished(p.sessionID);
              break;
            }
            case "session.idle": finished(p.sessionID); break;
            case "session.error": {
              if (!p.sessionID) break;
              busy.delete(p.sessionID);
              send(p.error && p.error.name === "MessageAbortedError" ? "Interrupt" : "StopFailure", { session_id: p.sessionID });
              break;
            }
            case "message.updated": if (p.info) roles.set(p.info.id, p.info.role); break;
            case "message.part.updated": {
              const part = p.part || {};
              if (part.type === "text" && !part.synthetic && roles.get(part.messageID) === "assistant") said.set(part.sessionID, part.text);
              if (part.type === "tool" && part.state && (part.state.status === "completed" || part.state.status === "error")) {
                send("PostToolUse", { session_id: part.sessionID, tool_name: part.tool });
              }
              break;
            }
            case "permission.asked":
            case "permission.updated": {
              const id = p.id, session = p.sessionID;
              hold(id, { session_id: session, tool_name: p.permission || p.type, tool_input: input(p.permission || p.type, p.metadata || {}, p.patterns || (p.pattern ? [].concat(p.pattern) : []), p.title) }, async (d) => {
                const reply = d.behavior === "allow" ? "once" : "reject";
                const done = await call("/permission/{requestID}/reply", { requestID: id }, { reply });
                if ((!done || done.error) && client.postSessionIdPermissionsPermissionId) {
                  await client.postSessionIdPermissionsPermissionId({ path: { id: session, permissionID: id }, body: { response: reply } }).catch(() => {});
                }
              });
              break;
            }
            case "permission.replied": settle(p.requestID || p.permissionID); break;
            case "question.asked": {
              const id = p.id, qs = p.questions || [];
              const questions = qs.map((q) => ({ question: q.question, header: q.header, multiSelect: !!q.multiple, options: q.options || [] }));
              hold(id, { session_id: p.sessionID, tool_name: "AskUserQuestion", tool_input: { questions } }, (d) => {
                if (d.behavior !== "allow") return call("/question/{requestID}/reject", { requestID: id }, {});
                const a = (d.updatedInput && d.updatedInput.answers) || {};
                return call("/question/{requestID}/reply", { requestID: id }, { answers: qs.map((q) => { const t = String(a[q.question] || ""); return (q.multiple ? t.split(", ") : [t]).filter(Boolean); }) });
              });
              break;
            }
            case "question.replied":
            case "question.rejected": settle(p.requestID); break;
          }
        },
      };
    }

    // OpenCode 2 runs plugins in its background service, one for every terminal and the app. It reads every event
    // from the context and answers through it, or through `opencode api` for a form, which a plugin cannot reach.
    async function setup(ctx) {
      const said = new Map(), tools = new Map(), stop = new AbortController();
      const { hold, settle, clear } = requests(post);
      const api = (op, params, body) => new Promise((done) => {
        const args = ["api", op, ...Object.entries(params).flatMap(([k, v]) => ["--param", k + "=" + v])];
        if (body) args.push("--data", JSON.stringify(body));
        execFile(process.execPath, args, { timeout: 15000 }, () => done());
      });
      const on = (event) => {
        const d = event.data || {}, id = d.sessionID;
        switch (event.type) {
          case "session.execution.started": said.delete(id); post("UserPromptSubmit", { session_id: id }); break;
          case "session.execution.succeeded": post("Stop", { session_id: id, last_assistant_message: said.get(id) }); break;
          case "session.execution.interrupted": post("Interrupt", { session_id: id }); break;
          case "session.execution.failed": post("StopFailure", { session_id: id }); break;
          case "session.text.ended": if (d.text && d.text.trim()) said.set(id, d.text); break;
          case "session.tool.input.started": tools.set(d.id, d.name); break;
          case "session.tool.success":
          case "session.tool.failed": post("PostToolUse", { session_id: id, tool_name: tools.get(d.id) || "tool" }); tools.delete(d.id); break;
          case "permission.asked": {
            const tool_input = input(d.action, d.metadata || {}, d.resources || [], d.message);
            hold(d.id, { session_id: id, tool_name: d.action, tool_input }, (a) =>
              ctx.permission.reply({ sessionID: id, requestID: d.id, decision: a.behavior === "allow" ? "once" : "reject" }).catch(() => {}));
            break;
          }
          case "permission.replied": settle(d.requestID); break;
          // The question tool asks through a form: one field for each question, its options by label.
          case "form.created": {
            const form = d.form || {}, fields = (form.fields || []).filter((f) => !f.hidden);
            if ((form.metadata || {}).kind !== "question" || !fields.length) break;
            const questions = fields.map((f) => ({ question: f.description || f.title || "", header: f.title || "", multiSelect: f.type === "multiselect",
              options: (f.options || []).map((o) => ({ label: o.label || o.value, description: o.description || "" })) }));
            const where = { sessionID: form.sessionID, formID: form.id };
            hold(form.id, { session_id: form.sessionID, tool_name: "AskUserQuestion", tool_input: { questions } }, (a) => {
              if (a.behavior !== "allow") return api("session.form.cancel", where);
              const given = (a.updatedInput && a.updatedInput.answers) || {}, answer = {};
              fields.forEach((f, i) => {
                const value = (label) => { const o = (f.options || []).find((o) => (o.label || o.value) === label); return o ? o.value : label; };
                const picked = String(given[questions[i].question] || "");
                if (f.type === "multiselect") answer[f.key] = picked.split(", ").filter(Boolean).map(value);
                else if (picked) answer[f.key] = value(picked);
              });
              return api("session.form.reply", where, { answer });
            });
            break;
          }
          case "form.replied":
          case "form.cancelled": settle(d.id); break;
        }
      };
      (async () => {
        for await (const event of ctx.event.subscribe({ signal: stop.signal })) { try { on(event); } catch (e) {} }
      })().catch(() => {});
      return () => { stop.abort(); clear(); };
    }

    // OpenCode 1 (1.4 and later) runs `server`; OpenCode 2 runs `setup`.
    export default { id: "perch", server: PerchPlugin, setup };

    """#

    /// pi loads it from ~/.pi/agent/extensions. pi has no permission prompts of its own; when an extension asks you
    /// something in the terminal, the card shows it and Pick up takes you there.
    static let pi = #"""
    // Perch: tells Perch what pi is doing, so the notch knows the moment it finishes or asks you something.
    // Perch wrote this file and removes it when you turn Live status off in its Settings. It does nothing while Perch is not running.
    import { request } from "node:http";
    import { existsSync } from "node:fs";
    import { homedir } from "node:os";

    const sock = homedir() + "/.config/perch/perch.sock";

    function post(event: string, body: Record<string, unknown>) {
      if (!existsSync(sock)) return;
      const data = JSON.stringify({ ...body, pid: process.pid });
      const req = request({ socketPath: sock, path: "/pi/" + event, method: "POST",
        headers: { "Content-Type": "application/json", "Content-Length": Buffer.byteLength(data) } });
      req.on("error", () => {});
      req.end(data);
    }

    function text(message: any): string | undefined {
      const blocks = Array.isArray(message?.content) ? message.content : [];
      const t = blocks.filter((b: any) => b?.type === "text").map((b: any) => b.text).join("\n\n").trim();
      return t || undefined;
    }

    export default function (pi: any) {
      let said: string | undefined, failed = false, aborted = false;
      const id = (ctx: any) => ctx?.sessionManager?.getSessionId?.() ?? "";
      const on = (event: string, handler: (e: any, ctx: any) => void) => {
        try { pi.on(event, async (e: any, ctx: any) => { try { handler(e, ctx); } catch {} }); } catch {}
      };
      on("agent_start", (_e, ctx) => { said = undefined; failed = false; aborted = false; post("UserPromptSubmit", { session_id: id(ctx) }); });
      on("tool_execution_end", (e, ctx) => post("PostToolUse", { session_id: id(ctx), tool_name: e.toolName }));
      on("message_end", (e) => {
        if (e.message?.role !== "assistant") return;
        said = text(e.message) ?? said;
        failed = e.message.stopReason === "error";
        aborted = e.message.stopReason === "aborted";
      });
      on("agent_settled", (e, ctx) => {
        if (e.aborted || aborted) post("Interrupt", { session_id: id(ctx) });
        else if (failed) post("StopFailure", { session_id: id(ctx) });
        else post("Stop", { session_id: id(ctx), last_assistant_message: said });
      });
      // An extension asks you something in the terminal (pi 1.0 and later).
      on("ui_prompt_start", (e, ctx) => post("PermissionRequest", { session_id: id(ctx), tool_name: "pi_prompt", tool_input: { question: e.title ?? "", kind: e.kind } }));
      on("ui_prompt_end", (_e, ctx) => post("PostToolUse", { session_id: id(ctx), tool_name: "pi_prompt" }));
    }

    """#
}
