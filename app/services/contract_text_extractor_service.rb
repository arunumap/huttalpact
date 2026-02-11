require "nokogiri"
require "zip"

class ContractTextExtractorService
  class UnsupportedFormatError < StandardError; end
  class ExtractionError < StandardError; end

  # Limit extracted text to prevent excessively large DB records and downstream token overflows
  MAX_EXTRACTED_TEXT_LENGTH = 500_000

  def initialize(contract_document)
    @document = contract_document
  end

  def call
    raise ExtractionError, "No file attached to document #{@document.id}" unless @document.file.attached?

    detected_type = @document.content_type
    raise UnsupportedFormatError, "Unsupported file type: #{detected_type.inspect}" if detected_type.blank?

    @document.update_columns(extraction_status: "processing")

    text = case detected_type
    when "application/pdf"
      extract_pdf
    when /wordprocessingml|docx/
      extract_docx
    when /text/
      extract_text
    else
      raise UnsupportedFormatError, "Unsupported file type: #{detected_type}"
    end

    # Guard against nil/empty extraction
    if text.blank?
      @document.update!(extracted_text: "", extraction_status: "completed", page_count: @page_count)
      Rails.logger.warn("Contract text extraction produced empty result for document #{@document.id}")
      return ""
    end

    # Truncate excessively large text to prevent downstream issues
    text = text.truncate(MAX_EXTRACTED_TEXT_LENGTH, omission: "\n\n[Text truncated at #{MAX_EXTRACTED_TEXT_LENGTH} characters]") if text.length > MAX_EXTRACTED_TEXT_LENGTH

    @document.update_columns(
      extracted_text: text,
      extraction_status: "completed",
      page_count: @page_count,
      updated_at: Time.current
    )

    text
  rescue UnsupportedFormatError, ExtractionError => e
    @document.update_columns(extraction_status: "failed", updated_at: Time.current) if @document.persisted?
    raise e
  rescue => e
    @document.update_columns(extraction_status: "failed", updated_at: Time.current) if @document.persisted?
    Rails.logger.error("Contract text extraction failed for document #{@document.id}: #{e.message}")
    raise e
  end

  private

  def extract_pdf
    data = @document.file.download
    raise ExtractionError, "PDF file is empty" if data.blank?

    reader = PDF::Reader.new(StringIO.new(data))
    @page_count = reader.page_count
    reader.pages.map { |page| page.text rescue "" }.join("\n\n")
  rescue PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError => e
    raise ExtractionError, "Could not read PDF: #{e.message}"
  end

  def extract_docx
    data = @document.file.download
    raise ExtractionError, "DOCX file is empty" if data.blank?

    tempfile = Tempfile.new([ "contract", ".docx" ])
    tempfile.binmode
    tempfile.write(data)
    tempfile.rewind

    @page_count = nil # DOCX doesn't have reliable page count

    parts = []

    # Extract headers from raw ZIP (not supported by the docx gem)
    parts.concat(extract_docx_headers_footers(tempfile.path, "header"))

    # Extract paragraphs and tables via the docx gem
    doc = Docx::Document.open(tempfile.path)

    # Interleave paragraphs and tables in document order by walking the body XML
    doc_body = doc.instance_variable_get(:@doc)&.at_xpath("//w:body", "w" => OOXML_NS)

    if doc_body
      doc_body.children.each do |node|
        case node.name
        when "p" # paragraph
          text = extract_paragraph_text(node)
          parts << text if text.present?
        when "tbl" # table
          table_text = extract_table_text(node)
          parts << table_text if table_text.present?
        end
      end
    else
      # Fallback: extract paragraphs then tables separately
      doc.paragraphs.each { |p| parts << p.text if p.text.present? }
      doc.tables.each_with_index { |table, idx| parts << format_table(table, idx) }
    end

    # Extract footers from raw ZIP
    parts.concat(extract_docx_headers_footers(tempfile.path, "footer"))

    parts.join("\n\n")
  rescue Zip::Error => e
    raise ExtractionError, "Could not read DOCX (invalid zip): #{e.message}"
  ensure
    tempfile&.close
    tempfile&.unlink
  end

  OOXML_NS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"

  def extract_paragraph_text(node)
    node.xpath(".//w:t", "w" => OOXML_NS).map(&:text).join
  end

  def extract_table_text(tbl_node)
    rows = tbl_node.xpath(".//w:tr", "w" => OOXML_NS)
    return nil if rows.empty?

    lines = [ "[Table]" ]
    rows.each do |row|
      cells = row.xpath(".//w:tc", "w" => OOXML_NS)
      cell_texts = cells.map { |c| c.xpath(".//w:t", "w" => OOXML_NS).map(&:text).join.strip }
      lines << cell_texts.join(" | ")
    end
    lines.join("\n")
  end

  def format_table(table, _index)
    lines = [ "[Table]" ]
    table.rows.each do |row|
      cells = row.cells.map { |c| c.text.strip }
      lines << cells.join(" | ")
    end
    lines.join("\n")
  end

  def extract_docx_headers_footers(path, type)
    parts = []
    label = type.capitalize

    Zip::File.open(path) do |zip|
      zip.glob("word/#{type}*.xml").sort_by(&:name).each do |entry|
        xml = Nokogiri::XML(entry.get_input_stream.read)
        text = xml.xpath("//w:p//w:t", "w" => OOXML_NS).map(&:text).join(" ").strip
        parts << "[#{label}] #{text}" if text.present?
      end
    end

    parts
  rescue Zip::Error
    # If we can't read ZIP for headers/footers, skip gracefully — the main
    # docx gem extraction will catch the real error.
    []
  end

  def extract_text
    @page_count = nil
    data = @document.file.download
    data.force_encoding("UTF-8")
    data.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
  end
end
