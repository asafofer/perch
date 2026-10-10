/// The files Live status adds to OpenCode and pi. They post to Perch's socket in the same words Claude Code's hooks use
/// (UserPromptSubmit, PostToolUse, PermissionRequest, Stop, StopFailure, Interrupt), so Perch reads every agent the same way.
/// Each starts with HookInstaller.pluginMark, which is how Perch knows the file is its own.
enum PerchPlugins {
    static let body: [String: String] = ["opencode": opencode, "pi": pi]

    /// OpenCode loads it from ~/.config/opencode/plugins. It never waits on Perch: OpenCode's own prompt shows as usual,
    /// and a request Perch can answer is held open beside it. Whichever answers first wins; an answer from Perch goes
    /// back through OpenCode's own client, and one given in OpenCode lets Perch's request go.
    static let opencode = #"""
    // Perch: tells Perch what OpenCode is doing, so the notch knows the moment it needs you and can answer it.
    // Perch wrote this file and removes it when you turn Live status off in its Settings. It does nothing while Perch is not running.
    import { existsSync } from "node:fs";
    import { homedir } from "node:os";

    const sock = homedir() + "/.config/perch/perch.sock";

    function post(event, body, signal) {
      if (!existsSync(sock)) return Promise.resolve("");
      return fetch("http://perch/opencode/" + event, {
        method: "POST", unix: sock, signal, headers: { "Content-Type": "application/json" }, body: JSON.stringify({ ...body, pid: process.pid }),
      }).then((r) => r.text()).catch(() => "");
    }

    // What a permission is about, in the shape Perch reads: the command, the file, the address.
    function input(p) {
      const meta = p.metadata || {}, patterns = p.patterns || (p.pattern ? [].concat(p.pattern) : []), first = patterns[0] || "";
      const kind = p.permission || p.type;
      if (kind === "bash") return { command: meta.command || patterns.join(" && ") };
      if (kind === "webfetch") return { url: meta.url || first };
      if (["edit", "write", "read", "external_directory"].includes(kind)) return { filePath: meta.filepath || meta.filePath || first };
      return { description: p.title || patterns.join(", ") };
    }

    export const PerchPlugin = async ({ client }) => {
      const busy = new Set(), roles = new Map(), said = new Map(), held = new Map();
      const raw = client._client || client.client;
      const call = (url, path, body) => raw ? raw.post({ url, path, body, headers: { "Content-Type": "application/json" } }).catch(() => {}) : undefined;
      // A request Perch can answer: held open until you answer it there, or here (then it is let go).
      const hold = (id, body, answer) => {
        const stop = new AbortController();
        held.set(id, stop);
        post("PermissionRequest", body, stop.signal).then((text) => {
          held.delete(id);
          let d;
          try { d = JSON.parse(text).hookSpecificOutput.decision; } catch (e) { return; }
          if (d) answer(d);
        });
      };
      const settle = (id) => { const c = held.get(id); if (c) { held.delete(id); c.abort(); } };
      const finished = (id) => { if (busy.delete(id)) post("Stop", { session_id: id, last_assistant_message: said.get(id) }); };
      return {
        event: async ({ event }) => {
          const p = event.properties || {};
          switch (event.type) {
            case "session.status": {
              const t = p.status && p.status.type;
              if (t === "busy" && !busy.has(p.sessionID)) { busy.add(p.sessionID); post("UserPromptSubmit", { session_id: p.sessionID }); }
              if (t === "idle") finished(p.sessionID);
              break;
            }
            case "session.idle": finished(p.sessionID); break;
            case "session.error": {
              if (!p.sessionID) break;
              busy.delete(p.sessionID);
              post(p.error && p.error.name === "MessageAbortedError" ? "Interrupt" : "StopFailure", { session_id: p.sessionID });
              break;
            }
            case "message.updated": if (p.info) roles.set(p.info.id, p.info.role); break;
            case "message.part.updated": {
              const part = p.part || {};
              if (part.type === "text" && !part.synthetic && roles.get(part.messageID) === "assistant") said.set(part.sessionID, part.text);
              if (part.type === "tool" && part.state && (part.state.status === "completed" || part.state.status === "error")) {
                post("PostToolUse", { session_id: part.sessionID, tool_name: part.tool });
              }
              break;
            }
            case "permission.asked":
            case "permission.updated": {
              const id = p.id, session = p.sessionID;
              hold(id, { session_id: session, tool_name: p.permission || p.type, tool_input: input(p) }, async (d) => {
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
                return call("/question/{requestID}/reply", { requestID: id }, { answers: qs.map((q) => String(a[q.question] || "").split(", ").filter(Boolean)) });
              });
              break;
            }
            case "question.replied":
            case "question.rejected": settle(p.requestID); break;
          }
        },
      };
    };

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
