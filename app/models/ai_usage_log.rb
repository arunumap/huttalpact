class AiUsageLog < ApplicationRecord
  # Legacy fallback cost constants — used for rows without an ai_extraction_config
  MODEL_INPUT_COST_PER_MILLION = 3.0
  MODEL_OUTPUT_COST_PER_MILLION = 15.0

  belongs_to :organization
  belongs_to :contract, optional: true
  belongs_to :ai_extraction_config, optional: true
  has_many :contract_reviews, dependent: :nullify
  has_one :extraction_feedback, primary_key: :contract_id, foreign_key: :contract_id

  validates :ai_model, presence: true
  validates :input_tokens, :output_tokens, :total_tokens, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :duration_ms, numericality: { greater_than_or_equal_to: 0, only_integer: true }, allow_nil: true
  validates :extraction_mode, inclusion: { in: %w[full incremental] }

  scope :successful, -> { where(success: true) }
  scope :failed, -> { where(success: false) }
  scope :by_org, ->(organization_id) { where(organization_id:) }
  scope :by_model, ->(ai_model) { where(ai_model:) }
  scope :since, ->(time) { where(created_at: time..) }
  scope :in_period, ->(start_time, end_time) { where(created_at: start_time..end_time) }

  before_validation :compute_total_tokens

  def self.daily_totals(days: 30)
    since(days.days.ago)
      .group("DATE(created_at)")
      .select(
        "DATE(created_at) AS usage_date",
        "COUNT(*) AS extraction_count",
        "SUM(input_tokens) AS input_tokens_sum",
        "SUM(output_tokens) AS output_tokens_sum",
        "SUM(total_tokens) AS total_tokens_sum"
      )
      .order("usage_date DESC")
  end

  def self.total_cost(scope = all)
    scope.includes(:ai_extraction_config).sum(&:estimated_cost)
  end

  # Per-row cost using linked config's rates, falling back to hardcoded constants
  def estimated_cost
    input_rate = ai_extraction_config&.input_cost_per_million || MODEL_INPUT_COST_PER_MILLION
    output_rate = ai_extraction_config&.output_cost_per_million || MODEL_OUTPUT_COST_PER_MILLION

    ((input_tokens / 1_000_000.0) * input_rate) +
      ((output_tokens / 1_000_000.0) * output_rate)
  end

  private

  def compute_total_tokens
    self.input_tokens ||= 0
    self.output_tokens ||= 0
    self.total_tokens = input_tokens + output_tokens
  end
end
