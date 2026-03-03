class BlogCategory < ApplicationRecord
  has_many :blog_posts, dependent: :nullify

  normalizes :name, with: ->(value) { value.strip.squeeze(" ") }

  validates :name, presence: true, length: { maximum: 100 }, uniqueness: { case_sensitive: false }
  validates :slug, presence: true, uniqueness: true,
            format: { with: /\A[a-z0-9\-]+\z/, message: "only allows lowercase letters, numbers, and hyphens" }
  validates :description, length: { maximum: 2_000 }, allow_blank: true
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  before_validation :generate_slug

  scope :ordered, -> { order(:position, :name) }

  private

  MAX_SLUG_RETRIES = 5

  def generate_slug
    return if name.blank?
    return if slug.present?

    base_slug = name.to_s.parameterize.truncate(80, omission: "")
    base_slug = "category" if base_slug.blank?
    self.slug = base_slug
    counter = 1
    while BlogCategory.where.not(id: id).exists?(slug: slug)
      self.slug = "#{base_slug}-#{counter}"
      counter += 1
    end
  rescue ActiveRecord::RecordNotUnique
    counter ||= 1
    counter += 1
    retry if counter <= MAX_SLUG_RETRIES
    raise
  end
end
