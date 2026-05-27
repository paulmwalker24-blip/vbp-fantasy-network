# Private Commissioner Data

This folder is for local-only payment reconciliation inputs. Real names, emails, and exports belong here, not in tracked public data.

Ignored local files:

- `manager-identities.json`
- `payment-status-overrides.json`
- `payments/exports/<LEAGUE-ID>-current.csv`
- `leaguesafe-payments.csv`
- `leaguesafe-bbu-current.csv`
- `leaguesafe-bracket-current.csv`
- `leaguesafe-bracket-payments.csv`
- `leaguesafe-gauntlet-current.csv`
- `leaguesafe-gauntlet-payments.csv`

Do not commit real names, emails, or payment exports.

## Standard Single-League Payments

Use `payments/exports/` for a LeagueSafe export that belongs to one league record, such as `DYN8`, `RD4`, `KP1`, or `CH1`. Importing the raw download under its internal league ID prevents payment files from becoming scattered. Use `-PaymentPeriod 2027` or similar when a league has a separate future-season collection; reconciliation automatically combines all imported periods for that league:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\import-leaguesafe-export.ps1 -LeagueRecordId DYN8 -SourcePath "C:\Users\pkwal\Downloads\VBP Dynasty League #8 (Slow Draft) payment details (1).csv"
powershell -ExecutionPolicy Bypass -File .\scripts\import-leaguesafe-export.ps1 -LeagueRecordId DYN1 -PaymentPeriod 2027 -SourcePath "C:\Users\pkwal\Downloads\DYN1 2027 payment details.csv"
powershell -ExecutionPolicy Bypass -File .\scripts\reconcile-league-payments.ps1 -LeagueRecordId DYN8
powershell -ExecutionPolicy Bypass -File .\scripts\build-payment-index.ps1
```

Outputs are written under ignored `reports/private/payments/`:

- `README.md` and `league-payment-index.csv` list every league and its stored payment source.
- `<LEAGUE-ID>/tracker.csv` compares Sleeper roster assignments to LeagueSafe rows.
- `<LEAGUE-ID>/unmatched-leaguesafe-rows.csv` lists payer rows whose Sleeper identity still needs confirmation.

Save confirmed payer-to-Sleeper aliases in `manager-identities.json` and rerun reconciliation.

Save league-specific departures, requested refunds, or other commissioner follow-ups in `payment-status-overrides.json`. These notes appear in the generated payment page while the original LeagueSafe export remains unchanged.

For a visible Explorer-facing folder, generate the commissioner view:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build-commissioner-payment-center.ps1
```

This creates the local-only top-level `PAYMENT-CENTER/` folder with:

- `START-HERE.md`
- `ALL-LEAGUES-PAYMENT-INDEX.md`
- `MASTER-CONFIRMED-MANAGERS.md`
- `MASTER-MANAGER-DIRECTORY.md`, which includes confirmed identities plus paid names still needing a Sleeper match
- `CSV-EXPORTS/BBU-UNMATCHED-SLEEPER-MANAGERS.csv`, which keeps unmatched BBU Sleeper identities easy to compare against paid names
- `LEAGUES/<LEAGUE-ID> - <LEAGUE-NAME>.md` for each readable league page
- `CSV-EXPORTS/` for spreadsheet versions

## Shared-Pool Payments

Continue using the specialized workflow when one LeagueSafe contest covers multiple public rooms:

- Best Ball Union uses `leaguesafe-bbu-current.csv` and `reconcile-bbu-payments.ps1`.
- Redraft Bracket uses `leaguesafe-bracket-current.csv` and `reconcile-redraft-bracket-payments.ps1`.
- Existing Best Ball Gauntlet input remains supported; a new refresh may also be imported through the standard single-league flow as `BG1`.

## Legacy Normalized CSV Headers

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
