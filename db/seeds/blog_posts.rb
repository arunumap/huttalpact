# frozen_string_literal: true

# Seed blog categories and initial blog posts.
#
# Usage:
#   bin/rails runner db/seeds/blog_posts.rb
#
# Posts are created as drafts — review and publish via the admin UI.

admin = AdminUser.first!
puts "Using admin: #{admin.email_address}"

# ── Categories ──────────────────────────────────────────────
categories = {
  "Contract Management" => { slug: "contract-management", description: "Tips and best practices for tracking contracts, renewals, and deadlines.", position: 0 },
  "Property Management" => { slug: "property-management", description: "Guides for property managers handling leases, vendor contracts, and compliance.", position: 1 },
  "Product Updates"     => { slug: "product-updates", description: "New features, improvements, and tips for getting the most from PactBadger.", position: 2 }
}

categories.each do |name, attrs|
  BlogCategory.find_or_create_by!(slug: attrs[:slug]) do |cat|
    cat.name = name
    cat.description = attrs[:description]
    cat.position = attrs[:position]
  end
  puts "  ✓ Category: #{name}"
end

contract_mgmt = BlogCategory.find_by!(slug: "contract-management")
property_mgmt = BlogCategory.find_by!(slug: "property-management")
product_updates = BlogCategory.find_by!(slug: "product-updates")

# ── Post 1: Pain-Point (Top of Funnel) ─────────────────────
post1_body = <<~MARKDOWN
  If you manage commercial properties, you already know the drill: lease end dates scattered across filing cabinets, renewal deadlines buried in spreadsheet tabs, and the constant anxiety that something important is slipping through the cracks.

  You're not alone. Most property management companies with 5–50 properties still track lease expirations in Excel. It works — until it doesn't.

  ## The Spreadsheet Problem

  Spreadsheets are flexible, familiar, and free. But they have real limitations when it comes to tracking lease expirations:

  **No automatic alerts.** You have to remember to check the spreadsheet. If you're busy with tenant issues, maintenance requests, or new acquisitions, those renewal deadlines don't announce themselves.

  **Data goes stale.** Leases get amended. Options get exercised. Someone updates one sheet but not another. By the time you check, the dates may be wrong.

  **No single source of truth.** The property manager has one version. The accountant has another. The asset manager has a third. Which one is current?

  **Key clauses are invisible.** A spreadsheet might capture the end date, but what about the 90-day notice requirement? The auto-renewal clause? The rent escalation trigger? These details live in the lease document itself — not in row 47 of your tracker.

  ## What Actually Goes Wrong

  Here are real scenarios we've heard from property managers:

  ### The Missed Notice Period
  A 5-year commercial lease had a 120-day notice-to-vacate requirement. The property manager caught it at 60 days. The tenant was already planning to leave, but the late notice triggered penalty clauses worth $18,000.

  ### The Silent Auto-Renewal
  A vendor contract for landscaping services auto-renewed for another 2 years because no one flagged the 30-day opt-out window. The company was locked into above-market rates they wanted to renegotiate.

  ### The Forgotten Rent Escalation
  A lease included a 3% annual rent escalation tied to the anniversary date. The property manager didn't bill the increase for 14 months. Recovering the difference from a tenant who "didn't know" was a months-long headache.

  ## What You Actually Need

  You don't need a six-figure enterprise contract management system. You need something that does four things well:

  1. **Stores lease documents in one place** — PDF, Word, or scanned files, accessible to your team.
  2. **Extracts the key dates automatically** — start dates, end dates, renewal deadlines, notice periods.
  3. **Sends alerts before deadlines** — not the day of, not the day after, but with enough lead time to act.
  4. **Surfaces hidden clauses** — auto-renewals, escalations, termination rights, and penalties.

  ## A Better Approach

  Modern tools can read your lease documents and extract the important information for you. Upload a PDF lease, and AI identifies the parties, the term, the renewal structure, the notice requirements, and the key clauses — in seconds, not hours.

  Then, instead of manually checking a spreadsheet every Monday, you get an email 90 days before a renewal deadline. Or 60 days. Or whatever lead time your lease requires.

  The information stays current because it's pulled directly from the document. And your entire team sees the same data.

  ## Getting Started

  If you're ready to move beyond spreadsheets, here's a simple transition plan:

  1. **Start with your most critical leases.** Don't try to migrate everything at once. Pick the 10 leases with the nearest expiration dates.
  2. **Upload the actual documents.** Not a summary — the real lease PDF. AI extraction works best with the full document.
  3. **Verify the extracted data.** AI is accurate but not perfect. Spend 2 minutes confirming the key dates and terms.
  4. **Set your alert preferences.** Decide how much lead time you need for each type of deadline.
  5. **Expand gradually.** Once you trust the system, upload the rest of your portfolio.

  The goal isn't to replace your judgment — it's to make sure nothing falls through the cracks while you're focused on running properties.

  ---

  *PactBadger is built specifically for property managers who've outgrown spreadsheets. Upload your leases, and AI extracts dates, values, and key clauses automatically. [Try it free](/) — no credit card required.*
