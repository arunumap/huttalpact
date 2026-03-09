class ReviewSourceLocatorService
  # Resolves a source_excerpt to a stable locator within document text.
  # Returns { locator: { "document_id":, "start_offset":, "end_offset":, "matched_text": }, strategy: "exact"|"fuzzy"|"anchor"|"none" }

  def initialize(documents)
    @documents = documents
    @normalized_cache = {}
  end

  def resolve(source_excerpt, page_hint: nil, section_hint: nil)
    return { locator: nil, strategy: "none" } if source_excerpt.blank?

    result = exact_match(source_excerpt)
    return { locator: result, strategy: "exact" } if result

    result = fuzzy_match(source_excerpt)
    return { locator: result, strategy: "fuzzy" } if result

    result = anchor_match(source_excerpt, page_hint: page_hint, section_hint: section_hint)
    return { locator: result, strategy: "anchor" } if result

    { locator: nil, strategy: "none" }
  end

  def resolve_all(review_fields)
    review_fields.each do |field|
      next if field.source_excerpt.blank?
      next if field.source_match_strategy.present?

      result = resolve(
        field.source_excerpt,
        page_hint: field.source_locator&.dig("page_hint"),
        section_hint: field.source_locator&.dig("section_hint")
      )

      updated_locator = result[:locator].presence || field.source_locator
      field.update_columns(
        source_locator: updated_locator,
        source_match_strategy: result[:strategy]
      )
    end
  end

  private

  def exact_match(excerpt)
    normalized_excerpt = normalize(excerpt)

    @documents.each do |doc|
      normalized_text = normalized_text_for(doc)
      pos = normalized_text.index(normalized_excerpt)
      next unless pos

      original_start = map_to_original_offset(doc[:text], pos)
      original_end = map_to_original_offset(doc[:text], pos + normalized_excerpt.length)
      matched = doc[:text][original_start...original_end]

      return build_locator(doc[:id], original_start, original_end, matched)
    end
    nil
  end

  def fuzzy_match(excerpt)
    excerpt_tokens = tokenize(excerpt)
    return nil if excerpt_tokens.length < 3

    best_match = nil
    best_score = 0.0
    threshold = 0.7

    @documents.each do |doc|
      doc_token_positions = tokenize_with_positions(doc[:text])
      window_size = excerpt_tokens.length
      max_start = doc_token_positions.length - window_size
      next if max_start.negative?

      (0..max_start).each do |i|
        window_tokens = doc_token_positions[i, window_size].map { |t| t[:token] }
        overlap = (window_tokens & excerpt_tokens).size.to_f / excerpt_tokens.length

        next unless overlap > best_score && overlap >= threshold

        best_score = overlap
        start_offset = doc_token_positions[i][:start]
        end_offset = doc_token_positions[i + window_size - 1][:end]

        best_match = build_locator(doc[:id], start_offset, end_offset, doc[:text][start_offset...end_offset])
      end
    end

    best_match
  end

  def anchor_match(_excerpt, page_hint:, section_hint:)
    return nil if page_hint.blank? && section_hint.blank?

    @documents.each do |doc|
      text = doc[:text]

      next if section_hint.blank?

      section_pos = text.downcase.index(section_hint.downcase)
      next unless section_pos

      region_start = section_pos
      region_end = [ section_pos + 500, text.length ].min

      return build_locator(doc[:id], region_start, region_end, text[region_start...region_end])
    end
    nil
  end

  def normalize(text)
    text.to_s.gsub(/\s+/, " ").strip.downcase
  end

  def normalized_text_for(doc)
    @normalized_cache[doc[:id]] ||= normalize(doc[:text])
  end

  def tokenize(text)
    text.to_s.downcase.scan(/\w+/)
  end

  def tokenize_with_positions(text)
    tokens = []
    text.to_s.scan(/\w+/i) do
      m = Regexp.last_match
      tokens << { token: m[0].downcase, start: m.begin(0), end: m.end(0) }
    end
    tokens
  end

  # Maps a character position in the normalized text back to the original text.
  # Normalization collapses whitespace runs to a single space, strips
  # leading/trailing whitespace, and lowercases.
  def map_to_original_offset(original, norm_offset)
    orig_idx = 0
    norm_idx = 0

    # Skip leading whitespace (normalize strips it)
    orig_idx += 1 while orig_idx < original.length && original[orig_idx].match?(/\s/)

    while norm_idx < norm_offset && orig_idx < original.length
      if original[orig_idx].match?(/\s/)
        # Whitespace run in original → single space in normalized
        norm_idx += 1
        orig_idx += 1
        orig_idx += 1 while orig_idx < original.length && original[orig_idx].match?(/\s/)
      else
        orig_idx += 1
        norm_idx += 1
      end
    end

    orig_idx
  end

  def build_locator(document_id, start_offset, end_offset, matched_text)
    {
      "document_id" => document_id,
      "start_offset" => start_offset,
      "end_offset" => end_offset,
      "matched_text" => matched_text
    }
  end
end
