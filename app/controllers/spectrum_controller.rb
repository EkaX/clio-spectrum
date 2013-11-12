#
# SpectrumController#search() - primary entry point
#   - figures out the sources, then for each one calls:
#     SpectrumController#get_results()
#     - which for each source
#       - fixes input parameters in a source-specific way,
#       - calls either:  Spectrum::Engines::Summon.new(fixed_params)
#       -           or:  blacklight_search(fixed_params)
#
# SpectrumController#fetch() - alternative entry point
#   - does the same thing, but for AJAX calls, returning JSON
#
class SpectrumController < ApplicationController
  include Blacklight::Controller
  include Blacklight::Catalog
  include Blacklight::Configurable
  include BlacklightRangeLimit::ControllerOverride
  layout 'quicksearch'



  def search
    @results = []

    # process any Filter Queries - turn Summon API Array of key:value pairs into
    # nested Rails hash (see inverse transform in Spectrum::Engines::Summon)
    #  BEFORE: params[s.fq]="AuthorCombined:eric foner"
    #  AFTER:  params[s.fq]={"AuthorCombined"=>"eric foner"}
    # [This logic is here instead of fix_articles_params, because it needs to act
    #  upon the true params object, not the cloned copy.]
    if params['s.fq'].kind_of?(Array) or params['s.fq'].kind_of?(String)
      new_fq = {}
      key_value_array = []
      Array.wrap(params['s.fq']).each do |key_value|
        key_value_array  = key_value.split(':')
        new_fq[ key_value_array[0] ] = key_value_array[1] if key_value_array.size == 2
      end
      params['s.fq'] = new_fq
    end

    session['search'] = params

    @search_layout = SEARCHES_CONFIG['layouts'][params['layout']]

    # First, try to detect if we should go to the landing page.
    # But... Facet-Only searches are still searches.
    if params['q'].nil? && params['s.q'].nil? &&
       params['s.fq'].nil? && params['s.ff'].nil? ||
          (params['q'].to_s.empty? && @active_source == 'library_web')
      flash[:error] = "You cannot search with an empty string." if params['commit']
    elsif @search_layout.nil?
      flash[:error] = "No search layout specified"
      redirect_to root_path
    else
      @search_style = @search_layout['style']
      @has_facets = @search_layout['has_facets']
      sources =  @search_layout['columns'].collect { |col|
        col['searches'].collect { |item| item['source'] }
      }.flatten

      @action_has_async = true if @search_style == 'aggregate'

      if @search_style == 'aggregate' && !session[:async_off]
        @action_has_async = true
        @results = {}
        sources.each { |source| @results[source] = {} }
      else
        @results = get_results(sources)
      end

    end

    @show_landing_pages = true if @results.empty?
  end


  def fetch

    @search_layout = SEARCHES_CONFIG['layouts'][params[:layout]]

    @datasource = params[:datasource]

    if @search_layout.nil?
      render :text => "Search layout invalid."
    else
      @fetch_action = true
      @search_style = @search_layout['style']
      @has_facets = @search_layout['has_facets']
      sources =  @search_layout['columns'].collect { |col|
        col['searches'].collect { |item| item['source'] }
      }.flatten.select { |source| source == @datasource }

      @results = get_results(sources)
      render 'fetch', layout: 'js_return'

    end

  end

  private

  def fix_articles_params(params)
    # Rails.logger.debug "fix_articles_params() in params=#{params.inspect}"

    params['authorized'] = @user_characteristics[:authorized]

    # Article searches within QuickSearch should act as New searches
    params['new_search'] = 'true' if @active_source == 'quicksearch'
    # QuickSearch is only one of may possible Aggregates - so maybe this instead?
    # params['new_search'] = 'true' if @search_style == 'aggregate'

    # seeing a "q" param means a submit directly from the basic search box
    # OR from a direct link
    # (instead of from a facet, or a sort/paginate link, or advanced search)
    q_param = params['q']
    if q_param
      # which search field was selected from the drop-down?  default s.q
      search_field = params['search_field'] ||= 's.q'
      # LibraryWeb QuickSearch will pass us "search_field=all_fields",
      # which means to do a Summon search against 's.q'
      search_field = 's.q' if search_field == 'all_fields'

      if search_field == 's.q'
        # If s.q (default simple summon search)...
        # move the CLIO-interface "q" to what Summon works with, "s.q"
        params['s.q']            = q_param
        session['search']['s.q'] = q_param
      else
        # If the search field is a filter query (s.fq), e.g. "s.fq[TitleCombined]"...
        hash = Rack::Utils.parse_nested_query("#{search_field}=#{q_param}")
        params.merge! hash
        # explicitly set base query s.q to emtpy string
        params['s.q'] = ''
        session['search']['s.q'] = ''
      end

      # why knock these out?
      # So that this isn't passed along in the built navigation URLs,
      # which interferes when we try to "X" our keyword term.
      params.delete('q')
      # This we want to leave in (don't delete), so our selected field remains?
      # params.delete('search_field')
    end

    if params['pub_date']
      params['s.cmd'] = "setRangeFilter(PublicationDate,#{params['pub_date']['min_value']}:#{params['pub_date']['max_value']})"
    end

    # Rails.logger.debug "fix_articles_params() out params=#{params.inspect}"
    params
  end

  def get_results(sources)
    @result_hash = {}
    new_params = params.to_hash
    sources.listify.each do |source|

      fixed_params = new_params.deep_clone
      %w{layout commit source sources controller action}.each { |param_name|
         fixed_params.delete(param_name)
      }
      fixed_params.delete(:source)
      # "results" is not the search results, it's the engine object, in a
      # post-search-execution state.
      results = case source
        when 'dissertations'
          fixed_params['source'] = 'dissertations'
          fixed_params = fix_articles_params(fixed_params)
          Spectrum::Engines::Summon.new(fixed_params)

        when 'articles'
          fixed_params['source'] = 'articles'
          fixed_params = fix_articles_params(fixed_params)
          Spectrum::Engines::Summon.new(fixed_params)

        when 'newspapers'
          fixed_params['source'] = 'newspapers'
          fixed_params = fix_articles_params(fixed_params)
          Spectrum::Engines::Summon.new(fixed_params)

        when 'ebooks'
          fixed_params['source'] = 'ebooks'
          fixed_params = fix_articles_params(fixed_params)
          Spectrum::Engines::Summon.new(fixed_params)

        when 'catalog_ebooks'
          fixed_params['source'] = 'catalog_ebooks'
          blacklight_search(fixed_params)

        when 'databases'
          fixed_params['source'] = 'databases'
          blacklight_search(fixed_params)

        when 'journals'
          fixed_params['source'] = 'journals'
          blacklight_search(fixed_params)

        when 'catalog_dissertations'
          fixed_params['source'] = 'catalog_dissertations'
          blacklight_search(fixed_params)

        when 'catalog'
          fixed_params['source'] = 'catalog'
          blacklight_search(fixed_params)

        when 'academic_commons'
          fixed_params['source'] = 'academic_commons'
          blacklight_search(fixed_params)

        when 'ac_dissertations'
          fixed_params['source'] = 'ac_dissertations'
          blacklight_search(fixed_params)

        when 'library_web'
          # GoogleAppliance engine can't handle absent q param
          fixed_params['q'] ||= ''
          Spectrum::Engines::GoogleAppliance.new(fixed_params)

        when 'catalog_trial'
          fixed_params['source'] = 'catalog_trial'
          blacklight_search(fixed_params)

        else
          # raise Error.new("SpectrumController#get_results() unhandled source: '#{source}'")
          raise "SpectrumController#get_results() unhandled source: '#{source}'"
        end

      @result_hash[source] = results
    end

    @result_hash
  end
end
