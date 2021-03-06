module CulFacetsHelper
  # CUL local view partials call cul_facet_field_in_params?,
  # which calls BL facet_field_in_params? against field and negated-field
  def cul_facet_field_in_params?(field)
    return true if facet_field_in_params?(field)

    negated_field = "-#{field}"
    # Can't do this - blacklight_range_limit assumes that the string
    # passed in to facet_field_in_params?() is a valid Solr field name.
    # facet_field_in_params?(field) || facet_field_in_params?(negated_field)
    return true if params[:f] && params[:f][negated_field]
    false
  end

  ##
  # Check if the query parameters have the given facet field with the
  # given value.
  #
  # @param [Object] facet field
  # @param [Object] facet value
  # @return [Boolean]
  def facet_in_params?(field, item)
    field = item.field if item && item.respond_to?(:field)

    value = facet_value_for_facet_item(item)

    return true if facet_field_in_params?(field) && params[:f][field].include?(value)

    negated_field = "-#{field}"
    # Can't do this - blacklight_range_limit assumes that the string
    # passed in to facet_field_in_params?() is a valid Solr field name.
    # return true if facet_field_in_params?(negated_field) and params[:f][negated_field].include?(value)

    return true if params[:f] && params[:f][negated_field] && params[:f][negated_field].include?(value)

    false
  end

  # Based on Blacklight::FacetsHelperBehavior.render_selected_facet_value()
  def render_selected_excluded_facet_value(excluded_solr_field, item)
    remove_href = search_action_path(search_state.remove_facet_params(excluded_solr_field, item))

    content_tag(:span, class: 'facet-label') do
      content_tag(:span, "NOT #{facet_display_value(excluded_solr_field, item)}", class: 'selected') +
        # remove link
        link_to(remove_href, class: 'remove') do
          content_tag(:span, '', class: 'glyphicon glyphicon-remove') +
            content_tag(:span, '[remove]', class: 'sr-only')
        end
    end
  end

  # Override core blacklight render_constraints_helper_behavior.rb
  # module Blacklight::RenderConstraintsHelperBehavior#render_filter_element
  def render_filter_element(facet, values, localized_params)
    is_negative = facet =~ /^-/ ? 'NOT ' : ''
    proper_facet_name = facet.gsub(/^-/, '')

    facet_config = facet_configuration_for_field(proper_facet_name)

    values.map do |val|
      render_constraint_element(
        facet_field_label(proper_facet_name),
        is_negative + facet_display_value(proper_facet_name, val),
        remove: url_for(remove_facet_params(facet, val, localized_params)),
        classes: ['filter', 'filter-' + proper_facet_name.parameterize]
      ) + "\n"
    end
  end

  def expand_all_facets?
    get_browser_option('always_expand_facets') == 'true'
  end

  def build_facet_tag(facet_field, _datasource = active_source)
    facet_field_label = if facet_field.is_a? String
                          facet_field
                        elsif facet_field.respond_to?(:field)
                          facet_field.field
                        elsif facet_field.respond_to?(:display_name)
                          facet_field.display_name
                        elsif facet_field.respond_to?(:field_name)
                          facet_field.field_name
                        else
                          ''
                          raise
    end
    # facet_tag = active_source + '_' + facet_field.field.parameterize
    facet_tag = active_source + '_' + facet_field_label
  end

  ##
  ##   #####   BLACKLIGHT 5    #####
  ##   override Blacklight::FacetsHelperBehavior,
  ##   to add support for NEXT-1028
  ##
  # Determine whether a facet should be rendered as collapsed or not.
  #   - if the facet is 'active', don't collapse
  #   - if the facet is configured to collapse (the default), collapse
  #   - if the facet is configured not to collapse, don't collapse
  #
  # @param [Blacklight::Configuration::FacetField]
  # @return [Boolean]
  #
  # Columbia Override
  # Accept a Blacklight Facet, a Summon Facet, or a String
  # Check against our Browser Options
  def should_collapse_facet?(facet_field)
    # 1) If the facet is 'active', don't collapse

    # For Summon Facets
    if facet_field.respond_to?(:has_applied_value?)
      return false if facet_field.has_applied_value?
    end
    # For Blacklight Facets
    if facet_field.respond_to?(:field)
      return false if facet_field_in_params?(facet_field.field)
    end

    # 2) Columbia - check browser options for display preference
    # NEXT-1028 - Make facet state (open/closed) sticky through a selection
    # Do we have an explicit browser-display setting saved?
    # If so, respect that saved setting ("Sticky").
    facet_tag = build_facet_tag(facet_field, active_source)
    return false if get_browser_option(facet_tag) == 'open'
    return true if get_browser_option(facet_tag) == 'closed'

    # 3) "if the facet is configured..."
    # Last fall-back, if the facet has a config option, respect it
    return facet_field.collapse if facet_field.respond_to?(:collapse)

    # Default state if nothing indicates otherwise....
    true
  end

  # # Is there something telling us to render this facet as open?
  # def render_facet_open?(facet_field, datasource = active_source)
  #   # Do we have "Expand All Facets" turned on?
  #   return true if expand_all_facets?
  #
  #   # Is the facet itself configured to display as open?
  #   return true if facet_field && facet_field.respond_to?(:open) && facet_field.open == true
  #
  #   # NEXT-1028 - Make facet state (open/closed) sticky through a selection
  #   # Do we have an explicit browser-display setting saved?
  #   # If so, respect that saved setting ("Sticky").
  #   facet_tag = build_facet_tag(facet_field, datasource)
  #   return true if get_browser_option(facet_tag) == 'open'
  #   return false if get_browser_option(facet_tag) == 'closed'
  #
  #   # Nothing told us to render this facet as open, so it'll be closed.
  #   false
  # end
  
  # CLIO includes a Search Options with quick-select toggles.
  # One of them replicates the format:Online facet, 
  # but with a check-mark GUI widget
  def render_online_toggle
    onlineFacetItem = Blacklight::Solr::Response::Facets::FacetItem.new(value: 'Online')

    # Is format:Online already selected?
    if facet_in_params?('format', 'Online')
      # the "remove facet" url
      url = search_action_path(search_state.remove_facet_params('format', onlineFacetItem))
      icon = content_tag(:span, '', class: 'glyphicon glyphicon-check')
    # Is format:Online not yet selected?
    else
      # the "add facet" url
      url = path_for_facet('format', onlineFacetItem)
      icon = content_tag(:span, '', class: 'glyphicon glyphicon-unchecked')
    end
    
    content_tag(:div, 
    link_to(icon, url) + ' Online only'
    )
            
  end

  # CLIO includes a Search Options with quick-select toggles.

  # Committee doesn't want this
  # # One of CLIO's Search Options toggles replicates the format:Online facet,
  # # but with a check-mark GUI widget
  # def render_online_toggle
  #   onlineFacetItem = Blacklight::Solr::Response::Facets::FacetItem.new(value: 'Online')
  #
  #   # Is format:Online already selected?
  #   if facet_in_params?('format', 'Online')
  #     # the "remove facet" url
  #     url = search_action_path(search_state.remove_facet_params('format', onlineFacetItem))
  #     icon = content_tag(:span, '', class: 'glyphicon glyphicon-check')
  #   # Is format:Online not yet selected?
  #   else
  #     # the "add facet" url
  #     url = path_for_facet('format', onlineFacetItem)
  #     icon = content_tag(:span, '', class: 'glyphicon glyphicon-unchecked')
  #   end
  #
  #   content_tag(:div, link_to(icon, url) + ' Online only')
  # end

  # Another of CLIO's Search Options toggles controls render_govdocs_togglet GovDocs docs are included in search-results
  def render_govdocs_toggle
    # Are we currently excluding GovDocs?
    # If so, (1) render toggle as checked, (2) link to un-exclude
    excluded_format_field = '-format'
    govdocs_item = 'US Government Document'

    if params['f'] && params['f'][excluded_format_field] && params['f'][excluded_format_field].include?(govdocs_item)
      icon = content_tag(:span, '', class: 'glyphicon glyphicon-check')
      url = search_action_path(search_state.remove_facet_params(excluded_format_field, govdocs_item))
    else
      icon = content_tag(:span, '', class: 'glyphicon glyphicon-unchecked')
      # first, clear out "format=govdoc" if it's there
      without_govdocs = search_state.remove_facet_params('format', govdocs_item)
      new_state = search_state.reset(without_govdocs)
      # same search, but w/govdocs excluded:
      url = search_action_path(new_state.add_facet_params_and_redirect(excluded_format_field, govdocs_item))
    end

    label = 'Exclude Online U.S. Government Information'
    content_tag(:div, link_to(icon, url) + ' ' + label)
  end
  
end
