# KalulaApp — Native iOS

SwiftUI app for Kalula. Works on **iPhone and iPad** (iOS 16+).

## Features

| Feature | Description |
|---|---|
| 📄 Scan vendor quotes | Camera scan → on-device OCR → Claude AI extracts line items → create Kalula quote |
| 🧾 Scan receipts | Camera scan → upload to Azure → stored in your tenant folder for accounting |
| 📁 Document storage | Any document → your Azure tenant folder |
| 💬 Quotes list | Browse, filter, and view all Kalula quotes |

## Opening in Xcode

```bash
cd /Users/chrisntuli/GitHub/KalulaApp
open KalulaApp.xcodeproj
```

Select your team under **Signing & Capabilities**, choose a simulator or connected device, and press **⌘R**.

## Regenerating the project

If you add new Swift files, run:
```bash
xcodegen generate
```

## Backend environment variables required

Add these to `/Users/chrisntuli/GitHub/kalula/backend/.env`:

```env
# Azure Storage — get these from Azure Portal → Storage Account → Access keys
AZURE_STORAGE_ACCOUNT_NAME=your_account_name
AZURE_STORAGE_ACCOUNT_KEY=your_account_key
AZURE_STORAGE_CONTAINER=kalula-documents

# Anthropic — for vendor quote OCR parsing
ANTHROPIC_API_KEY=sk-ant-...
```

## Azure folder structure (per tenant)

```
kalula-documents/
└── {tenantId}/
    ├── vendor_quote/
    │   └── 2026-05-26_uuid.jpg
    ├── receipt/
    │   └── 2026-05-26_uuid.jpg
    └── general/
        └── 2026-05-26_uuid.jpg
```

## Database migration

```bash
cd /Users/chrisntuli/GitHub/kalula/packages/db
npx prisma migrate deploy
```

## New backend endpoints

| Method | Path | Description |
|---|---|---|
| `POST` | `/v1/documents/upload-url` | Get a short-lived SAS URL for direct Azure upload |
| `POST` | `/v1/documents/confirm` | Save document metadata after the Azure PUT completes |
| `POST` | `/v1/documents/parse-quote` | Parse OCR text into quote line items (Claude AI) |
| `GET` | `/v1/documents?type=RECEIPT` | List tenant documents (filter by type) |
| `DELETE` | `/v1/documents/:id` | Delete document + Azure blob |

## Scan flow (Vendor Quote)

```
Camera → VisionKit scan → on-device OCR (Vision framework)
  → POST /documents/parse-quote   (Claude extracts line items)
  → User reviews / edits line items
  → POST /quotes                  (creates Kalula quote)
  → POST /documents/upload-url    (get 30-min SAS token)
  → PUT  {sasUrl}                 (iOS → Azure directly, token-scoped)
  → POST /documents/confirm       (save metadata)
```

## Scan flow (Receipt / General)

```
Camera → VisionKit scan
  → POST /documents/upload-url    (get 30-min SAS token)
  → PUT  {sasUrl}                 (iOS → Azure directly, token-scoped)
  → POST /documents/confirm       (save metadata)
```
