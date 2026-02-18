# SageBadger — Feature Gap Analysis

> Generated: 2026-02-17

## Build Plan Status

Weeks 1–9 (Auth, Contracts, Upload, AI Extraction, Dashboard, Alerts, Polish, Billing, Pre-launch) are **fully implemented**. Week 10 (production launch/deployment) is not yet done.

---

## High Priority — Incomplete Workflows

### 1. No Team Management UI
`Membership` and `Invitation` models exist with owner/admin/member roles, but after onboarding there is **no way to invite members, change roles, or remove users**. The only invite path is the onboarding wizard step 3.

- **Files**: `app/models/membership.rb`, `app/models/invitation.rb`
- **Missing**: A controller + views for `/settings/team` or similar

### 2. ~~No User Profile / Account Settings~~ ✅ DONE
Users can now update their name, email, and password from `/settings/profile`. Password changes verify the current password and invalidate all other sessions.

- **Files**: `app/controllers/settings/profile_controller.rb`, `app/views/settings/profile/show.html.erb`

### 3. ~~No Organization Settings~~ ✅ DONE
Admin+ users can now update organization name and slug from `/settings/organization`. Changes are audit-logged.

- **Files**: `app/controllers/settings/organization_controller.rb`, `app/views/settings/organization/show.html.erb`

### 4. Admin Role Defined but Unused
The `admin` role exists on memberships but has no permission differentiation from `member`. All members have full CRUD on everything except billing (owner-only).

- **Files**: `app/models/membership.rb`

### 5. Branding Inconsistency — "HuttalPact" References
Remnants of a prior product name appear in:
- `app/mailers/application_mailer.rb` — `from:` address
- `app/mailers/invitation_mailer.rb` — subject line
- `app/helpers/seo_helper.rb` — `DEFAULT_SITE_NAME`
- `app/controllers/registrations_controller.rb` — welcome message
- `public/robots.txt` — sitemap comment

---

## Medium Priority — Logic & Data Issues

### 6. Alert Channel Bug
`AlertGeneratorService` creates one `AlertRecipient` per user per alert. If a user has both `email_enabled` and `in_app_enabled`, they **only get email** — the in-app channel is silently skipped.

- **File**: `app/services/alert_generator_service.rb` (~L110-L112)

### 7. Draft Status Badge Missing
`contract_status_badge` in `ApplicationHelper` has no entry for `"draft"`, so drafts render with the same color as active contracts.

- **File**: `app/helpers/application_helper.rb`

### 8. No Expired Session Cleanup Job
`Session` has an `expired` scope but sessions are never cleaned up in bulk. They accumulate indefinitely in the DB.

- **File**: `app/models/session.rb`
- **Missing**: A recurring job in `config/recurring.yml`

### 9. ContractStatusUpdaterJob Doesn't Regenerate Alerts
When contracts transition to `expiring_soon`, no alert regeneration occurs. Alerts may have stale trigger dates.

- **File**: `app/jobs/contract_status_updater_job.rb`

### 10. Counter Cache Mismatch
`Organization.contracts_count` counts all contracts (including drafts/archived), but plan enforcement uses `contracts.not_archived.count`. The counter cache isn't used for limit enforcement.

- **Files**: `app/models/organization.rb`, `app/models/concerns/plan_limits.rb`

### 11. No Upper-Bound Validation on `renewal_date`
Renewal date only validated > `start_date`, not > `end_date`. A renewal before the contract ends is semantically wrong.

- **File**: `app/models/contract.rb` (date validations)

### 12. Single-Timezone Assumption
All date logic uses server time (`Date.current` / `Time.current`) with no per-org timezone support. Recurring jobs run at server-local time.

- **Files**: `config/recurring.yml`, `app/services/alert_generator_service.rb`

### 13. Invitation Acceptance for Existing Users
If a logged-in user clicks an invite link, `redirect_if_authenticated` sends them away without joining the org. Invitation acceptance only works during registration.

- **File**: `app/controllers/registrations_controller.rb`

---

## Lower Priority — Missing SaaS Features

### 14. No Email Verification
User emails are never verified after registration.

### 15. No 2FA/MFA
Authentication is single-factor password only.

### 16. No Document Download
Users can't re-download uploaded contract files from the contract detail page.

### 17. No CSV/Data Import
No spreadsheet import for migrating existing contracts into the system.

### 18. No Weekly/Monthly Digest Emails
Common SaaS engagement pattern — summary of upcoming renewals/expirations.

### 19. No Custom Tagging/Labels
Contracts can only be categorized by `contract_type` (6 fixed options). No user-defined tags.

### 20. No Global Search
Search only covers the contracts index. No search across alerts, audit logs, vendors, or key clauses.

### 21. No Terms of Service / Privacy Policy Pages
Footer links exist but there are no corresponding routes or views.

### 22. No Dedicated Reporting Page
Dashboard has summary stats but no reporting with date range filtering, trend charts, or downloadable reports.

### 23. No Contract Sharing / External Access
No way to share contract details with someone outside the organization.

### 24. No API
No REST or GraphQL API for external integrations.

### 25. No Contract Templates
No ability to create or use standard contract templates.

---

## Performance Concerns

### 26. Alert Count Queries on Every Request
`set_unread_alert_count` in `ApplicationController` runs 2 DB queries on every authenticated request. Should be cached or lazy-loaded.

- **File**: `app/controllers/application_controller.rb` (~L49-L65)

### 27. Dashboard Has ~15 Uncached Queries
No eager loading or fragment caching on the dashboard.

- **File**: `app/controllers/dashboard_controller.rb`

### 28. No GIN/Trigram Index on `contracts.vendor_name`
ILIKE search on `vendor_name` will degrade at scale. Consider a `pg_trgm` GIN index.

- **File**: `db/schema.rb`

---

## Test Gaps

### 29. No System Tests
`test/system/` directory doesn't exist. No browser-level integration tests.

### 30. No ApplicationHelper Tests
~200 lines of badge/formatting methods with no test coverage.

### 31. No Stimulus/JS Tests
13 Stimulus controllers with no JavaScript tests.

### 32. No PasswordsMailer Preview
`test/mailers/previews/` has previews for alert and invitation mailers but not for passwords.

---

## Deployment (Week 10 — Not Started)

- Production deployment via Kamal (configured but not deployed)
- S3 configuration for Active Storage in production
- Postmark API token in production credentials
- Error tracking (Sentry gem installed but not configured)
- Analytics (Plausible or similar — no gem or config)
