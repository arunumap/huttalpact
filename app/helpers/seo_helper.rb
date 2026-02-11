# frozen_string_literal: true

module SeoHelper
  DEFAULT_SITE_NAME = "HuttalPact"
  DEFAULT_DESCRIPTION = "AI-powered contract tracking for SMBs. Upload contracts, auto-extract key dates and clauses, and never miss a renewal deadline again."
  DEFAULT_OG_IMAGE = "og-image.png"

  # Renders all SEO meta tags in the <head>. Call from layouts.
  #
  #   <%= seo_meta_tags %>
  #
  # Views set per-page values via content_for:
  #   <% content_for :title, "My Page Title" %>
  #   <% content_for :meta_description, "Custom description" %>
  #   <% content_for :meta_robots, "noindex, nofollow" %>
  #   <% content_for :canonical_url, "https://huttalpact.com/pricing" %>
  def seo_meta_tags
    safe_join([
      tag.meta(name: "description", content: seo_description),
      tag.meta(name: "robots", content: seo_robots),
      canonical_tag,
      og_tags,
      twitter_tags
    ].compact)
  end

  # Renders JSON-LD structured data for the page.
  #
  #   <%= structured_data(type: :organization) %>
  #   <%= structured_data(type: :software_application) %>
  #   <%= structured_data(type: :faq, items: [...]) %>
  def structured_data(type:, **options)
    data = case type
    when :organization
      organization_schema
    when :software_application
      software_application_schema
    when :faq
      faq_schema(options[:items] || [])
    when :breadcrumb
      breadcrumb_schema(options[:items] || [])
    end

    return unless data

    tag.script(data.to_json.html_safe, type: "application/ld+json")
  end

  private

  def seo_title
    content_for(:title).presence || DEFAULT_SITE_NAME
  end

  def seo_description
    content_for(:meta_description).presence || DEFAULT_DESCRIPTION
  end

  def seo_robots
    content_for(:meta_robots).presence || "index, follow"
  end

  def canonical_tag
    url = content_for(:canonical_url).presence || request.original_url.split("?").first
    tag.link(rel: "canonical", href: url)
  end

  def og_tags
    safe_join([
      tag.meta(property: "og:site_name", content: DEFAULT_SITE_NAME),
      tag.meta(property: "og:title", content: seo_title),
      tag.meta(property: "og:description", content: seo_description),
      tag.meta(property: "og:type", content: content_for(:og_type).presence || "website"),
      tag.meta(property: "og:url", content: content_for(:canonical_url).presence || request.original_url.split("?").first),
      tag.meta(property: "og:image", content: og_image_url)
    ])
  end

  def twitter_tags
    safe_join([
      tag.meta(name: "twitter:card", content: "summary_large_image"),
      tag.meta(name: "twitter:title", content: seo_title),
      tag.meta(name: "twitter:description", content: seo_description),
      tag.meta(name: "twitter:image", content: og_image_url)
    ])
  end

  def og_image_url
    if content_for?(:og_image)
      content_for(:og_image)
    else
      image_url(DEFAULT_OG_IMAGE)
    end
  rescue StandardError
    ""
  end

  # --- Structured Data Schemas ---

  def organization_schema
    {
      "@context" => "https://schema.org",
      "@type" => "Organization",
      "name" => DEFAULT_SITE_NAME,
      "url" => root_url,
      "logo" => image_url("sagebadger-logo.svg"),
      "description" => DEFAULT_DESCRIPTION,
      "sameAs" => []
    }
  rescue StandardError
    nil
  end

  def software_application_schema
    {
      "@context" => "https://schema.org",
      "@type" => "SoftwareApplication",
      "name" => DEFAULT_SITE_NAME,
      "applicationCategory" => "BusinessApplication",
      "operatingSystem" => "Web",
      "description" => DEFAULT_DESCRIPTION,
      "offers" => [
        {
          "@type" => "Offer",
          "name" => "Free",
          "price" => "0",
          "priceCurrency" => "USD",
          "description" => "10 contracts, 5 AI extractions/mo, 1 user"
        },
        {
          "@type" => "Offer",
          "name" => "Starter",
          "price" => "49",
          "priceCurrency" => "USD",
          "priceSpecification" => { "@type" => "UnitPriceSpecification", "billingDuration" => "P1M" },
          "description" => "100 contracts, 50 AI extractions/mo, 5 users"
        },
        {
          "@type" => "Offer",
          "name" => "Pro",
          "price" => "149",
          "priceCurrency" => "USD",
          "priceSpecification" => { "@type" => "UnitPriceSpecification", "billingDuration" => "P1M" },
          "description" => "Unlimited contracts, extractions, and users"
        }
      ]
    }
  end

  def faq_schema(items)
    return nil if items.empty?

    {
      "@context" => "https://schema.org",
      "@type" => "FAQPage",
      "mainEntity" => items.map do |item|
        {
          "@type" => "Question",
          "name" => item[:question],
          "acceptedAnswer" => {
            "@type" => "Answer",
            "text" => item[:answer]
          }
        }
      end
    }
  end

  def breadcrumb_schema(items)
    return nil if items.empty?

    {
      "@context" => "https://schema.org",
      "@type" => "BreadcrumbList",
      "itemListElement" => items.each_with_index.map do |item, index|
        {
          "@type" => "ListItem",
          "position" => index + 1,
          "name" => item[:name],
          "item" => item[:url]
        }
      end
    }
  end
end
