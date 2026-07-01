// SkinQuest v11.8.3 - support request email notifier
// Deploy with: supabase functions deploy support-notify
// Required secrets:
//   RESEND_API_KEY
//   SUPPORT_NOTIFY_TO=support@skinquestcs.com
//   SUPPORT_NOTIFY_FROM=SkinQuest Support <support@skinquestcs.com>
//   SUPPORT_WEBHOOK_SECRET=<random long secret>

const jsonHeaders = {
  "Content-Type": "application/json"
};

function escapeHtml(value: unknown): string {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function getRecord(payload: Record<string, unknown>): Record<string, unknown> {
  const record = payload.record ?? payload.new ?? payload;
  if (record && typeof record === "object" && !Array.isArray(record)) {
    return record as Record<string, unknown>;
  }
  return {};
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: jsonHeaders });
  }

  if (request.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: jsonHeaders
    });
  }

  const expectedSecret = Deno.env.get("SUPPORT_WEBHOOK_SECRET") || "";
  const suppliedSecret = request.headers.get("x-support-secret") || request.headers.get("authorization")?.replace(/^Bearer\s+/i, "") || "";

  if (!expectedSecret || suppliedSecret !== expectedSecret) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: jsonHeaders
    });
  }

  const resendApiKey = Deno.env.get("RESEND_API_KEY") || "";
  const notifyTo = Deno.env.get("SUPPORT_NOTIFY_TO") || "support@skinquestcs.com";
  const notifyFrom = Deno.env.get("SUPPORT_NOTIFY_FROM") || "SkinQuest Support <support@skinquestcs.com>";

  if (!resendApiKey) {
    return new Response(JSON.stringify({ error: "Missing RESEND_API_KEY" }), {
      status: 500,
      headers: jsonHeaders
    });
  }

  let payload: Record<string, unknown>;
  try {
    payload = await request.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON" }), {
      status: 400,
      headers: jsonHeaders
    });
  }

  const record = getRecord(payload);
  const id = record.id ?? "unknown";
  const topic = String(record.topic || "Support request").slice(0, 100);
  const email = String(record.account_email || "No email captured").slice(0, 254);
  const message = String(record.message || "").slice(0, 2000);
  const pageUrl = String(record.page_url || "Unknown page");
  const createdAt = String(record.created_at || new Date().toISOString());
  const browserLanguage = String(record.browser_language || "Unknown");
  const userAgent = String(record.user_agent || "Unknown");

  if (!message.trim()) {
    return new Response(JSON.stringify({ error: "Missing support message" }), {
      status: 400,
      headers: jsonHeaders
    });
  }

  const subject = `New SkinQuest support request: ${topic}`;
  const html = `
    <div style="font-family:Arial,sans-serif;line-height:1.55;color:#111827">
      <h2 style="margin:0 0 10px">New SkinQuest support request</h2>
      <p style="margin:0 0 16px;color:#4b5563">A new support request was submitted from the website.</p>
      <table style="border-collapse:collapse;width:100%;max-width:720px">
        <tr><td style="padding:8px;border:1px solid #e5e7eb"><b>ID</b></td><td style="padding:8px;border:1px solid #e5e7eb">${escapeHtml(id)}</td></tr>
        <tr><td style="padding:8px;border:1px solid #e5e7eb"><b>Topic</b></td><td style="padding:8px;border:1px solid #e5e7eb">${escapeHtml(topic)}</td></tr>
        <tr><td style="padding:8px;border:1px solid #e5e7eb"><b>Email</b></td><td style="padding:8px;border:1px solid #e5e7eb">${escapeHtml(email)}</td></tr>
        <tr><td style="padding:8px;border:1px solid #e5e7eb"><b>Page</b></td><td style="padding:8px;border:1px solid #e5e7eb">${escapeHtml(pageUrl)}</td></tr>
        <tr><td style="padding:8px;border:1px solid #e5e7eb"><b>Created</b></td><td style="padding:8px;border:1px solid #e5e7eb">${escapeHtml(createdAt)}</td></tr>
        <tr><td style="padding:8px;border:1px solid #e5e7eb"><b>Language</b></td><td style="padding:8px;border:1px solid #e5e7eb">${escapeHtml(browserLanguage)}</td></tr>
      </table>
      <h3 style="margin:18px 0 8px">Message</h3>
      <div style="white-space:pre-wrap;padding:12px;border:1px solid #e5e7eb;border-radius:10px;background:#f9fafb">${escapeHtml(message)}</div>
      <details style="margin-top:16px;color:#4b5563">
        <summary>Technical context</summary>
        <p style="white-space:pre-wrap">${escapeHtml(userAgent)}</p>
      </details>
    </div>
  `;

  const text = [
    "New SkinQuest support request",
    `ID: ${id}`,
    `Topic: ${topic}`,
    `Email: ${email}`,
    `Page: ${pageUrl}`,
    `Created: ${createdAt}`,
    "",
    "Message:",
    message,
    "",
    `User agent: ${userAgent}`
  ].join("\n");

  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${resendApiKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      from: notifyFrom,
      to: [notifyTo],
      reply_to: email.includes("@") ? email : undefined,
      subject,
      html,
      text
    })
  });

  const responseBody = await res.text();
  if (!res.ok) {
    console.error("Resend email failed", responseBody);
    return new Response(JSON.stringify({ error: "Email send failed", details: responseBody }), {
      status: 502,
      headers: jsonHeaders
    });
  }

  return new Response(JSON.stringify({ ok: true }), {
    status: 200,
    headers: jsonHeaders
  });
});
