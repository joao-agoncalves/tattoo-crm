-- =============================================================
-- Tattoo CRM — estrutura inicial (multi-estúdio)
-- Cada tatuador/estúdio é um "studio". Todos os dados ficam
-- isolados por studio_id com Row Level Security (RLS).
-- =============================================================

create extension if not exists "pgcrypto";

-- ---------- Tipos ----------
create type member_role as enum ('owner', 'staff', 'agency');
create type lead_source as enum ('ad', 'organic');
create type msg_direction as enum ('inbound', 'outbound');
create type msg_sender as enum ('contact', 'ai', 'human_dashboard', 'human_phone', 'system');
create type opp_stage as enum ('novo', 'qualificado', 'orcamento_enviado', 'agendado', 'realizado', 'perdido');
create type quote_status as enum ('enviado', 'aceito', 'recusado');
create type deposit_status as enum ('nao_cobrado', 'pendente', 'pago');
create type appt_status as enum ('marcado', 'realizado', 'cancelado', 'faltou');

-- ---------- Estúdios e membros ----------
create table studios (
  id              uuid primary key default gen_random_uuid(),
  name            text not null,
  slug            text unique not null,
  commission_rate numeric(5,2) not null default 0,   -- % sobre vendas vindas de anúncio
  monthly_fee     numeric(10,2) not null default 0,
  timezone        text not null default 'America/Sao_Paulo',
  created_at      timestamptz not null default now()
);

