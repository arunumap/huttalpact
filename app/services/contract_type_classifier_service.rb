class ContractTypeClassifierService
  Result = Struct.new(:suggested_type, :confidence, :scores, keyword_init: true) do
    def confident?
      suggested_type.present? && confidence.to_i >= 70
    end
  end

  TYPE_SIGNALS = {
    "lease" => [
      "lease agreement",
      "landlord",
      "tenant",
      "lessor",
      "lessee",
      "premises",
      "base rent",
      "cam",
      "common area maintenance",
      "rent commencement"
    ],
    "service_agreement" => [
      "master service agreement",
      "msa",
      "statement of work",
      "sow",
      "professional services",
      "deliverables",
      "scope of services",
      "service levels",
      "fees for services"
    ],
    "maintenance" => [
      "maintenance",
      "preventive maintenance",
      "service calls",
      "work order",
      "equipment service",
      "inspection schedule"
    ],
    "insurance" => [
      "insurance policy",
      "coverage",
      "premium",
      "deductible",
      "insured",
      "carrier",
      "policy period"
    ],
    "software" => [
      "software license",
      "subscription term",
      "saas",
      "licensed software",
      "user seats",
      "api",
      "uptime",
      "data processing"
    ]
  }.freeze

  MIN_TOP_SCORE = 3
  MIN_MARGIN_SCORE = 2

  def initialize(contract)
    @contract = contract
  end

  def call
    text = compiled_text
    return Result.new(suggested_type: nil, confidence: 0, scores: {}) if text.blank?

    scores = TYPE_SIGNALS.transform_values { |signals| score_signals(text, signals) }
    suggested_type, top_score = scores.max_by { |_type, score| score }
    second_score = scores.reject { |type, _score| type == suggested_type }.values.max.to_i

    return Result.new(suggested_type: nil, confidence: 0, scores: scores) if top_score.to_i <= 0

    margin = top_score - second_score
    raw_confidence = [ 35 + (top_score * 8) + (margin * 5), 99 ].min
    confident = top_score >= MIN_TOP_SCORE && margin >= MIN_MARGIN_SCORE
    confidence = confident ? [ raw_confidence, 70 ].max : [ raw_confidence, 69 ].min

    Result.new(suggested_type: suggested_type, confidence: confidence, scores: scores)
  end

  private

  def compiled_text
    @compiled_text ||= @contract.contract_documents.completed.ordered
      .pluck(:extracted_text)
      .compact
      .join("\n")
      .downcase
  end

  def score_signals(text, signals)
    signals.count { |signal| signal_match?(text, signal) }
  end

  def signal_match?(text, signal)
    signal = signal.downcase
    if signal.include?(" ")
      text.include?(signal)
    else
      text.match?(/\b#{Regexp.escape(signal)}\b/)
    end
  end
end
