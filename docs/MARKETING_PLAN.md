# PactBadger — Go-to-Market Plan

> Created: 2026-03-03  
> Product: AI-powered contract tracking for SMBs  
> First target vertical: Property management companies (5–50 properties)  
> Pricing: Free ($0) → Starter ($49/mo) → Pro ($149/mo)

---

## What You Already Have (Marketing Infrastructure)

Your app has a strong foundation — don't underestimate what's already built:

- **Landing page** — Hero, features, how-it-works, testimonials, pricing teaser, FAQ
- **Pricing page** — 3-tier with monthly/annual toggle, Stripe integration
- **Blog CMS** — Admin-managed posts with categories, featured images, RSS/Atom feed
- **SEO infrastructure** — Meta tags, Open Graph, Twitter cards, JSON-LD structured data, sitemap
- **Legal pages** — Terms of Service, Privacy Policy
- **Free tier** — No-credit-card signup funnel (10 contracts, 5 AI extractions/mo)

---

## Phase 1: Pre-Launch Essentials (Do These First)

### 1. ~~Deploy to Production~~ ✅ DONE
App is live on Heroku.

### 2. ~~Add Analytics~~ ✅ DONE
Google Analytics 4 (G-KQLR3PQZ4W) is installed across all user-facing layouts (marketing, app, auth, onboarding, pricing). Only loads in production.

