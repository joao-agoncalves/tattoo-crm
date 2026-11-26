import { createClient } from "@supabase/supabase-js";

// Cliente com permissão total — usar SOMENTE no servidor (rotas de API).
export function supabaseAdmin() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) throw new Error("Supabase não configurado (variáveis de ambiente)");
  return createClient(url, key, { auth: { persistSession: false } });
}