create table studio_members (
  studio_id  uuid not null references studios(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  role       member_role not null default 'owner',
  created_at timestamptz not null default now(),
  primary key (studio_id, user_id)
);

-- Função usada por todas as políticas de segurança
create or replace function is_member(p_studio uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from studio_members
    where studio_id = p_studio and user_id = auth.uid()
  );
$$;

-- ---------- WhatsApp ----------
-- Provedor atual: UAZAPI (conexão por QR code, o tatuador continua usando o celular).
-- O campo provider deixa a porta aberta para a API oficial (Cloud API) no futuro.
create table whatsapp_accounts (
  id              uuid primary key default gen_random_uuid(),
  studio_id       uuid not null references studios(id) on delete cascade,
  provider        text not null default 'uazapi',   -- 'uazapi' | 'cloud_api'
  instance_id     text not null unique,             -- instância na UAZAPI (roteia o webhook ao estúdio certo)
  api_base_url    text,                             -- ex.: https://suaconta.uazapi.com
  display_phone   text,
  status          text,                             -- connected / disconnected
  created_at      timestamptz not null default now()
);

-- Tokens ficam separados e SEM acesso pelo navegador (só o servidor lê)
create table whatsapp_credentials (
  whatsapp_account_id uuid primary key references whatsapp_accounts(id) on delete cascade,
  instance_token      text not null,
  webhook_secret      text not null default encode(gen_random_bytes(24), 'hex'),
  updated_at          timestamptz not null default now()
);

-- Log bruto de tudo que chega no webhook (para auditoria e para ajustar a leitura dos anúncios)
create table webhook_events (
  id                  bigserial primary key,
  whatsapp_account_id uuid references whatsapp_accounts(id) on delete set null,
  payload             jsonb not null,
  processed           boolean not null default false,
  error               text,
  received_at         timestamptz not null default now()
);

-- ---------- Contatos (leads) ----------
create table contacts (
  id               uuid primary key default gen_random_uuid(),
  studio_id        uuid not null references studios(id) on delete cascade,
  wa_id            text not null,            -- número do cliente no WhatsApp
  name             text,
  -- Atribuição: gravada na PRIMEIRA mensagem e nunca sobrescrita
  source           lead_source not null default 'organic',
  ctwa_clid        text,                     -- nem sempre vem pela UAZAPI
  ad_source_id     text,                     -- ID do anúncio
  ad_source_type   text,
  ad_headline      text,
  ad_source_url    text,
  first_message_at timestamptz,
  created_at       timestamptz not null default now(),
  unique (studio_id, wa_id)
);

-- ---------- Conversas e mensagens ----------
create table conversations (
  id              uuid primary key default gen_random_uuid(),
  studio_id       uuid not null references studios(id) on delete cascade,
  contact_id      uuid not null references contacts(id) on delete cascade,
  ai_enabled      boolean not null default true,   -- botão liga/desliga IA
  last_message_at timestamptz,
  last_inbound_at timestamptz,                     -- para controlar a janela de 24h
  unread_count    int not null default 0,
  created_at      timestamptz not null default now(),
  unique (studio_id, contact_id)
);

create table messages (
  id              uuid primary key default gen_random_uuid(),
  studio_id       uuid not null references studios(id) on delete cascade,
  conversation_id uuid not null references conversations(id) on delete cascade,
  wamid           text unique,                     -- ID da Meta (evita duplicar)
  direction       msg_direction not null,
  sender          msg_sender not null,
  type            text not null default 'text',
  body            text,
  media_id        text,
  status          text,                            -- sent / delivered / read / failed
  raw             jsonb,
  sent_at         timestamptz not null default now()
);
create index on messages (conversation_id, sent_at);

-- ---------- Oportunidades (funil) ----------
create table opportunities (
  id          uuid primary key default gen_random_uuid(),
  studio_id   uuid not null references studios(id) on delete cascade,
  contact_id  uuid not null references contacts(id) on delete cascade,
  stage       opp_stage not null default 'novo',
  title       text,
  style       text,
  body_area   text,
  size        text,
  notes       text,
  lost_reason text,
  source      lead_source not null default 'organic',  -- copiado do contato
  ctwa_clid   text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index on opportunities (studio_id, stage);

create table quotes (
  id             uuid primary key default gen_random_uuid(),
  studio_id      uuid not null references studios(id) on delete cascade,
  opportunity_id uuid not null references opportunities(id) on delete cascade,
  amount         numeric(10,2) not null,
  description    text,
  status         quote_status not null default 'enviado',
  sent_at        timestamptz not null default now()
);

create table appointments (
  id             uuid primary key default gen_random_uuid(),
  studio_id      uuid not null references studios(id) on delete cascade,
  opportunity_id uuid not null references opportunities(id) on delete cascade,
  starts_at      timestamptz not null,
  ends_at        timestamptz,
  deposit_amount numeric(10,2),
  deposit_status deposit_status not null default 'nao_cobrado',
  status         appt_status not null default 'marcado',
  notes          text,
  created_at     timestamptz not null default now()
);
create index on appointments (studio_id, starts_at);

-- ---------- Vendas e comissão ----------
create table sales (
  id                uuid primary key default gen_random_uuid(),
  studio_id         uuid not null references studios(id) on delete cascade,
  opportunity_id    uuid not null references opportunities(id) on delete cascade,
  amount            numeric(10,2) not null,
  attributed_to_ads boolean not null default false,
  commission_rate   numeric(5,2) not null default 0,
  commission_amount numeric(10,2) generated always as
                    (case when attributed_to_ads then round(amount * commission_rate / 100, 2) else 0 end) stored,
  confirmed_by      uuid references auth.users(id),
  confirmed_at      timestamptz not null default now(),
  capi_sent_at      timestamptz,                    -- quando o evento Purchase foi enviado à Meta
  capi_response     jsonb
);

-- Preenche atribuição e % de comissão automaticamente ao registrar a venda
create or replace function sales_fill_defaults()
returns trigger language plpgsql as $$
begin
  select (o.source = 'ad'), s.commission_rate
    into new.attributed_to_ads, new.commission_rate
  from opportunities o join studios s on s.id = o.studio_id
  where o.id = new.opportunity_id;
  return new;
end $$;

create trigger trg_sales_defaults before insert on sales
for each row execute function sales_fill_defaults();

-- ---------- Configuração do agente (usada na versão 2) ----------
create table agent_settings (
  studio_id    uuid primary key references studios(id) on delete cascade,
  enabled      boolean not null default false,
  persona      text,          -- tom de voz, nome do atendente
  knowledge    jsonb not null default '{}'::jsonb,  -- estilos, preços, política de sinal, endereço...
  updated_at   timestamptz not null default now()
);

-- updated_at automático
create or replace function touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

create trigger trg_opp_touch before update on opportunities
for each row execute function touch_updated_at();
create trigger trg_agent_touch before update on agent_settings
for each row execute function touch_updated_at();

-- =============================================================
-- Segurança (RLS): cada usuário só enxerga o próprio estúdio
-- =============================================================
alter table studios              enable row level security;
alter table studio_members       enable row level security;
alter table whatsapp_accounts    enable row level security;
alter table whatsapp_credentials enable row level security;  -- sem política = ninguém do navegador lê
alter table webhook_events       enable row level security;  -- idem
alter table contacts             enable row level security;
alter table conversations        enable row level security;
alter table messages             enable row level security;
alter table opportunities        enable row level security;
alter table quotes               enable row level security;
alter table appointments         enable row level security;
alter table sales                enable row level security;
alter table agent_settings       enable row level security;

create policy studios_read on studios for select using (is_member(id));
create policy members_read on studio_members for select using (is_member(studio_id));
create policy wa_read on whatsapp_accounts for select using (is_member(studio_id));

do $$
declare t text;
begin
  foreach t in array array['contacts','conversations','messages','opportunities',
                           'quotes','appointments','sales','agent_settings']
  loop
    execute format('create policy %1$s_all on %1$I for all
                    using (is_member(studio_id)) with check (is_member(studio_id))', t);
  end loop;
end $$;

-- =============================================================
-- Visão para a dashboard: funil e receita por anúncio
-- =============================================================
create or replace view v_ad_performance with (security_invoker = true) as
select
  c.studio_id,
  coalesce(c.ad_source_id, 'organico') as ad_id,
  max(c.ad_headline)                   as ad_headline,
  count(distinct c.id)                 as leads,
  count(distinct o.id) filter (where o.stage in ('agendado','realizado')) as agendados,
  count(distinct s.id)                 as vendas,
  coalesce(sum(s.amount), 0)           as receita,
  coalesce(sum(s.commission_amount), 0) as comissao
from contacts c
left join opportunities o on o.contact_id = c.id
left join sales s on s.opportunity_id = o.id
group by c.studio_id, coalesce(c.ad_source_id, 'organico');
