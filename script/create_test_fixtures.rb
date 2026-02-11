#!/usr/bin/env ruby
# Creates test fixture files for DOCX and PDF extraction tests

require "zip"

# Create a minimal valid DOCX
docx_path = File.expand_path("../test/fixtures/files/sample.docx", __dir__)

Zip::OutputStream.open(docx_path) do |zos|
  zos.put_next_entry("[Content_Types].xml")
  zos.write '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' \
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">' \
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>' \
    '<Default Extension="xml" ContentType="application/xml"/>' \
    '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>' \
    '</Types>'

  zos.put_next_entry("_rels/.rels")
  zos.write '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' \
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' \
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>' \
    '</Relationships>'

  zos.put_next_entry("word/_rels/document.xml.rels")
  zos.write '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' \
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' \
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>' \
    '</Relationships>'

  zos.put_next_entry("word/styles.xml")
  zos.write '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' \
    '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">' \
    '</w:styles>'

  zos.put_next_entry("word/document.xml")
  zos.write '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' \
    '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">' \
    '<w:body>' \
    '<w:p><w:r><w:t>This is a test DOCX contract between Acme Corp and Test Vendor.</w:t></w:r></w:p>' \
    '<w:p><w:r><w:t>Monthly fee: $500. Term: January 2025 to December 2025.</w:t></w:r></w:p>' \
    '</w:body>' \
    '</w:document>'
end

puts "Created DOCX fixture: #{docx_path} (#{File.size(docx_path)} bytes)"

# Create a proper PDF using prawn if available, otherwise a hand-crafted one
pdf_path = File.expand_path("../test/fixtures/files/sample.pdf", __dir__)

begin
  require "prawn"

  Prawn::Document.generate(pdf_path) do
    text "This is a test PDF contract for extraction."
    text "Vendor: TestCorp. Monthly fee: $1000."
  end
  puts "Created PDF fixture (via Prawn): #{pdf_path} (#{File.size(pdf_path)} bytes)"
rescue LoadError
  # Hand-craft a minimal valid PDF
  # This is a more carefully offset-computed PDF
  objects = []

  objects << "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n"
  objects << "2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n"
  objects << "3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>\nendobj\n"

  stream = "BT /F1 12 Tf 72 720 Td (This is a test PDF contract for extraction.) Tj ET"
  objects << "4 0 obj\n<< /Length #{stream.length} >>\nstream\n#{stream}\nendstream\nendobj\n"
  objects << "5 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\n"

  header = "%PDF-1.4\n"
  offsets = []
  pos = header.length

  objects.each do |obj|
    offsets << pos
    pos += obj.length
  end

  xref_offset = pos
  xref = "xref\n0 #{objects.length + 1}\n"
  xref += "0000000000 65535 f \n"
  offsets.each do |off|
    xref += format("%010d 00000 n \n", off)
  end

  trailer = "trailer\n<< /Size #{objects.length + 1} /Root 1 0 R >>\nstartxref\n#{xref_offset}\n%%EOF\n"

  File.write(pdf_path, header + objects.join + xref + trailer)
  puts "Created PDF fixture (hand-crafted): #{pdf_path} (#{File.size(pdf_path)} bytes)"
end
