import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const reply = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });

const toHex = (bytes: ArrayBuffer) =>
  Array.from(new Uint8Array(bytes), (byte) => byte.toString(16).padStart(2, "0")).join("");

const constantTimeEqual = (left: string, right: string) => {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index += 1) {
    difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return difference === 0;
};

async function validBitlabsHash(unsignedUrl: string, suppliedHash: string, secret: string) {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-1" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(unsignedUrl));
  return constantTimeEqual(toHex(signature), suppliedHash.toLowerCase());
}

Deno.serve(async (req) => {
  try {
    if (req.method !== "GET") return reply({ error: "Method not allowed." }, 405);
    const secret = Deno.env.get("BITLABS_APP_SECRET") || "";
    if (!secret) return reply({ error: "BitLabs secret is not configured." }, 503);

    // BitLabs appends hash as the final parameter and signs the untouched URL
    // before it. Do not decode/re-encode the URL before validating it.
    const hashMarker = req.url.lastIndexOf("&hash=");
    if (hashMarker < 0) return reply({ error: "Missing callback hash." }, 401);
    const unsignedUrl = req.url.slice(0, hashMarker);
    const suppliedHash = req.url.slice(hashMarker + 6).split("&", 1)[0];
    if (!/^[0-9a-f]{40}$/i.test(suppliedHash) ||
        !await validBitlabsHash(unsignedUrl, suppliedHash, secret)) {
      return reply({ error: "Invalid callback hash." }, 401);
    }

    const params = new URL(req.url).searchParams;
    const userId = String(params.get("uid") || "");
    const transactionId = String(params.get("tx") || "");
    const amount = Math.round(Number(params.get("val") || "0"));
    const referenceId = String(params.get("ref") || "");
    if (!/^[0-9a-f-]{36}$/i.test(userId) || !transactionId || transactionId.length > 180 ||
        !Number.isSafeInteger(amount) || amount === 0 || Math.abs(amount) > 100000) {
      return reply({ error: "Invalid callback parameters." }, 400);
    }

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    const payload = Object.fromEntries(params.entries());
    delete payload.hash;
    const { data, error } = await admin.rpc("process_bitlabs_callback", {
      p_event_id: transactionId,
      p_user_id: userId,
      p_amount: amount,
      p_reference_id: referenceId || null,
      p_payload: payload,
    });
    if (error) throw error;
    return reply(data);
  } catch (error) {
    console.error(error);
    return reply({ error: error instanceof Error ? error.message : "Unexpected error." }, 500);
  }
});