MARKDOWN

if BlogPost.find_by(slug: "track-lease-expirations-without-spreadsheet").nil?
  BlogPost.create!(
    admin_user: admin,
    blog_category: property_mgmt,
    title: "How to Track Commercial Lease Expirations Without a Spreadsheet",
    slug: "track-lease-expirations-without-spreadsheet",
    body: post1_body,
    excerpt: "Spreadsheets break down as your property portfolio grows. Here's what actually goes wrong — and a better approach to tracking lease expirations, renewals, and notice periods.",
    meta_description: "Stop tracking lease expirations in Excel. Learn why spreadsheets fail and how AI tools extract key dates and send automatic alerts.",
    status: "draft"
  )
  puts "  ✓ Post: How to Track Commercial Lease Expirations Without a Spreadsheet"
end

# ── Post 2: How-To / Product (Middle of Funnel) ────────────

post2_body = <<~MARKDOWN
  You just uploaded a 40-page commercial lease to PactBadger. Within a minute, the system has identified the landlord, the tenant, the lease term, every critical date, the monthly rent, the security deposit, and a half-dozen key clauses — including the auto-renewal provision buried on page 31.

  How does that work? And more importantly, can you trust it?

  ## The Three-Step Pipeline

  When you upload a document to PactBadger, three things happen in sequence:

  ### Step 1: Text Extraction
  First, we extract the raw text from your document. PactBadger accepts PDF, DOCX, and TXT files. For PDFs, we extract embedded text (and for scanned documents, we use OCR to convert the image to text). The goal is clean, readable text that preserves the structure of the original document.

  ### Step 2: AI Analysis
  The extracted text is sent to an AI model that has been specifically instructed to identify contract and lease information. The AI reads the full document and extracts structured data:

  - **Parties** — landlord/lessor and tenant/lessee names
  - **Dates** — lease start, end, renewal, and notice deadlines
  - **Financial terms** — rent amount, security deposit, escalation schedules
  - **Key clauses** — auto-renewal, early termination, penalties, assignment rights, insurance requirements, and more

  The AI doesn't guess. It identifies specific passages in the document and extracts values from them. Each extraction includes the source context — the actual text from the lease that the value was pulled from.

  ### Step 3: Alert Generation
  Once the key dates are extracted, PactBadger automatically creates alerts. If your lease ends on December 31, 2027, and has a 90-day notice requirement, you'll get an alert on October 2, 2027 — with enough time to make a decision and act on it.

  Alerts are sent via email and shown in your PactBadger dashboard. You choose how far in advance you want to be notified.

  ## What Gets Extracted

  Here's a breakdown of what PactBadger pulls from a typical commercial lease:

  | Field | Example |
  |-------|---------|
  | Contract type | Commercial Lease |
  | Parties | ABC Properties LLC ↔ Tenant Corp |
  | Start date | January 1, 2024 |
  | End date | December 31, 2028 |
  | Monthly rent | $4,500/month |
  | Security deposit | $9,000 |
  | Renewal date | October 2, 2028 (90 days before end) |
  | Notice period | 90 days |
  | Auto-renewal | Yes — 2-year extension if no notice given |
  | Rent escalation | 3% annually on anniversary |
  | Early termination | Permitted after Year 3 with 6 months' notice + 2 months' penalty |

  Beyond the structured fields, the AI also identifies **key clauses** — specific provisions that have financial or legal significance. These include:

  - Auto-renewal and extension terms
  - Termination rights and penalties
  - Rent escalation and adjustment formulas
  - Insurance and indemnification requirements
  - Assignment and subletting restrictions
  - Maintenance and repair obligations
  - CAM (Common Area Maintenance) provisions

  Each clause is extracted with a summary and the source text from the document, so you can verify it against the original.

  ## How Accurate Is It?

  AI extraction is very good, but it's not infallible. Here's what to expect:

  **Dates and financial terms** — High accuracy. These are concrete values that appear explicitly in the text. AI finds them reliably.

  **Parties and roles** — High accuracy for standard lease formats. Complex multi-party agreements or unusual naming conventions occasionally need a manual check.

  **Key clauses** — Good accuracy for standard commercial lease clauses. The AI identifies the right provisions in the vast majority of cases. Unusual or heavily negotiated clauses may need review.

  **Our recommendation:** Always do a quick scan of the extracted data before relying on it for decisions. PactBadger makes this easy — the extraction results page shows every field with its source context, and you can edit any value with a single click.

  We also give you the option to rate each extraction and provide feedback, which helps us continuously improve accuracy.

  ## What About Amendments and Addenda?

  Many leases have amendments that modify the original terms. PactBadger handles this by allowing you to upload multiple documents per contract. When you upload an amendment, the AI re-analyzes the full document set and updates the extracted data accordingly.

  For example, if you upload a lease followed by a rent amendment, the system will update the financial terms to reflect the amendment while preserving the original lease dates.

  ## Try It Yourself

  The best way to understand the extraction is to see it work on your own documents:

  1. **Sign up for free** — no credit card required
  2. **Upload a lease** — drag and drop a PDF, DOCX, or TXT file
  3. **Watch the extraction** — results appear within a minute
  4. **Review and refine** — check the extracted data and make any corrections

  The free plan includes 10 contracts and 5 AI extractions per month — enough to test with your most important leases.

  ---

  *Ready to see what AI can find in your leases? [Upload your first contract](/) and see results in under a minute.*
