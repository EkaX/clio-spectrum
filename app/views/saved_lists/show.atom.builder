
xml.instruct!(:xml, :encoding => "UTF-8")

xml.feed("xmlns" => "http://www.w3.org/2005/Atom") do

  xml.title   @list.display_name + " Saved List"
  # an author is required, so we'll just use the app name
  xml.author { xml.name  "List owner: " + @list.owner }

  xml.link    "rel" => "self", "href" => url_for(params.to_unsafe_hash.merge(:only_path => false))
  xml.link    "rel" => "alternate", "href" => url_for(params.to_unsafe_hash.merge(:only_path => false, :format => "html")), "type" => "text/html"
  xml.id      url_for(params.to_unsafe_hash.merge(:only_path => false, :format => "html", :content_format => nil, "type" => "text/html"))

  # updated is required, for now we'll just set it to now, sorry
  xml.updated Time.now.strftime("%Y-%m-%dT%H:%M:%SZ")



  @document_list.select {|doc| doc.instance_of?(SolrDocument) }.each do |doc|
    xml.entry do
      xml.title   doc.to_semantic_values[:title][0] || doc.id

      # updated is required, for now we'll just set it to now, sorry
      xml.updated Time.now.strftime("%Y-%m-%dT%H:%M:%SZ")

      xml.link    "rel" => "alternate", "type" => "text/html", "href" => solr_document_url(doc)
      # add other doc-specific formats, atom only lets us have one per
      # content type, so the first one in the list wins.
      xml << render_link_rel_alternates(doc, :unique => true)

      xml.id      solr_document_url(doc[:id])


      if doc.to_semantic_values[:author][0]
        xml.author { xml.name(doc.to_semantic_values[:author][0]) }
      end

      with_format("html") do
        xml.summary "type" => "html" do
              # hardcode a specific CLIO partial to create HTML atom summary
              # xml.text! render_document_partial(doc, :index)
              xml.text! render('/catalog/atom_summary', :document => doc)
        end
      end

      #If they asked for a format, give it to them.
      if (params["content_format"] &&
          doc.export_formats[params["content_format"].to_sym])

          type = doc.export_formats[params["content_format"].to_sym][:content_type]

          xml.content :type => type do |content_element|
            data = doc.export_as(params["content_format"])

            # encode properly. See:
            # http://tools.ietf.org/html/rfc4287#section-4.1.3.3
            type = type.downcase
            if (type.downcase =~ /\+|\/xml$/)
              # xml, just put it right in
              content_element << data
            elsif (type.downcase =~ /text\//)
              # text, escape
              content_element.text! data
            else
              #something else, base64 encode it
              content_element << Base64.encode64(data)
            end
          end

      end


    end
  end

end




