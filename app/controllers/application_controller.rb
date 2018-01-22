## Top level controller defining application-wide behaviors,
# filters, authentication, methods used throughout multiple
# classes, etc.
require 'mail'
class ApplicationController < ActionController::Base
  helper_method :set_browser_option, :get_browser_option, :debug_timestamp

  # Adds a few additional behaviors into the application controller
  include Blacklight::Controller
  include Blacklight::Catalog
  include Blacklight::Configurable

  include BrowseSupport
  include PreferenceSupport

  # Please be sure to implement current_user and user_session. Blacklight depends on
  # these methods in order to perform user specific actions.
  check_authorization
  skip_authorization_check

  # Set headers to prevent all caching in authenticated sessions,
  # so that people can't 'back' in the browser to see possibly secret stuff.
  before_filter :set_cache_headers

  before_filter :apply_random_q
  # before_filter :trigger_async_mode
  before_filter :trigger_debug_mode
  before_filter :by_source_config
  before_filter :log_additional_data
  before_filter :set_user_characteristics
  before_filter :condense_advanced_search_params

  # https://github.com/airblade/paper_trail/#4a-finding-out-who-was-responsible-for-a-change
  before_filter :set_paper_trail_whodunnit

  # Access to the current ApplicationController instance from anywhere
  # https://stackoverflow.com/a/33774123/1343906
  cattr_accessor :current
  before_filter { ApplicationController.current = self }
  after_filter  { ApplicationController.current = nil  }

  # NEXT-537 - logging in should not redirect you to the root path
  # from the Devise how-to docs...
  # https://github.com/plataformatec/devise/wiki/
  # How-To:-Redirect-back-to-current-page-after-sign-in,-sign-out,-sign-up,-update
  before_filter :store_location

  # Polling for logged-in-status shouldn't update the devise last-activity tracker
  prepend_before_action :skip_timeout, only: [:render_session_status, :render_session_timeout]
  def skip_timeout
    request.env["devise.skip_trackable"] = true
  end

  rescue_from CanCan::AccessDenied do |exception|
    # note - access denied gives a 302 redirect, not 403 forbidden.
    # see https://github.com/ryanb/cancan/wiki/exception-handling
    redirect_to root_url, alert: exception.message
  end

  rescue_from ActionView::MissingTemplate do |exception|
    if request.format == 'html'
      redirect_to root_url, alert: exception.message
    else
      Rails.logger.warn "request.format = #{request.format}"
      Rails.logger.warn "#{exception}"
      render nothing: true
    end
  end

  def apply_random_q
    if params[:random_q]
      start = Time.now
      chosen_line = nil
      line_to_pick = rand(11_917)
      input_file = File.join(Rails.root.to_s, 'config', 'opac_searches_sorted.txt')
      File.foreach(input_file).each_with_index do |line, number|
        chosen_line = line if number == line_to_pick
      end
      params['q'] = chosen_line
      # params['s.q'] = chosen_line
    end
  end

  def condense_advanced_search_params
    advanced_search_params = params['adv'] || {}
    advanced_search_params = {} if advanced_search_params == '{}'
    new_hash = {}
    counter = 1
    advanced_search_params.each_pair do |adv_field_number, attrs|

      if attrs && !attrs['field'].to_s.empty? && !attrs['value'].to_s.empty?
        new_hash[counter.to_s] = attrs
        counter += 1
      end
    end
    params['adv'] = new_hash
  end

  def set_user_characteristics
    # remote_ip gives back whatever's in X-Forwarded-For, which can
    # be manipulated by the client.  use remote_addr instead.
    # this will have to be revisited if/when clio lives behind a proxy.
    client_ip = request.remote_addr
    is_on_campus = User.on_campus?(client_ip)
    @user_characteristics =
    {
      ip: client_ip,
      on_campus: is_on_campus
    }
    @debug_entries[:user_characteristics] = @user_characteristics
  end


  # AJAX handler for browser-option setting/getting
  def set_browser_option_handler
    unless params.key?('name') && params.key?('value')
      render json: nil, status: :bad_request and return
    end

    set_browser_option(params['name'], params['value'])
    render json: nil, status: :ok
  end

  # Rails method for browser-option setting/getting
  def set_browser_option(name, value)
    _clio_browser_options = YAML.load(cookies[:_clio_browser_options] || '{}')
    _clio_browser_options = {} unless _clio_browser_options.is_a?(Hash)
    _clio_browser_options[name] = value
    cookies[:_clio_browser_options] = { value: _clio_browser_options.to_yaml,
                                        expires: 1.year.from_now }
  end

  # AJAX handler for browser-option setting/getting
  def get_browser_option_handler
    if params.key?('value') || !params.key?('name')
      render json: nil, status: :bad_request and return
    end

    if value = get_browser_option(params['name'])
      render json: value, status: :ok
    else
      render json: nil, status: :not_found
    end
  end

  # Rails method for browser-option setting/getting
  def get_browser_option(name)
    _clio_browser_options = YAML.load(cookies[:_clio_browser_options] || '{}')
    _clio_browser_options.is_a?(Hash) ? _clio_browser_options[name] : nil
  end

  # AJAX handler for persistence of selected-items
  def selected_items_handler

    unless params.key?('verb')
      render json: nil, status: :bad_request and return
    end

    verb = params['verb']
    id_param = params['id_param']

    selected_item_list = Array(session[:selected_items]).flatten

    case verb
    when 'add'
      return render json: nil, status: :bad_request unless id_param
      selected_item_list.push(id_param)
    when 'remove'
      return render json: nil, status: :bad_request unless id_param
      selected_item_list.delete(id_param)
    when 'clear'
      selected_item_list = []
    when 'reset'
      # return render json: nil, status: :bad_request unless id_param
      # Fail silently for this one - it's run on every page load
      # Or... maybe reset to a null list if id_param isn't given?
      id_param = [] unless id_param
      selected_item_list = id_param if id_param
    else
      render json: nil, status: :bad_request and return
    end

    session[:selected_items] = selected_item_list

    render json: nil, status: :ok
  end


  # Called from SpectrumController.get_results()
  # and from CatalogController.index()
  def blacklight_search(sent_options = {})
    # raise
    Rails.logger.debug "ApplicationController#blacklight_search(sent_options=#{sent_options.inspect})"
    options = sent_options.deep_clone
    options['source'] = $active_source unless options['source']
    options['debug_mode'] = @debug_mode
    options['current_user'] = current_user

    # this new() actually runs the search.
    # [ the Solr engine call perform_search() within it's initialize() ]
    debug_timestamp('blacklight_search() calling Solr.new()')
    search_engine = Spectrum::SearchEngines::Solr.new(options)
    debug_timestamp('blacklight_search() Solr.new() complete.')

    if search_engine.successful?
      @response = search_engine.search
      @results = search_engine.documents
      if search_engine.total_items > 0
        # No, leave this to happen via async AJAX onload
        # look_up_clio_holdings(@results)

        # Currently, item-alerts only show within the Databases data source.
        # Why?
        if $active_source.present? && $active_source == 'databases'
          add_alerts_to_documents(@results)
        end
      end
    end

    @debug_entries ||= {}

    # our search engine classes don't inherit from ApplicationController.
    # they may set their own @debug_entries instance variables, which we
    # here need to merge in with the controller-level instance variable.
    @debug_entries = @debug_entries.recursive_merge(search_engine.debug_entries)

    search_engine
  end

  # def trigger_async_mode
  #   if params.delete('async_off') == 'true'
  #     session[:async_off] = true
  #   elsif params.delete('async_on') == 'true'
  #     session[:async_off] = nil
  #   end
  # end

  def trigger_debug_mode
    params_debug_mode = params['debug_mode']

    if params_debug_mode == 'on'
      @debug_mode = true
    elsif params_debug_mode == 'off'
      @debug_mode = false
    else
      @debug_mode ||= session['debug_mode'] || false
    end

    params.delete('debug_mode')

    unless current_user
      @debug_mode = false
    end

    # 11/2017 - CUD wants to see debug details
    @debug_mode = true if current_user && current_user.has_role?('site', 'pilot')

    session['debug_mode'] = @debug_mode

    @current_user = current_user
    default_debug
  end

  def default_debug
    @debug_start_time = Time.now
    @debug_entries = Hash.arbitrary_depth
    @debug_entries['params'] = params

    # Rails 4?  session.inspect now dumps full object internals,
    # instead of just stored keys/values.  Convert to hash first.
    @debug_entries['session'] = session.to_hash

    # ENV is environment variables, but not the HTTP-related env variables
    # @debug_entries['environment'] = ENV
    @debug_entries['request.referer'] = request.referer
    @debug_entries['timestamps'] = []
    debug_timestamp('setup')
  end

  def debug_timestamp(label = 'timestamp')
    elapsed = (Time.now - @debug_start_time) * 1000
    @debug_entries['timestamps'] << { label => "#{elapsed.round(0)} ms" }
  end

  def determine_active_source
    # return params['datasource'] if params.has_key? 'datasource'

    # Try to find the datasource,
    # first in the params,
    # second in the path
    source = if params.has_key? 'datasource'
      params['datasource']
    else
      request.path.to_s.gsub(/^\//, '').gsub(/\/.*/, '')
    end

    # Remap as necessary...
    # shelf-browse is part of the catalog datasource
    if source == 'browse'
      source = 'catalog'
    end

    # If what we found is a real source, use it.
    # Otherwise, fall back to quicksearch as a default.
    if DATASOURCES_CONFIG['datasources'].has_key?(source)
      # Some pseudo-sources (e.g., 'catalog_dissertations') are just 
      # customizations of their super-sources.  Check for that.
      if DATASOURCES_CONFIG['datasources'][source].has_key?('supersource')
        return DATASOURCES_CONFIG['datasources'][source]['supersource']
      else
        return source
      end
    else
      return 'quicksearch'
    end

  end

  # def connection(source = $active_source)
  #   if self.respond_to?(:blacklight_config)
  #     @connections ||= {}
  #     @connections[source] || (@connections[source] = Spectrum::SearchEngines::Solr.generate_rsolr(source))
  #   end
  # end

  def repository_class
    Spectrum::SolrRepository
  end

  def blacklight_config(source = $active_source)
    @blacklight_configs ||= {}
    @blacklight_configs[source] || (@blacklight_configs[source] = Spectrum::SearchEngines::Solr.generate_config(source))
  end

  def catch_404s
    unrouted_uri = request.fullpath
    alert = "remote ip: #{request.remote_ip}   Invalid URL: #{unrouted_uri}"
    logger.warn alert
    redirect_to root_path, alert: alert
  end

  # 7/13 - we'll need to send email from multiple datasources,
  # so move this core function to application controller.
  # (remove catalog-specific, solr-specific code???)

  # NEXT-556 - send citation to more than one email address at a time
  # Override Blacklight core method, which limits to single email.
  # --
  # And now, since we've overridden this anyway, make some fixes.
  # Like, don't do Solr lookup on ID when generating form (AJAX GET),
  # only when sending emails (AJAX PUT)

  # Email Action (this will render the appropriate view on GET requests and process the form and send the email on POST requests)
  def email
    mail_to = params[:to]
    #allow user to enter email address and name to include in email (NEXT-910)
    if params[:reply_to]
      reply_to = Mail::Address.new params[:reply_to]
      reply_to.display_name = params[:name]
    end
    # We got a post - that is, a submitted form, with a "To" - send the email!
    if request.post? && (current_user.present? || @user_characteristics[:on_campus] || verify_recaptcha)
      if mail_to
        url_gen_params = { host: request.host_with_port, protocol: request.protocol }

        if mail_to.match(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,4}/)
          # IDs may be Catalog Bib keys or Summon FETCH IDs...
          @documents = ids_to_documents(params[:id])
          if @documents.nil? || @documents.empty?
            flash[:error] = I18n.t('blacklight.email.errors.invalid')
          else
            message_text = params[:message]
            email = RecordMailer.email_record(@documents, { to: mail_to, reply_to: reply_to.format, message: message_text }, url_gen_params)
          end
        else
          flash[:error] = I18n.t('blacklight.email.errors.to.invalid', to: mail_to)
        end
      else
        flash[:error] = I18n.t('blacklight.email.errors.to.blank')
      end

      unless params['id']
        flash[:error] = I18n.t('blacklight.email.errors.invalid')
      end

      unless flash[:error]
        email.deliver_now
        flash[:success] = 'Email sent'
        redirect_to solr_document_path(params['id']) unless request.xhr?
      end
    else
      #pre-fill email form with user's email and name (NEXT-810)
      if current_user
        reply_to = Mail::Address.new current_user.email
        reply_to.display_name = "#{current_user.first_name} #{current_user.last_name}"
        @display_name = reply_to.display_name if reply_to
        @reply_to = reply_to.address if reply_to
      end
    end

    # This is supposed to catch the GET - return the HTML of the form
    unless !request.xhr? && flash[:success]
      respond_to do |format|
        format.js { render layout: false }
        format.html
      end
    end
  end

  def ids_to_documents(id_array = [])
    # Array-ize single id inputs: '123' --> [ '123' ] 
    id_array = Array.wrap(id_array)
    document_array = []
    return document_array unless id_array.kind_of?(Array)
    return document_array if id_array.empty?

    # First, split into per-source lists,
    # (depend on Summon IDs to start with "FETCH"...)
    catalog_item_ids = []
    articles_item_ids = []
    Array.wrap(id_array).each do |item_id|
      if item_id.start_with?('FETCH')
        articles_item_ids.push item_id
      else
        catalog_item_ids.push item_id
      end
    end

    catalog_document_list = []
    if catalog_item_ids.any?
      # Then, do two source-specific set-of-id lookups

      extra_solr_params = {
        rows: catalog_item_ids.size
      }

      # NEXT-1067 - Saved Lists broken for very large lists (~400)
      # fix by breaking into slices
      catalog_item_ids.each_slice(100) { |slice|
        # response, slice_document_list = get_solr_response_for_field_values(SolrDocument.unique_key, slice, extra_solr_params)
        response, slice_document_list = fetch(slice, extra_solr_params)
        catalog_document_list += slice_document_list
      }
    end

    article_document_list = []
    if articles_item_ids.any?
      article_document_list = get_summon_docs_for_id_values(articles_item_ids)
    end

    # Then, merge back, in original order
    key_to_doc_hash = {}
    catalog_document_list.each do |doc|
      key_to_doc_hash[ doc[:id]] = doc
    end
    article_document_list.each do |doc|
      key_to_doc_hash[ doc.id] = doc
    end

    id_array.each do |id|
      document_array.push key_to_doc_hash[id]
    end
    document_array
  end


  def get_summon_docs_for_id_values(id_array)
    return [] unless id_array.kind_of?(Array)
    return [] if id_array.empty?

    @params = {
      'spellcheck' => true,
      's.ho' => true,
      # 's.cmd' => 'addFacetValueFilters(ContentType, Newspaper Article)',
      # 's.ff' => ['ContentType,and,1,5', 'SubjectTerms,and,1,10', 'Language,and,1,5']
    }

    @config = APP_CONFIG['summon']
    @config.merge!(url: 'http://api.summon.serialssolutions.com/2.0.0')
    @config.symbolize_keys!

    @params['s.cmd'] ||= "setFetchIDs(#{id_array.join(',')})"

    # @params['s.q'] ||= ''
    @params['s.fq'] ||= ''
    @params['s.role'] ||= ''

    @errors = nil
    begin
      @service = ::Summon::Service.new(@config)

      # Rails.logger.info "[Spectrum][Summon] config: #{@config}"
      # Rails.logger.info "[Spectrum][Summon] params: #{@params}"

      ### THIS is the actual call to the Summon service to do the search
      @search = @service.search(@params)

    rescue => ex
      # Rails.logger.error "[Spectrum][Summon] error: #{e.message}"
      @errors = ex.message
    end

    # we choose to return empty list instead of nil
    @search ? @search.documents : []
  end

  # Render a true or false, for if the user is logged in
  def render_session_status
    Rails.logger.debug "status=#{!!current_user}"
    response.headers["Etag"] = ""  # clear etags to prevent caching
    render plain: !!current_user, status: 200
  end

  def render_session_timeout
    flash[:notice] = "Authenticated session been has timed out.  Now browsing anonymously."
    # redirect_to "/login"
    redirect_to root_path
  end

  private

  def set_cache_headers
    if current_user
      response.headers["Cache-Control"] = "no-cache, no-store"
      response.headers["Pragma"] = "no-cache"
      response.headers["Expires"] = "Fri, 01 Jan 1990 00:00:00 GMT"
    end
  end


  def by_source_config
    $active_source = determine_active_source
  end

  # NEXT-537 - logging in should not redirect you to the root path
  # from the Devise how-to docs...
  # https://github.com/plataformatec/devise/wiki/
  # How-To:-Redirect-back-to-current-page-after-sign-in,-sign-out,-sign-up,-update

  def store_location
    fullpath = request.fullpath
    # store this as the last-acccessed URL, except for exceptions...

    session[:previous_url] = fullpath unless
      # No AJAX ever
      request.xhr? or
      # exclude /users paths, which reflect the login process
      fullpath =~ /\/users/ or
      fullpath =~ /\/backend/ or
      fullpath =~ /\/catalog\/unapi/ or
      fullpath =~ /\/catalog\/.*\.endnote/ or
      fullpath =~ /\/catalog\/email/ or
      # exclude lists VERBS, but don't wildcare /lists or viewing will break
      fullpath =~ /\/lists\/add/ or
      fullpath =~ /\/lists\/move/ or
      fullpath =~ /\/lists\/remove/ or
      fullpath =~ /\/lists\/email/ or
      # /spectrum/fetch - loading subpanels of bento-box aggregate
      fullpath =~ /\/spectrum/ or
      # old-style async ajax holdings lookups - obsolete?
      fullpath =~ /\/holdings/ or
      # Persistent selected-item lists
      fullpath =~ /\/selected/ or
      # auto-timeout polling
      fullpath =~ /\/active/
  end

  # DEVISE callback
  # https://github.com/plataformatec/devise/wiki/ ... 
  #     How-To:-Redirect-to-a-specific-page-on-successful-sign-in-and-sign-out
  def after_sign_in_path_for(resource = nil)
    session[:previous_url] || root_path
  end

  protected

  def log_additional_data
    request.env['exception_notifier.url'] = {
      url: "#{request.protocol}#{request.host_with_port}#{request.fullpath}"
    }
  end

  def add_alerts_to_documents(documents)
    documents = Array.wrap(documents)
    return if documents.length == 0

    # # initialize
    # documents.each do |doc|
    #   raise
    #   doc.to_h['_item_alerts'] = {}
    #   ItemAlert::ALERT_TYPES.each do |alert_type, label|
    #     doc['_item_alerts'][alert_type] = []
    #   end
    # end

    # fetch all alerts for current doc-set, in single query
    alerts = ItemAlert.where(source: 'catalog',
                             item_key: documents.map(&:id)).includes(:author)

    # loop over fetched alerts, adding them in to their documents
    alerts.each do |alert|
      this_alert_type = alert.alert_type

      # skip over no-longer-used alert types that may still be in the db table
      next unless ItemAlert::ALERT_TYPES.key?(this_alert_type)

      document = documents.find do |doc|
        doc.fetch('id').to_s == alert.item_key.to_s
      end

      document.item_alerts[this_alert_type] << alert

      document['_active_item_alert_count'] ||= 0
      document['_active_item_alert_count'] += 1 if alert.active?

    end
  end
end