MARKDOWN

if BlogPost.find_by(slug: "how-pactbadger-extracts-key-dates-from-leases").nil?
  BlogPost.create!(
    admin_user: admin,
    blog_category: product_updates,
    title: "How PactBadger Extracts Key Dates from Your Lease in Seconds",
    slug: "how-pactbadger-extracts-key-dates-from-leases",
    body: post2_body,
    excerpt: "Upload a PDF lease and get structured data back in under a minute. Here's how PactBadger's AI extraction pipeline works — and what to expect from the results.",
    meta_description: "See how PactBadger's AI reads lease documents and extracts dates, terms, and clauses automatically. Free to try, no credit card required.",
    status: "draft"
  )
  puts "  ✓ Post: How PactBadger Extracts Key Dates from Your Lease in Seconds"
end

# ── Post 3: Comparison / Alternatives (Bottom of Funnel) ───

post3_body = <<~MARKDOWN
  If you manage commercial or residential properties, you already know that tracking lease dates in your head doesn't scale. But the contract management software market is confusing — tools range from free spreadsheet templates to $50,000/year enterprise platforms.

  This guide focuses on tools that actually make sense for property management companies with 5–50 properties. We evaluated each option on price, ease of use, lease-specific features, and whether you'll actually use it after the first week.

  ## What Property Managers Actually Need

  Before comparing tools, let's define what matters:

  1. **Lease document storage** — Upload and access the actual PDF/Word lease from anywhere
  2. **Key date tracking** — Start dates, end dates, renewal deadlines, notice periods
  3. **Automated alerts** — Email or in-app reminders before critical deadlines
  4. **Clause visibility** — Auto-renewal terms, escalation schedules, termination rights
  5. **Team access** — Multiple users can view and manage contracts
  6. **Affordability** — Priced for a 10–50 property portfolio, not a Fortune 500 company

  ## The Options

  ### 1. Spreadsheets (Google Sheets / Excel)

  **Price:** Free
  **Best for:** Solo operators with < 10 leases

  The default choice. Create columns for tenant name, lease start, lease end, rent, and renewal date. Set a Google Calendar reminder for each deadline.

  **Pros:**
  - Free and familiar
  - Completely flexible — add any column you want
  - Easy to share with a team

  **Cons:**
  - No automatic alerts — you have to manually create reminders
  - Data goes stale when leases are amended
  - Key clauses (auto-renewal, termination rights) don't fit neatly in a cell
  - No connection to the actual lease document
  - Gets unwieldy past 20–30 entries

  **Verdict:** Fine for getting started. Breaks down as your portfolio grows.

  ### 2. Property Management Software (AppFolio, Buildium, Yardi)

  **Price:** $1–3 per unit/month (minimum $250–400/month for most plans)
  **Best for:** Companies that need full property management (accounting, maintenance, tenant portals)

  These platforms handle the entire property management workflow: accounting, maintenance requests, tenant screening, and rent collection. Lease tracking is a feature, not the focus.

  **Pros:**
  - All-in-one property management
  - Lease dates are tracked as part of the tenant record
  - Good if you're already using the platform

  **Cons:**
  - Expensive if you only need contract tracking
  - Lease tracking features are basic — typically just dates, not clauses
  - Vendor contracts and non-lease agreements are usually an afterthought
  - No AI extraction — you manually enter everything
  - Complex setup and onboarding

  **Verdict:** If you already use AppFolio or Buildium, check if their lease tracking meets your needs. If you're buying one just for contract tracking, it's overkill.

  ### 3. Enterprise Contract Management (Ironclad, DocuSign CLM, Concord)

  **Price:** $20,000–50,000+/year
  **Best for:** Large legal teams, 1,000+ contracts, complex workflows

  These are powerful platforms built for legal and procurement teams at large companies. They handle contract authoring, negotiation workflows, e-signatures, obligation tracking, and compliance.

  **Pros:**
  - Extremely feature-rich
  - Custom workflows and approval chains
  - AI-powered analysis (at the enterprise tier)

  **Cons:**
  - Way too expensive for a 10–50 property company
  - Months-long implementation
  - Feature complexity you'll never use
  - Often require a dedicated admin

  **Verdict:** Not the right fit for SMB property managers. You'd be paying for features designed for a legal department with 50 people.

  ### 4. Simple Contract Trackers (Contractbook, ContractSafe, Agiloft)

  **Price:** $300–600/month for a small team
  **Best for:** Mid-size companies with diverse contract portfolios

  These tools sit between spreadsheets and enterprise CLMs. They provide document storage, date tracking, and basic alerting. Some offer limited AI features at higher tiers.

  **Pros:**
  - Purpose-built for contract tracking
  - Better than spreadsheets for organization and alerts
  - Document storage included

  **Cons:**
  - Not built for property management specifically
  - AI extraction (if available) often requires higher-tier plans
  - $300+/month is steep for a small property management company
  - Generic categories — no lease-specific fields (rent, CAM, escalation)

  **Verdict:** Solid tools, but priced and designed for mid-market companies, not small property management firms.

  ### 5. PactBadger

  **Price:** Free for 10 contracts, $49/month (Starter), $149/month (Pro)
  **Best for:** Property management companies with 5–50 properties

  Full disclosure — we built PactBadger, so we're biased. But here's why we built it specifically for this use case:

  **Pros:**
  - **AI-powered extraction** — Upload a PDF lease and get dates, terms, and clauses extracted automatically. No manual data entry.
  - **Built for leases** — Fields for rent, security deposit, escalation, CAM, and other lease-specific terms.
  - **Automated alerts** — Email and in-app notifications before renewal deadlines, notice periods, and expirations.
  - **Key clause detection** — Auto-renewal, termination, penalty, escalation, and other critical clauses identified and highlighted.
  - **Affordable** — Free tier for getting started, $49/month for up to 100 contracts and a 5-person team.
  - **Fast setup** — Upload a lease and see extracted data in under a minute. No implementation project.

  **Cons:**
  - No e-signature or contract authoring (we focus on tracking existing contracts)
  - No accounting or maintenance features (we're not a property management platform)
  - Newer product — fewer integrations than established tools

  **Verdict:** Purpose-built for the specific problem of tracking lease deadlines and key clauses without the cost or complexity of enterprise tools.

  ## Comparison Summary

  | Feature | Spreadsheet | PM Software | Enterprise CLM | Mid-Market Tracker | PactBadger |
  |---------|:-----------:|:-----------:|:--------------:|:------------------:|:----------:|
  | Price (monthly) | Free | $250+ | $1,500+ | $300+ | Free–$149 |
  | AI extraction | ✗ | ✗ | ✓ (enterprise tier) | Limited | ✓ |
  | Lease-specific fields | Manual | Basic | ✗ | ✗ | ✓ |
  | Automated alerts | ✗ | Basic | ✓ | ✓ | ✓ |
  | Key clause detection | ✗ | ✗ | ✓ | ✗ | ✓ |
  | Setup time | Minutes | Weeks | Months | Days | Minutes |
  | Team access | ✓ | ✓ | ✓ | ✓ | ✓ |

  ## Our Recommendation

  - **< 10 leases, solo operator:** Start with a spreadsheet. Upgrade when it starts to feel fragile.
  - **10–50 properties, small team:** [Try PactBadger](/) — it's purpose-built for this scenario, and the free tier lets you test with no commitment.
  - **50+ properties, complex workflows:** Evaluate mid-market trackers or property management platforms with strong lease tracking modules.
  - **1,000+ contracts, legal team:** Enterprise CLM is probably the right investment.

  The right tool depends on your portfolio size, team size, and whether lease tracking is your primary need or one feature among many.

  ---

  *PactBadger offers a free plan with 10 contracts and 5 AI extractions per month. [Sign up and upload your first lease](/) — no credit card required.*
MARKDOWN

if BlogPost.find_by(slug: "best-contract-tracking-software-property-managers").nil?
  BlogPost.create!(
    admin_user: admin,
    blog_category: contract_mgmt,
    title: "Best Contract Tracking Software for Property Managers (2026)",
    slug: "best-contract-tracking-software-property-managers",
    body: post3_body,
    excerpt: "Comparing spreadsheets, property management platforms, enterprise CLMs, and purpose-built contract trackers. Which one actually makes sense for a 5–50 property portfolio?",
    meta_description: "Compare the best contract tracking tools for property managers in 2026. From spreadsheets to AI-powered platforms for your portfolio.",
    status: "draft"
  )
  puts "  ✓ Post: Best Contract Tracking Software for Property Managers (2026)"
end

puts
puts "Done! 3 categories and 3 draft blog posts created."
puts "Review and publish them at: /admin/blog_posts"
