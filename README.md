# Tattoo CRM

CRM + rastreamento de vendas no WhatsApp para estúdios de tatuagem.

- **Next.js** (Vercel): telas e rotas de API (webhook da UAZAPI, agente com Claude)
- **Supabase**: banco, login e segurança por estúdio (RLS)
- **UAZAPI**: conexão do WhatsApp por QR code

## Banco
Rode `supabase/migrations/0001_init.sql` no SQL Editor do Supabase.

## Variáveis
Veja `.env.example`. Valores reais ficam só na Vercel.

## Webhook
`https://SEU-SITE/api/whatsapp/webhook/<segredo>`