### 3. Set Up Google Search Console
- Verify domain ownership at [search.google.com/search-console](https://search.google.com/search-console)
- Submit your sitemap (`/sitemap.xml`)
- This is how Google discovers your pages — do it day one

### 4. Create Basic Social Accounts
Even if you don't plan to post frequently, claim your handles:
- [ ] **LinkedIn company page** (your buyers are business professionals)
- [ ] **X/Twitter** (@pactbadger)
- [ ] **Google Business Profile** (helps with branded search)

---

## Phase 2: Content Marketing (Weeks 1–4)

Content is your #1 lever. Property managers Google their problems. You need to be the answer.

### Blog Content Strategy

Your blog CMS is built and ready. Publish **2 posts per week** in these categories:

#### Category 1: Pain-Point Content (Top of Funnel)
These attract people who don't know your product exists yet. Target long-tail keywords.

| Post Title | Target Keyword | Intent |
|---|---|---|
| "How to Track Commercial Lease Expirations Without a Spreadsheet" | lease expiration tracking | Problem-aware |
| "5 Contract Renewal Mistakes Property Managers Make" | contract renewal mistakes | Problem-aware |
| "What Happens When You Miss a Lease Renewal Notice Period" | missed lease renewal | Pain-aware |
| "Auto-Renewal Clauses: What Property Managers Need to Know" | auto-renewal clause lease | Educational |
| "How to Organize Vendor Contracts for a Property Portfolio" | organize vendor contracts | Problem-aware |
| "CAM Reconciliation Deadlines: Never Miss Another One" | CAM reconciliation deadline | Niche pain |
| "Lease Audit Checklist for Property Managers" | lease audit checklist | Educational |
| "How AI Is Changing Contract Management for Small Businesses" | AI contract management | Trend-aware |

#### Category 2: Product / How-To Content (Middle of Funnel)
For people evaluating solutions.

| Post Title | Purpose |
|---|---|
| "How PactBadger Extracts Key Dates from Your Lease in Seconds" | Demonstrate AI value |
| "Setting Up Contract Alerts: A Step-by-Step Guide" | Show ease of use |
| "From Spreadsheet to PactBadger: A Migration Guide" | Reduce switching friction |
| "How We Built Our AI Extraction Pipeline" | Build trust, show expertise |

#### Category 3: Comparison / Alternative Content (Bottom of Funnel)
For people actively shopping. These convert well.

| Post Title | Target Keyword |
|---|---|
| "Best Contract Tracking Software for Property Managers (2026)" | contract tracking software property management |
| "PactBadger vs. Spreadsheets: Why It's Time to Upgrade" | contract tracking spreadsheet alternative |
| "Contract Management Tools Under $50/Month for Small Teams" | cheap contract management software |

### SEO Quick Wins
- Run your sitemap generation (`rake sitemap:refresh`) after deploying
- Ensure every blog post has a unique `meta_description` (you validate max 160 chars — good)
- Add internal links between blog posts and your pricing/signup pages
- Use descriptive alt text on all images (you're already doing this on the homepage)

---

## Phase 3: Direct Outreach (Weeks 2–6)

### Target: Property Management Companies (5–50 Properties)

This is your stated beachhead. These companies:
- Manage dozens of leases manually (often in Excel or filing cabinets)
- Have a dedicated operations person who handles renewals
- Feel acute pain around missed notice periods and surprise auto-renewals
- Are typically NOT using enterprise CLM tools (too expensive, too complex)

### Where to Find Them

1. **LinkedIn Sales Navigator** — Search for titles like "Property Manager," "Operations Manager," "Portfolio Manager" at companies with 5–50 employees in real estate/property management.

2. **Industry directories:**
   - IREM (Institute of Real Estate Management) member directory
   - NAA (National Apartment Association) local chapter lists
   - BOMA (Building Owners and Managers Association) membership
   - Local commercial real estate associations

3. **Google Maps** — Search "property management company [city]" in mid-size metros

### Outreach Script (Email / LinkedIn DM)

Keep it short, specific, and problem-focused:

> **Subject:** Quick question about how you track lease renewals
>
> Hi [Name],
>
> I noticed [Company] manages [X] properties in [City]. Quick question — how are you currently tracking lease renewal deadlines and notice periods across your portfolio?
>
> I built PactBadger specifically for property managers who outgrew spreadsheets but don't need a six-figure enterprise system. You upload your leases (PDF, Word, or text), AI extracts the key dates and clauses, and you get automatic alerts before deadlines.
>
> Free plan, no credit card — takes about 2 minutes to try with one lease.
>
> Would you be open to a 10-minute walkthrough?
>
> [Your name]

### Volume Target
- **50 personalized outreach messages per week** (LinkedIn + email)
- Expect 5–10% reply rate, 2–3% conversion to free trial
- Goal: 10 free trial signups from outreach in month 1

---

## Phase 4: Community & Distribution (Ongoing)

### 1. Property Management Forums & Communities
- **BiggerPockets** — Largest real estate investing community. Post helpful answers (NOT spam), link to relevant blog posts.
- **Reddit** — r/CommercialRealEstate, r/PropertyManagement, r/realestateinvesting
- **/r/SaaS**, **/r/startups** — For founder community and feedback
- **LinkedIn Groups** — Property management and commercial real estate groups

**Rule:** Give value first. Answer questions. Share your blog content when genuinely relevant. Never hard-sell.

### 2. Product Hunt Launch
Good for initial buzz and backlinks. Prep:
- [ ] Create a compelling tagline ("AI-powered contract tracking that won't let you miss a deadline")
- [ ] 4–6 product screenshots/GIF demos
- [ ] A short (60-second) Loom video walkthrough
- [ ] Ask your early users to upvote/review on launch day
- [ ] Post on a Tuesday or Wednesday (best PH days)

### 3. Industry-Specific Directories
List PactBadger on:
- **G2** (free listing)
- **Capterra** (free listing, PPC available later)
- **GetApp**
- **SaaSHub**
- **AlternativeTo**
- **AppSumo Marketplace** (if you want an early-adopter deal — think carefully about LTD economics)

### 4. Partnerships
Once you have 10+ paying customers:
- **Property management associations** — Sponsor a local IREM or BOMA chapter event ($200–500). Offer their members a discount.
- **Property management software integrators** — Companies that sell AppFolio/Buildium/Yardi may refer clients who need contract tracking (not included in those platforms).
- **Commercial real estate attorneys** — They see the pain firsthand and can refer clients.

---

## Phase 5: Paid Acquisition (Month 2+, After Organic Validation)

Don't spend money on ads until you've validated messaging through outreach and content. When ready:

### Google Ads (Search)
Start with high-intent, low-competition keywords:
- "lease expiration tracking software"
- "contract renewal reminder tool"
- "property management contract tracking"
- Budget: $500–1,000/month to start. Target cost-per-trial under $30.

### LinkedIn Ads
Effective for B2B but expensive ($8–15 per click). Use only for:
- Retargeting website visitors (cheapest LinkedIn campaign)
- Sponsored content promoting your best blog posts to property management titles

### Estimated Unit Economics
| Metric | Target |
|---|---|
| Starter ARPU | $49/mo ($588/yr) |
| Trial → Paid conversion | 10–15% |
| Target CAC (blended) | < $100 |
| LTV:CAC ratio | > 5:1 |
| Payback period | < 2 months |

---

## Metrics to Track

Set these up from day one (Plausible + simple internal tracking):

| Metric | How to Track |
|---|---|
| Website visitors | Plausible |
| Signup rate | Plausible goal on `/dashboard` (post-signup redirect) |
| Free → Starter conversion | Internal (Stripe webhook / Pay gem) |
| Blog traffic by post | Plausible |
| Outreach reply rate | Spreadsheet / CRM |
| Time to first AI extraction | Internal query on `ai_extract_contract_jobs` |
| Churn rate | Stripe / Pay gem |

---

## Quick-Win Checklist (First 7 Days)

- [x] Deploy to production (Heroku)
- [x] Add Google Analytics 4
- [ ] Submit sitemap to Google Search Console
- [ ] Claim LinkedIn, Twitter, Google Business Profile
- [ ] Write and publish 3 blog posts (1 pain-point, 1 how-to, 1 comparison)
- [ ] Send 20 personalized LinkedIn messages to property managers
- [ ] List on G2, Capterra, SaaSHub (free)
- [ ] Record a 60-second Loom demo video
- [ ] Share launch on LinkedIn personal profile, r/SaaS, Indie Hackers

---

## What NOT to Do Yet

- **Don't build an affiliate program** — You need volume first.
- **Don't hire a marketing agency** — You need to understand your funnel and messaging yourself before outsourcing.
- **Don't chase enterprise deals** — Stay focused on the 5–50 property segment. Enterprise has a totally different sales cycle.
- **Don't spend on brand ads** — Only performance marketing (search, retargeting) until you have product-market fit signal.
- **Don't over-invest in social media posting** — 2 LinkedIn posts/week is fine. Content + outreach beats a social calendar.

---

## Summary: Priority Order

1. ~~**Deploy**~~ ✅ Already live on Heroku
2. ~~**Analytics**~~ ✅ GA4 installed — **Set up Google Search Console next**
3. **Blog content** — 2 posts/week, SEO-optimized, pain-point focused
4. **Direct outreach** — 50 messages/week to property managers
5. **Community presence** — BiggerPockets, Reddit, LinkedIn groups
6. **Directory listings** — G2, Capterra, SaaSHub (free backlinks + discovery)
7. **Product Hunt launch** — One-time boost, good for backlinks
8. **Paid ads** — After organic messaging is validated (month 2+)
