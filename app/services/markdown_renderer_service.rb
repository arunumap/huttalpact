class MarkdownRendererService
  ALLOWED_TAGS = %w[
    p br hr h1 h2 h3 h4 h5 h6 strong em a blockquote ul ol li pre code
    table thead tbody tr th td img sup
  ].freeze

  ALLOWED_ATTRIBUTES = %w[href target rel src alt title class].freeze

  class HtmlRenderer < Redcarpet::Render::HTML
    def block_code(code, language)
      lexer = if language.present?
        Rouge::Lexer.find_fancy(language, code) || Rouge::Lexers::PlainText
      else
        Rouge::Lexers::PlainText
      end

      formatter = Rouge::Formatters::HTML.new
      highlighted = formatter.format(lexer.lex(code))

      %(<pre><code class="language-#{lexer.tag}">#{highlighted}</code></pre>)
    end
  end

  def self.call(markdown)
    new(markdown).call
  end

  def initialize(markdown)
    @markdown = markdown.to_s
  end

  def call
    html = renderer.render(@markdown)
    sanitizer.sanitize(html, tags: ALLOWED_TAGS, attributes: ALLOWED_ATTRIBUTES)
  end

  private

  def renderer
    @renderer ||= Redcarpet::Markdown.new(
      HtmlRenderer.new(
        filter_html: true,
        hard_wrap: true,
        link_attributes: { rel: "noopener", target: "_blank" }
      ),
      autolink: true,
      fenced_code_blocks: true,
      tables: true,
      strikethrough: true,
      no_intra_emphasis: true,
      lax_spacing: true,
      highlight: true,
      superscript: true,
      footnotes: true
    )
  end

  def sanitizer
    @sanitizer ||= Rails::Html::SafeListSanitizer.new
  end
end
