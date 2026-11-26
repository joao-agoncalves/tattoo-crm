import { NextRequest, NextResponse } from "next/server";
import { supabaseAdmin } from "@/lib/supabase-admin";

export const dynamic = "force-dynamic";

// URL para colar na UAZAPI:  https://SEU-SITE/api/whatsapp/webhook/<segredo>
// O segredo identifica de qual estúdio é o número (ou é a chave de captura temporária).
export async function POST(req: NextRequest, ctx: { params: Promise<{ secret: string }> }) {
  const { secret } = await ctx.params;
  const db = supabaseAdmin();

  let accountId: string | null = null;
  const { data: cred } = await db
    .from("whatsapp_credentials")
    .select("whatsapp_account_id")
    .eq("webhook_secret", secret)
    .maybeSingle();

  if (cred) {
    accountId = cred.whatsapp_account_id;
  } else if (!process.env.WEBHOOK_CAPTURE_SECRET || secret !== process.env.WEBHOOK_CAPTURE_SECRET) {
    return NextResponse.json({ ok: false }, { status: 401 });
  }

  let payload: unknown;
  try {
    payload = await req.json();
  } catch {
    payload = { _raw: await req.text().catch(() => "") };
  }

  // Passo 1: guardar tudo exatamente como chegou (prova + auditoria).
  const { error } = await db.from("webhook_events").insert({
    whatsapp_account_id: accountId,
    payload,
  });
  if (error) console.error("webhook_events insert", error);

  // Passo 2 (próxima etapa): interpretar a mensagem, atribuir anúncio, acionar o agente.
  return NextResponse.json({ ok: true });
}

export async function GET() {
  return NextResponse.json({ ok: true, service: "tattoo-crm webhook" });
}
