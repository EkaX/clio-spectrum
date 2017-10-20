# Use this file to easily define all of your cron jobs.

# Load rails environment
require File.expand_path('../config/environment', __dir__)

# Set environment to current environment.
set :environment, Rails.env

# Give our jobs nice subject lines
set :subject, 'cron output'
set :recipient, 'clio-dev@library.columbia.edu'
set :job_template, "/usr/local/bin/mailifoutput -s ':subject (:environment)' :recipient  /bin/bash -c ':job'"

# CLIO DEV, CLIO TEST
if ['clio_dev', 'clio_test', 'clio_prod'].include?(@environment)

  # Still to do....
  # - cleanup search records
  # - cleanup sessions
  # - sync library hours

  # == BIBLIOGRAPHIC ==

  # Nightly incremental
  every :day, at: '1am' do
    rake 'bibliographic:extract:process EXTRACT=incremental', subject: 'daily incremental'
  end
  # Weekly cumulative, catch-up run in case we missed anything
  every :sunday, at: '4am' do
    rake 'bibliographic:extract:process EXTRACT=cumulative', subject: 'weekly cumulative'
  end

  # # FULL - to be included as needed
  # every :foobarday, at: '3:00pm' do
  #   rake 'bibliographic:extract:process EXTRACT=full', subject: 'FULL'
  # end

  #  ===  AUTHORITIES  ===

  #  Add authority variants after each daily load 
  every :day, at: '2am' do
    rake 'authorities:add_to_bib:by_extract[incremental]', subject: 'daily authorities'
  end
  # Weekly authority catch-up against cumulative
  every :sunday, at: '6am' do
    rake 'authorities:add_to_bib:by_extract[cumulative]', subject: 'weekly authorities'
  end


  # == LAW ==

  # Weekly full load of all Law records
  every :sunday, at: '8am' do
    rake 'bibliographic:extract:process EXTRACT=law', subject: 'law load'
  end

  # Add authority variants to the Law records after each load
  every :sunday, at: '10am' do
    rake 'authorities:add_to_bib:by_extract[law]', subject: 'weekly law authorities'
  end

  # # Weekly Delete of all stale Law records (3 week grace period)
  # # (TODO: this should definitely be coded into a rake task!)
  # every :sunday, at: '10am' do
  #   command '/usr/bin/curl --silent "http://lito-solr-dev1.cul.columbia.edu:8983/solr/clio_dev/update?commit=true" -H "Content-Type: text/xml" --data-binary "<delete><query>timestamp:[* TO NOW/DAY-21DAYS] AND location_facet:Law</query></delete>"', subject: 'law purge'
  # end

end


# # Run on every host - dev, test, prod
# every :day, at: '1am' do
#   rake 'metadata:process', subject: 'GeoData metadata:process output'
# end



# Examples of per-environment cron commands
# 
# if @environment == "geoblacklight_dev"
#     every :weekday, :at => '10pm' do
#         # rake "foo:bar"
#     end
# end
