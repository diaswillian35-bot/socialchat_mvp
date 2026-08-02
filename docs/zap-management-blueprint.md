# Zap Management (app.acpaz.net) — Blueprint para versão moderna

> Documento de referência baseado em análise pública do portal (login, assets, CSS/JS).
> Use este arquivo como modelo funcional. Complete a seção **“Inventário interno”** após login.

---

## 1. Visão geral

| Item | Valor |
|------|--------|
| Nome atual | **Zap Management** |
| Empresa | A.C. Paz Construction Inc. (Toronto, CA) |
| URL | https://app.acpaz.net |
| Tipo | Portal operacional privado (equipe + clientes autorizados) |
| Domínio de negócio | Construção, reformas, obras residenciais/comerciais |

### Objetivo do sistema (inferido)
Centralizar operação de obras: equipe em campo, canteiros, documentos, contatos, filtros/listagens e mapa com GPS.

---

## 2. Stack atual (legado)

| Camada | Tecnologia |
|--------|------------|
| Reverse proxy | nginx |
| Backend | Java (Undertow) + JSP 2.2 |
| Sessão | Cookie `JSESSIONID` |
| Frontend | jQuery 2.1.4, jQuery UI 1.11.4, Material Design Lite |
| Upload | Dropzone.js |
| Tabelas | jQuery Tablesorter |
| Mapas | Google Maps (ícones customizados por estado) |
| Mobile | PWA-like (Apple touch icons, standalone mode script) |
| SSL | Wildcard `*.acpaz.net` (Amazon) |

### Endpoints públicos conhecidos
- `GET /` — tela de login
- `POST /user/authenticate` — autenticação (username, password, keepMeLoggedIn)
- `GET /home` — área autenticada (redireciona para login se sem sessão)

---

## 3. Módulos funcionais (inferidos por UI/CSS/JS)

### 3.1 Autenticação
- [ ] Login com username + password
- [ ] Checkbox “Keep me logged in”
- [ ] Mensagem de erro inline (`.error-login`)
- [ ] Redirecionamento HTTP → HTTPS

### 3.2 Layout / navegação
- [ ] Header fixo (Material Layout)
- [ ] Menu colapsável com submenus (`.acpaz__menu-collapsible`, `.acpaz__sub-menu`)
- [ ] Usuário logado + configurações (`.paz-logged-user`, `.paz-logged-user__settings`)
- [ ] Breadcrumbs (jquery-rcrumbs)

### 3.3 Mapas e geolocalização
Config em `ACPazConfig.Maps`:
- Posição do usuário (GPS manual)
- Posição automática
- Funcionário **em obra** (verde)
- Funcionário **finalizado** (vermelho)
- **Canteiro de obra** (ícone obra)

Controles inferidos:
- [ ] Botão mostrar mapa (`.paz-button__coord-map--show`)
- [ ] Botão GPS / track (`.paz-button__coord-gps`, `.paz-button__coord-gps--track`)
- [ ] Botão serviço de coordenadas (`.paz-button__coord-service`)
- [ ] Cálculo de distância Haversine (km) entre pontos

### 3.4 Listagens e dados
- [ ] Tabelas de dados (`.paz-data-table`, `.mdl-data-table`)
- [ ] Colunas fixas esquerda/direita em scroll horizontal
- [ ] Paginação custom (`.paz-paginate_*`)
- [ ] Tabelas resumidas (`.summarized__table`)
- [ ] Valor contratado (`.contracted-value`) — possível módulo financeiro/contrato

### 3.5 Filtros e busca
- [ ] Painel de filtros (`.paz-filter`, `.paz-filter-form`)
- [ ] Filtro por categorias (`.paz-button__filter--categories`)
- [ ] Combobox / select com tamanho e horário (`.paz-combobox__select-time`)

### 3.6 Formulários
- [ ] Formulários padrão (`.paz-form`, `.paz-form-wrapper`)
- [ ] Cards com título/subtítulo (`.paz-card--title`, `.paz-card--subtitle`)
- [ ] Comentários em overlay (`.paz-form-comments`, `.paz-comments-overlayer`)
- [ ] Slider (`.paz-slider`)
- [ ] Validação client-side (jquery.validate)

### 3.7 Uploads e mídia
- [ ] Upload de arquivos (Dropzone — `.paz-upload-container`)
- [ ] Tratamento de erro de imagem (`.paz-image_error`)

### 3.8 Contatos
- [ ] Bloco de contato com telefones (`.paz-contact`, `.paz-contact__phones`)

### 3.9 Erros e feedback
- [ ] Overlay genérico (`.paz-overlayer`)
- [ ] Detalhes de erro (`.paz-error-details`)

---

## 4. Inventário interno (preencher com login)

> **Não cole senhas neste arquivo.** Apenas descreva telas, campos e fluxos.

### Menu principal
| Item do menu | Rota (se visível) | O que faz | Roles |
|--------------|-------------------|-----------|-------|
| | | | |

### Telas
| Tela | Campos principais | Ações | Observações |
|------|-------------------|-------|-------------|
| | | | |

### Perfis de usuário
| Perfil | Permissões | Restrições |
|--------|------------|------------|
| Admin | | |
| Funcionário | | |
| Cliente | | |

