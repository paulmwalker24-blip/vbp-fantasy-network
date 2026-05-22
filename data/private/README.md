# Private Commissioner Data

This folder is for local-only payment reconciliation inputs.

Ignored local files:

- `manager-identities.json`
- `leaguesafe-payments.csv`
- `leaguesafe-bbu-current.csv`
- `leaguesafe-gauntlet-current.csv`
- `leaguesafe-gauntlet-payments.csv`

Do not commit real names, emails, or payment exports.

## LeagueSafe CSV Headers

`leaguesafe-bbu-current.csv` is the latest raw LeagueSafe export copied from Downloads.

`leaguesafe-payments.csv` is the normalized paid-row input used by the reconciliation scripts.

When a newer LeagueSafe export is downloaded, replace both with:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\import-bbu-leaguesafe-export.ps1 -SourcePath "C:\Users\pkwal\Downloads\VBP's Best Ball Union 2026 payment details (2).csv"
```

Use these headers for `leaguesafe-payments.csv`:

```csv
paymentId,leagueGroup,leagueRecordId,payerName,payerEmail,amount,date,status,notes,personId
```

`leagueRecordId` can be a specific room such as `BBU4`, or blank when the payment belongs to the shared Best Ball Union pool but has not been assigned yet.

For Best Ball Gauntlet, use:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\import-gauntlet-leaguesafe-export.ps1 -SourcePath "C:\Users\pkwal\Downloads\VBP Bestball Gauntlet #1 payment details.csv"
```

## Identity Ledger Shape

Use this starter shape for `manager-identities.json`:

```json
{
  "people": []
}
```

Each person can later hold multiple Sleeper accounts, LeagueSafe payer names, and notes.
