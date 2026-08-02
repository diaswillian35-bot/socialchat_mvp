# Android App Links (DRAFT — não publicar Hosting nesta etapa)

Destino: `https://remdy.app/.well-known/assetlinks.json`

Arquivo: `docs/deeplinks/assetlinks.json.DRAFT`

## Conteúdo
- `package_name`: `com.remdy.app`
- relação: `delegate_permission/common.handle_all_urls`
- SHA-256 **Play App Signing** (distribuição via Google Play)
- SHA-256 **upload key Remdy** (necessário para App Links em builds release instaladas fora da Play / sideload QA)

## Manifest
Hosts HTTPS: `remdy.app` e `www.remdy.app` (`android:autoVerify="true"`).

## Live vs draft
O arquivo online hoje contém apenas o SHA-256 do App Signing.
O draft adiciona o SHA-256 da upload key para sideload.
Não publicar Hosting até autorização com plano de isolamento.