### Entidades de dados (modelo)
```
User
  id, username, name, role, phone, active

ConstructionSite (Obra)
  id, name, address, lat, lng, clientId, status, contractedValue

Employee / FieldWorker
  id, name, phone, status [working|finished|offline], lastLat, lastLng, lastSeenAt

WorkSession / Check-in
  id, employeeId, siteId, startedAt, endedAt, gpsTrail[]

Document / Upload
  id, siteId, fileName, url, uploadedBy, createdAt

Contact
  id, name, phones[], email, relatedSiteId?

Comment
  id, entityType, entityId, authorId, text, createdAt

Category (filtros)
  id, name, parentId?
```

Ajuste nomes/campos após mapear o sistema real.

---

## 5. Proposta de versão moderna

### Stack recomendada (Flutter-friendly, alinhada ao seu ecossistema)

| Camada | Sugestão | Motivo |
|--------|----------|--------|
| App mobile + web | **Flutter** | Você já usa no Remdy; um codebase para iOS/Android/Web |
| Backend | **Firebase** ou **Supabase** | Auth, Firestore/Postgres, Storage, push |
| Auth | Email/senha + refresh token; opcional MFA | Substitui JSESSIONID |
| Mapas | **Google Maps Flutter** ou **Mapbox** | GPS em tempo real |
| Tempo real | Firestore listeners / Supabase Realtime | Posição de equipe ao vivo |
| Uploads | Firebase Storage / Supabase Storage | Substitui Dropzone |
| API custom | Cloud Functions / Edge Functions | Regras de negócio |

### Alternativa web-first
- **Next.js 15** + TypeScript + Tailwind + shadcn/ui
- **Prisma** + PostgreSQL
- **NextAuth** ou Clerk
- App mobile depois via React Native ou Flutter consumindo mesma API REST

---

## 6. Mapa legado → moderno

| Legado (Zap) | Moderno |
|--------------|---------|
| JSP + POST `/user/authenticate` | Auth provider (Firebase Auth / JWT) |
| JSESSIONID cookie | Secure httpOnly refresh + access token |
| jQuery tables + filters | DataTable server-side ou AG Grid / TanStack Table |
| Dropzone upload | Storage + progress UI nativo |
| Google Maps + ícones estáticos | Map widget + markers por status + clustering |
| Polling/manual refresh | WebSocket / Firestore realtime |
| Menu JSP server-rendered | Shell com bottom nav (mobile) + sidebar (web) |
| CSS Material Lite custom | Design system (Material 3 / Tailwind) |

---

## 7. MVP sugerido (fases)

### Fase 1 — Core (4–6 semanas)
1. Login + perfis (admin, funcionário, cliente)
2. CRUD de obras (canteiros)
3. Lista de funcionários
4. Mapa com pins: obra + funcionários
5. Upload de fotos por obra

### Fase 2 — Campo
1. GPS do funcionário (foreground + background limitado)
2. Check-in / check-out na obra
3. Status automático: working / finished
4. Notificações push (chegada, atraso)

### Fase 3 — Gestão
1. Filtros avançados e relatórios
2. Comentários por obra
3. Valor contratado / resumo financeiro
4. Export PDF/Excel

### Fase 4 — Cliente
1. Portal read-only para cliente ver andamento
2. Galeria de fotos da obra
3. Timeline de atividades

---

## 8. Modelo de telas (wireframe lógico)

```
[Login]
   ↓
[Home / Dashboard]
   ├── Mapa ao vivo (obras + equipe)
   ├── Obras (lista + filtros)
   │     └── Detalhe da obra
   │           ├── Info + valor contratado
   │           ├── Funcionários alocados
   │           ├── Fotos / documentos
   │           └── Comentários
   ├── Equipe (lista + status GPS)
   ├── Relatórios / resumos
   └── Configurações (perfil, logout)
```

---

## 9. Segurança na versão nova

- [ ] HTTPS everywhere; HSTS
- [ ] Senhas com hash (bcrypt/argon2) — nunca hardcoded
- [ ] RBAC por role (admin, employee, client)
- [ ] Rate limit no login
- [ ] Audit log (quem alterou o quê)
- [ ] GPS: consentimento explícito no mobile
- [ ] CSP, X-Frame-Options, cookies Secure + SameSite

---

## 10. Checklist para documentar com seu login

Faça login e preencha (screenshots opcionais em pasta separada):

1. Listar **todos os itens do menu** (nome + ordem)
2. Para cada item: capturar **campos do formulário** e **colunas da tabela**
3. Anotar **quem vê o quê** (se trocar de usuário)
4. Testar **mapa**: quais markers aparecem? Atualiza em tempo real?
5. Testar **upload**: tipos de arquivo, limite, onde aparece depois
6. Testar **filtros**: categorias disponíveis
7. Anotar **fluxos críticos** (ex.: criar obra → alocar funcionário → track GPS)
8. Exportar ou copiar **nomes de campos** visíveis (viram schema)

---

## 11. Próximo passo recomendado

1. Completar seção 4 (Inventário interno) com seu acesso
2. Validar entidades da seção 4 com stakeholders
3. Escolher stack (Flutter+Firebase vs Next+Postgres)
4. Scaffold do MVP Fase 1

---

*Gerado em: 2026-07-20 — análise externa de app.acpaz.net*
