# Google Sign-In — SHA obrigatório (Play Internal / Production)

## Causa raiz (2026-08-06)

O APK/AAB distribuído pela Google Play é **reassinado** com o certificado **App Signing** da Play.

Fingerprints confirmados:

| Certificado | SHA-1 | SHA-256 |
|-------------|-------|---------|
| Upload key (`remdy-upload.jks`) | `7EBE8B31740F8708C6C948BB8360D7A627680AFF` | `4E97471CC09C68A1502E113C2009F15F0015DE422997583431044C2FA5A613E4` |
| Debug keystore (máquina local) | `678AACD8BA9BF162F64623FC9823E23883BE0FF9` | `D9EF05E81A81808C21C209178122FCC06C44AEFF1E3E369EC8F7257A8B55930B` |
| Debug/legado `socialchat_mvp` | `FDF08986D283D4605CCD49530119A4E4A63C4417` | — |
| **Play App Signing** (Play Console, 2026-08-06) | `3A27A52CFDDF5AFE65A8D47DC279706E83852415` | `D8BFE88D70BD87CEBC3CACE11096594B93EEF2DAB4077B9E1E6E87E87649B91B` |
| assetlinks (histórico / outro) | — | `AAFDBF6CE986EC3960844FAC08CBA3B0CFBB7C0F4ED6B0789E0C92D4B4434711` |

## Correção aplicada (Firebase, 2026-08-06)

1. Registrados no Firebase Android app `com.remdy.app` (`1:384686982032:android:1bc018915f16701dbf2915`):
   - SHA-1 Play App Signing
   - SHA-256 Play App Signing
2. Upload + debug SHAs **preservados** (não removidos).
3. `google-services.json` oficial baixado; OAuth client type 1 agora inclui o SHA-1 Play.
4. Backup local: `android/app/google-services.json.bak_before_play_sha`.

Sem o SHA-1 do App Signing no Firebase, o login Google falha no build da Play (`ApiException:10` / `DEVELOPER_ERROR`) mesmo funcionando em sideload Release (upload key).

Propagação OAuth: alguns minutos. Retestar no build Play Internal após a próxima instalação da loja.
