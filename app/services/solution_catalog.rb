# frozen_string_literal: true

class SolutionCatalog
  Solution = Struct.new(
    :contract_type,
    :slug,
    :name,
    :meta_title,
    :meta_description,
    :index_blurb,
    :highlights,
    :hero_eyebrow,
    :hero_title,
    :hero_description,
    :hero_badge_title,
    :hero_badge_text,
    :pain_title,
    :pain_subtitle,
    :pain_points,
    :feature_title,
    :feature_subtitle,
    :features,
    :steps_title,
    :steps_subtitle,
    :steps,
    :comparison_subtitle,
    :comparison_rows,
    :cta_title,
    :cta_description,
    keyword_init: true
  )

  PUBLIC_CONTRACT_TYPES = (Contract::CONTRACT_TYPES - [ "other" ]).freeze

  CONFIG = {
    "lease" => {
      slug: "leases",
      name: "Leases",
      meta_title: "Lease Management Software — AI Extraction & Deadline Alerts | PactBadger",
      meta_description: "Turn lease files into structured data with AI extraction. Track rent schedules, option windows, CAM terms, and proactive lease alerts in PactBadger.",
      index_blurb: "Extract rent schedules, CAM terms, options, and notice windows from lease documents in one review flow.",
      highlights: [ "Rent schedules", "CAM terms", "Option windows" ],
      hero_eyebrow: "Lease solution",
      hero_title: "Track lease extractions and deadlines in one system",
      hero_description: "Upload lease files and PactBadger extracts rent schedules, option windows, CAM terms, and critical dates. Then it monitors deadlines and alerts your team before anything slips.",
      hero_badge_title: "40+ fields extracted",
      hero_badge_text: "From a single lease upload",
      pain_title: "What makes lease tracking hard",
      pain_subtitle: "Lease data lives across long documents, amendments, and notice windows that are easy to miss without a system.",
      pain_points: [
        { title: "Data buried in PDFs", description: "Key dates and obligations are locked inside lengthy lease documents and exhibits." },
        { title: "Scattered amendments", description: "Options, rent changes, and negotiated exceptions are often split across multiple files." },
        { title: "Missed notice windows", description: "One missed renewal or termination notice can lock you into the wrong terms." },
        { title: "Manual follow-up", description: "Teams rely on spreadsheets and calendars instead of a centralized lease workflow." }
      ],
      feature_title: "Everything your lease team needs",
      feature_subtitle: "From document upload to deadline action, PactBadger handles the full lease workflow.",
      features: [
        { title: "AI lease extraction", description: "Extract rent amounts, term dates, option windows, parties, and key clauses from lease files." },
        { title: "Rent schedule visibility", description: "Track current rent, upcoming escalations, and other financial milestones in one place." },
        { title: "CAM and operating terms", description: "Capture audit rights, caps, reconciliation timing, and related operating expense provisions." },
        { title: "Option and notice tracking", description: "Monitor renewal, expansion, termination, and purchase options before deadlines close." },
        { title: "Lease milestones", description: "Track one-time and recurring lease obligations with advance reminders." },
        { title: "Proactive alerts", description: "Get notified ahead of renewals, expirations, and notice periods so the team can act early." }
      ],
      steps_title: "From lease document to deadline control",
      steps_subtitle: "Three steps to turn lease files into a proactive management system.",
      steps: [
        { title: "Upload your lease documents", description: "Drag in lease files, amendments, exhibits, and related attachments in the formats your team already uses." },
        { title: "Review AI-extracted lease data", description: "PactBadger pulls structured lease fields and supporting evidence so your team can confirm the right details quickly." },
        { title: "Stay ahead of lease obligations", description: "Monitor expirations, option windows, rent changes, and milestone deadlines from one dashboard." }
      ],
      comparison_subtitle: "See how a dedicated lease system compares to manual methods.",
      comparison_rows: [
        [ "AI document extraction", false, false, true ],
        [ "Structured lease data", false, false, true ],
        [ "Option and notice tracking", "Manual", "Basic", true ],
        [ "Renewal and milestone alerts", false, "Basic", true ],
        [ "Clause identification", "Manual", false, true ],
        [ "Document storage and audit trail", false, false, true ]
      ],
      cta_title: "Get control of your lease deadlines",
      cta_description: "Start free and see how quickly your team can move from static files to proactive lease management."
    },
    "service_agreement" => {
      slug: "service-agreements",
      name: "Service Agreements",
      meta_title: "Service Agreement Management Software — AI Extraction & Alerts | PactBadger",
      meta_description: "Use AI to extract renewal terms, SLAs, notice periods, fees, and obligations from service agreements. Track deadlines and review contract terms in PactBadger.",
      index_blurb: "Track service levels, renewal terms, notice periods, and fee changes across customer and vendor service agreements.",
      highlights: [ "SLA terms", "Renewal clauses", "Notice periods" ],
      hero_eyebrow: "Service agreement solution",
      hero_title: "See every service agreement obligation before it becomes urgent",
      hero_description: "Upload service agreements and PactBadger extracts fees, service levels, renewal terms, notice periods, and key clauses. Keep teams ahead of renewals, obligations, and vendor/customer commitments.",
      hero_badge_title: "SLA and renewal visibility",
      hero_badge_text: "From one review workflow",
      pain_title: "Why service agreements are hard to track",
      pain_subtitle: "Commercial terms, service levels, and renewal clauses are often split across contracts, exhibits, and amendments.",
      pain_points: [
        { title: "Buried SLA terms", description: "Response-time commitments and service credits are easy to miss in dense legal language." },
        { title: "Auto-renewal risk", description: "Notice windows close before teams have time to renegotiate or switch providers." },
        { title: "Fee changes spread across files", description: "Pricing updates and amendments make it hard to know the current commercial terms." },
        { title: "No shared system of record", description: "Operations, procurement, and legal teams each track different details in different places." }
      ],
      feature_title: "Everything you need for service agreement oversight",
      feature_subtitle: "Keep service levels, renewals, fees, and obligations visible across every agreement.",
      features: [
        { title: "AI service agreement extraction", description: "Extract parties, effective dates, fees, renewal clauses, and other critical service terms." },
        { title: "SLA clause tracking", description: "Track uptime, response-time, escalation, and service credit language in one system." },
        { title: "Renewal and notice management", description: "Monitor auto-renewals, termination rights, and notice periods before they become urgent." },
        { title: "Amendment-aware review", description: "Keep master agreements, order forms, and amendments together in a single contract record." },
        { title: "Obligation visibility", description: "Surface operational commitments and internal follow-up items tied to each agreement." },
        { title: "Shared alerts", description: "Send reminders to the right team before renewals, reviews, and compliance deadlines." }
      ],
      steps_title: "From service agreement upload to action",
      steps_subtitle: "Three steps to move from static files to a proactive service agreement workflow.",
      steps: [
        { title: "Upload agreements and attachments", description: "Add master agreements, exhibits, statements of work, and amendments to one record." },
        { title: "Review extracted commercial and service terms", description: "Confirm the important dates, clauses, and obligations with evidence-backed AI output." },
        { title: "Act before renewals and service issues", description: "Stay ahead of renewals, notice periods, performance commitments, and contract reviews." }
      ],
      comparison_subtitle: "See how PactBadger compares to spreadsheets and calendar reminders for service agreements.",
      comparison_rows: [
        [ "AI service term extraction", false, false, true ],
        [ "SLA and clause visibility", "Manual", false, true ],
        [ "Renewal and notice alerts", false, "Basic", true ],
        [ "Amendment-aware contract records", false, false, true ],
        [ "Team-wide obligation tracking", "Limited", false, true ],
        [ "Audit trail and document storage", false, false, true ]
      ],
      cta_title: "Stay ahead of every service agreement review",
      cta_description: "Start free and give your team one place to track service terms, obligations, and renewal risk."
    },
    "maintenance" => {
      slug: "maintenance-agreements",
      name: "Maintenance Agreements",
      meta_title: "Maintenance Agreement Tracking — AI Extraction & Alerts | PactBadger",
      meta_description: "Extract service cadence, renewal terms, warranty language, pricing, and notice periods from maintenance agreements with PactBadger.",
      index_blurb: "Track service frequency, pricing terms, warranty clauses, and renewal dates across maintenance agreements.",
      highlights: [ "Service cadence", "Warranty terms", "Renewal dates" ],
      hero_eyebrow: "Maintenance agreement solution",
      hero_title: "Track maintenance contracts before service gaps and renewals surprise you",
      hero_description: "Upload maintenance agreements and PactBadger extracts service cadence, pricing, warranty language, renewal dates, and notice periods so teams can stay ahead of operational risk.",
      hero_badge_title: "Service cadence and terms",
      hero_badge_text: "Captured in one system",
      pain_title: "What makes maintenance agreements messy",
      pain_subtitle: "Service obligations and renewal terms are easy to overlook when agreements are tracked manually.",
      pain_points: [
        { title: "Service requirements hidden in text", description: "Inspection cadence, response commitments, and exclusions are buried in contract language." },
        { title: "Renewals sneak up", description: "Teams miss notice windows because maintenance contracts are tracked in separate spreadsheets." },
        { title: "Pricing changes over time", description: "Escalations, equipment schedules, and amendments create uncertainty around current costs." },
        { title: "Warranty and coverage ambiguity", description: "It is hard to know what is covered, when, and under which agreement version." }
      ],
      feature_title: "Everything you need to manage maintenance agreements",
      feature_subtitle: "See service terms, renewals, and obligations without digging through files.",
      features: [
        { title: "AI maintenance agreement extraction", description: "Capture service dates, parties, pricing, renewal clauses, and other critical fields automatically." },
        { title: "Service cadence tracking", description: "Track recurring service intervals, inspection schedules, and preventive maintenance commitments." },
        { title: "Warranty and exclusion review", description: "Keep warranty terms, exclusions, and responsibilities visible to the right team." },
        { title: "Renewal and notice alerts", description: "Get advance reminders before renewal windows or service agreement expirations." },
        { title: "Attachment-aware records", description: "Keep exhibits, equipment lists, and amendments tied to the same agreement record." },
        { title: "Shared visibility", description: "Give operations, procurement, and finance one source of truth for maintenance obligations." }
      ],
      steps_title: "From maintenance contract upload to operational clarity",
      steps_subtitle: "Three steps to centralize service terms and stay ahead of deadlines.",
      steps: [
        { title: "Upload the maintenance agreement", description: "Add the base contract plus schedules, pricing exhibits, and any later amendments." },
        { title: "Review extracted service and commercial terms", description: "Confirm service cadence, coverage, renewal language, and key obligations in one workflow." },
        { title: "Act before renewals and service lapses", description: "Use alerts and dashboards to stay ahead of renewal dates, service commitments, and follow-up work." }
      ],
      comparison_subtitle: "See how PactBadger compares to manual tracking for maintenance agreements.",
      comparison_rows: [
        [ "AI service term extraction", false, false, true ],
        [ "Warranty and exclusion visibility", "Manual", false, true ],
        [ "Renewal and notice alerts", false, "Basic", true ],
        [ "Recurring service tracking", "Manual", false, true ],
        [ "Centralized contract history", false, false, true ],
        [ "Shared audit trail", false, false, true ]
      ],
      cta_title: "Make maintenance agreements easier to manage",
      cta_description: "Start free and keep service terms, renewals, and obligations organized in one contract system."
    },
    "insurance" => {
      slug: "insurance-contracts",
      name: "Insurance Contracts",
      meta_title: "Insurance Contract Tracking — AI Extraction & Renewal Alerts | PactBadger",
      meta_description: "Extract policy periods, renewal dates, notice requirements, coverage terms, and obligations from insurance contracts with PactBadger.",
      index_blurb: "Monitor policy periods, renewal dates, notice requirements, and key coverage terms across insurance contracts.",
      highlights: [ "Policy periods", "Coverage terms", "Renewal notices" ],
      hero_eyebrow: "Insurance contract solution",
      hero_title: "Keep insurance renewals, notices, and coverage terms visible",
      hero_description: "Upload insurance contracts and PactBadger extracts policy dates, renewal terms, notice requirements, and key coverage clauses so your team can act before deadlines pass.",
      hero_badge_title: "Renewal and notice visibility",
      hero_badge_text: "Across every policy record",
      pain_title: "Why insurance contracts are easy to miss",
      pain_subtitle: "Policy renewals, notice periods, and coverage changes often live across endorsements and attachments.",
      pain_points: [
        { title: "Renewal dates are fragmented", description: "Policy periods and notice windows may be spread across binders, endorsements, and certificates." },
        { title: "Coverage details are hard to compare", description: "Limits, exclusions, and obligations take manual effort to piece together from multiple documents." },
        { title: "Late notice risk", description: "Missing notice or renewal deadlines can create operational and compliance risk." },
        { title: "No central contract view", description: "Teams chase down policy files instead of using one searchable system of record." }
      ],
      feature_title: "Everything you need for insurance contract visibility",
      feature_subtitle: "Track renewals, policy periods, and key insurance obligations from one place.",
      features: [
        { title: "AI insurance contract extraction", description: "Extract policy dates, carrier details, renewal terms, and key coverage clauses automatically." },
        { title: "Notice period tracking", description: "Surface cancellation, non-renewal, and other notice deadlines before they become urgent." },
        { title: "Coverage term visibility", description: "Keep limits, obligations, exclusions, and endorsements easy to review." },
        { title: "Attachment-aware records", description: "Store endorsements, certificates, and supporting documents alongside the base contract." },
        { title: "Renewal alerts", description: "Send reminders before renewal reviews and policy expirations." },
        { title: "Shared audit trail", description: "Give legal, risk, and operations one history of changes and contract activity." }
      ],
      steps_title: "From policy files to renewal control",
      steps_subtitle: "Three steps to centralize insurance contract deadlines and key terms.",
      steps: [
        { title: "Upload policy and endorsement files", description: "Bring the full insurance contract set into one place, including supporting attachments." },
        { title: "Review extracted dates and coverage terms", description: "Confirm policy periods, notice language, and obligations with evidence-backed AI output." },
        { title: "Monitor renewals and obligations", description: "Use alerts and dashboards to stay ahead of renewals, notices, and internal follow-up." }
      ],
      comparison_subtitle: "See how PactBadger compares to spreadsheets and calendars for insurance contract management.",
      comparison_rows: [
        [ "AI policy term extraction", false, false, true ],
        [ "Notice and renewal alerts", false, "Basic", true ],
        [ "Coverage term visibility", "Manual", false, true ],
        [ "Attachment-aware policy records", false, false, true ],
        [ "Team-wide access", "Limited", false, true ],
        [ "Audit trail and storage", false, false, true ]
      ],
      cta_title: "Stay ahead of insurance contract deadlines",
      cta_description: "Start free and keep policy periods, notices, and coverage terms organized in one system."
    },
    "software" => {
      slug: "software-agreements",
      name: "Software Agreements",
      meta_title: "Software Agreement Tracking — AI Extraction & Renewal Alerts | PactBadger",
      meta_description: "Track software renewals, pricing schedules, security obligations, notice periods, and key clauses by extracting software agreements with AI.",
      index_blurb: "Track subscriptions, pricing schedules, security terms, renewal clauses, and notice periods across software agreements.",
      highlights: [ "Subscription terms", "Pricing schedules", "Security clauses" ],
      hero_eyebrow: "Software agreement solution",
      hero_title: "Track software agreements before renewals and obligations catch you off guard",
      hero_description: "Upload software agreements and PactBadger extracts pricing terms, renewal clauses, notice periods, security obligations, and other critical details. Keep legal, procurement, and IT aligned on what matters next.",
      hero_badge_title: "Subscription and renewal visibility",
      hero_badge_text: "Across every software agreement",
      pain_title: "What makes software agreements difficult to manage",
      pain_subtitle: "Pricing, security, and renewal terms often live across order forms, MSAs, and data processing addenda.",
      pain_points: [
        { title: "Renewals happen before reviews", description: "Teams realize too late that subscriptions are auto-renewing under outdated terms." },
        { title: "Commercial terms are split across documents", description: "Pricing schedules, order forms, and amendments make current terms hard to verify." },
        { title: "Security obligations are buried", description: "Data handling, breach notice, and compliance commitments are easy to miss in long agreements." },
        { title: "Cross-functional ownership is unclear", description: "Legal, procurement, IT, and finance often each track only part of the agreement." }
      ],
      feature_title: "Everything you need for software agreement visibility",
      feature_subtitle: "Track pricing, renewals, security obligations, and related documents in one contract workflow.",
      features: [
        { title: "AI software agreement extraction", description: "Extract parties, pricing terms, renewal clauses, notice periods, and key software contract fields." },
        { title: "Order form and addendum review", description: "Keep MSAs, order forms, DPAs, security exhibits, and amendments connected to the same agreement." },
        { title: "Renewal and notice management", description: "Track auto-renewals, termination rights, and review windows before they close." },
        { title: "Security and compliance clause visibility", description: "Surface breach notice, data handling, audit, and compliance language in one system." },
        { title: "Pricing change awareness", description: "Monitor subscription fees, uplifts, and commercial changes across agreement versions." },
        { title: "Shared alerts and workflow", description: "Keep legal, procurement, IT, and finance aligned on upcoming obligations." }
      ],
      steps_title: "From software agreement upload to renewal readiness",
      steps_subtitle: "Three steps to centralize software contract terms and deadlines.",
      steps: [
        { title: "Upload the software agreement set", description: "Add the base agreement, order forms, addenda, and later amendments to one contract record." },
        { title: "Review extracted commercial and legal terms", description: "Confirm pricing, renewals, security obligations, and other high-value terms with AI assistance." },
        { title: "Act before renewals and reviews", description: "Use alerts and dashboards to stay ahead of auto-renewals, notice deadlines, and internal contract reviews." }
      ],
      comparison_subtitle: "See how PactBadger compares to manual software agreement tracking.",
      comparison_rows: [
        [ "AI agreement extraction", false, false, true ],
        [ "Renewal and notice alerts", false, "Basic", true ],
        [ "Pricing and uplift visibility", "Manual", false, true ],
        [ "Security clause review", "Manual", false, true ],
        [ "Multi-document agreement records", false, false, true ],
        [ "Shared audit trail", false, false, true ]
      ],
      cta_title: "Get ahead of software renewals and obligations",
      cta_description: "Start free and keep software agreement terms, pricing, and renewal deadlines in one searchable system."
    }
  }.freeze

  FEATURE_ICONS = [
    '<path stroke-linecap="round" stroke-linejoin="round" d="M9.813 15.904L9 18.75l-.813-2.846a4.5 4.5 0 00-3.09-3.09L2.25 12l2.846-.813a4.5 4.5 0 003.09-3.09L9 5.25l.813 2.846a4.5 4.5 0 003.09 3.09L15.75 12l-2.846.813a4.5 4.5 0 00-3.09 3.09zM18.259 8.715L18 9.75l-.259-1.035a3.375 3.375 0 00-2.455-2.456L14.25 6l1.036-.259a3.375 3.375 0 002.455-2.456L18 2.25l.259 1.035a3.375 3.375 0 002.455 2.456L21.75 6l-1.036.259a3.375 3.375 0 00-2.455 2.456z" />',
    '<path stroke-linecap="round" stroke-linejoin="round" d="M14.857 17.082a23.848 23.848 0 005.454-1.31A8.967 8.967 0 0118 9.75v-.7V9A6 6 0 006 9v.75a8.967 8.967 0 01-2.312 6.022c1.733.64 3.56 1.085 5.455 1.31m5.714 0a24.255 24.255 0 01-5.714 0m5.714 0a3 3 0 11-5.714 0" />',
    '<path stroke-linecap="round" stroke-linejoin="round" d="M19.5 14.25v-2.625a3.375 3.375 0 00-3.375-3.375h-1.5A1.125 1.125 0 0113.5 7.125v-1.5a3.375 3.375 0 00-3.375-3.375H8.25m0 12.75h7.5m-7.5 3H12M10.5 2.25H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 00-9-9z" />',
    '<path stroke-linecap="round" stroke-linejoin="round" d="M3.75 3v11.25A2.25 2.25 0 006 16.5h2.25M3.75 3h-1.5m1.5 0h16.5m0 0h1.5m-1.5 0v11.25A2.25 2.25 0 0118 16.5h-2.25m-7.5 0h7.5m-7.5 0l-1 3m8.5-3l1 3m0 0l.5 1.5m-.5-1.5h-9.5m0 0l-.5 1.5M9 11.25v1.5M12 9v3.75m3-6v6" />',
    '<path stroke-linecap="round" stroke-linejoin="round" d="M9 12h3.75M9 15h3.75M9 18h3.75m3 .75H18a2.25 2.25 0 002.25-2.25V6.108c0-1.135-.845-2.098-1.976-2.192a48.424 48.424 0 00-1.123-.08m-5.801 0c-.065.21-.1.433-.1.664 0 .414.336.75.75.75h4.5a.75.75 0 00.75-.75 2.25 2.25 0 00-.1-.664m-5.8 0A2.251 2.251 0 0113.5 2.25H15c1.012 0 1.867.668 2.15 1.586m-5.8 0c-.376.023-.75.05-1.124.08C9.095 4.01 8.25 4.973 8.25 6.108V8.25m0 0H4.875c-.621 0-1.125.504-1.125 1.125v11.25c0 .621.504 1.125 1.125 1.125h9.75c.621 0 1.125-.504 1.125-1.125V9.375c0-.621-.504-1.125-1.125-1.125H8.25zM6.75 12h.008v.008H6.75V12zm0 3h.008v.008H6.75V15zm0 3h.008v.008H6.75V18z" />',
    '<path stroke-linecap="round" stroke-linejoin="round" d="M3 3v1.5M3 21v-6m0 0l2.77-.693a9 9 0 016.208.682l.108.054a9 9 0 006.086.71l3.114-.732a48.524 48.524 0 01-.005-10.499l-3.11.732a9 9 0 01-6.085-.711l-.108-.054a9 9 0 00-6.208-.682L3 4.5M3 15V4.5" />'
  ].freeze

  def self.public_solutions
    PUBLIC_CONTRACT_TYPES.map { |contract_type| build(contract_type) }
  end

  def self.find_by_slug(slug)
    public_solutions.find { |solution| solution.slug == slug.to_s }
  end

  def self.feature_icon(index)
    FEATURE_ICONS[index % FEATURE_ICONS.length]
  end

  def self.build(contract_type)
    Solution.new(contract_type:, **CONFIG.fetch(contract_type))
  end
end
