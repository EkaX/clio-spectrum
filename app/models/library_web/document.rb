class LibraryWeb::Document
  attr_accessor :url, :title, :summary, :mime

  def initialize(xml_node = nil)
    if xml_node

      content_or_nil = ->(node) { node ? node.content : nil }

      @url     = content_or_nil.call(xml_node.at_css('UE'))
      @title   = content_or_nil.call(xml_node.at_css('T'))
      @summary = content_or_nil.call(xml_node.at_css('S'))
      @mime    = content_or_nil.call(xml_node.attribute('MIME'))

    end
  end
end
