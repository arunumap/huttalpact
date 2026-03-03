class BlogPost < ApplicationRecord
  belongs_to :admin_user
  belongs_to :blog_category, optional: true

  has_one_attached :featured_image

  normalizes :title, with: ->(value) { value.strip.squeeze(" ") }

  STATUSES = %w[draft published archived].freeze

  validates :title, presence: true, length: { maximum: 255 }
  validates :slug, presence: true, uniqueness: true,
            format: { with: /\A[a-z0-9\-]+\z/, message: "only allows lowercase letters, numbers, and hyphens" }
  validates :body, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :meta_description, length: { maximum: 160 }, allow_blank: true
  validates :canonical_url, length: { maximum: 500 }, allow_blank: true
  validates :og_image_url, length: { maximum: 500 }, allow_blank: true
  validates :published_at, presence: true, if: :published?

  before_validation :generate_slug
  before_validation :set_published_at

  scope :published, -> { where(status: "published").where(published_at: ..Time.current) }
  scope :draft, -> { where(status: "draft") }
  scope :archived, -> { where(status: "archived") }
  scope :recent, -> { order(published_at: :desc, created_at: :desc) }
  scope :in_category, ->(slug) { joins(:blog_category).where(blog_categories: { slug: slug }) }
  scope :for_index, -> { published.includes(:admin_user, :blog_category).recent }

  def published?
    status == "published"
  end

  def rendered_body
    MarkdownRendererService.call(body)
  end

  def reading_time
    words = body.to_s.scan(/\w+/).size
    [ (words / 238.0).ceil, 1 ].max
  end

  def display_excerpt
    return excerpt if excerpt.present?

    body.to_s.gsub(/[#*_`>\[\]()!-]/, " ").squish.truncate(220)
  end

  def published_on
    (published_at || created_at).to_date
  end

  def next_post
    self.class.published.where("published_at > ?", published_at).order(published_at: :asc).first
  end

  def previous_post
    self.class.published.where("published_at < ?", published_at).order(published_at: :desc).first
  end

  private

  MAX_SLUG_RETRIES = 5

  def generate_slug
    return if title.blank?
    return if slug.present?

    base_slug = title.to_s.parameterize.truncate(100, omission: "")
    base_slug = "post" if base_slug.blank?
    self.slug = base_slug
    counter = 1
    while BlogPost.where.not(id: id).exists?(slug: slug)
      self.slug = "#{base_slug}-#{counter}"
      counter += 1
    end
  rescue ActiveRecord::RecordNotUnique
    counter ||= 1
    counter += 1
    retry if counter <= MAX_SLUG_RETRIES
    raise
  end

  def set_published_at
    self.published_at = Time.current if published? && published_at.blank?
  end
end
