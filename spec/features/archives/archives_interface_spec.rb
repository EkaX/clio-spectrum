require 'spec_helper'

describe 'Archives Search' do
  it 'will be able to traverse next and previous links' do
    visit archives_index_path('q' => 'papers')

    expect(page).to_not have_css('.index_toolbar a', text: 'Previous')
    expect(page).to have_css('.index_toolbar a', text: 'Next')

    all('.index_toolbar a', text: 'Next').first.click

    expect(page).to have_css('.index_toolbar a', text: 'Previous')
    expect(page).to have_css('.index_toolbar a', text: 'Next')

    all('.index_toolbar a', text: 'Previous').first.click

    expect(page).to_not have_css('.index_toolbar a', text: 'Previous')
    expect(page).to have_css('.index_toolbar a', text: 'Next')
  end

  it 'can move between item-detail and search-results', :js do
    visit archives_index_path('q' => 'files')

    expect(page).to have_css '#documents .result.document'
    within all('.result.document').first do
      find('a', text: /files/i).click
    end

    expect(find('#search_info')).to have_text('1 of')
    expect(page).to_not have_css('#search_info a', text: 'Previous')
    expect(page).to have_css('#search_info a', text: 'Next')

    find('#search_info a', text: 'Next').click

    # save_and_open_page # debug
    # save_and_open_screenshot # debug

    expect(page).to have_text '2 of '
    expect(find('#search_info')).to have_text '2 of '
    expect(page).to have_css('#search_info a', text: 'Previous')
    expect(page).to have_css('#search_info a', text: 'Next')

    find('#search_info a', text: 'Previous').click

    expect(find('#search_info')).to have_text '1 of '
    expect(page).to_not have_css('#search_info a', text: 'Previous')
    expect(page).to have_css('#search_info a', text: 'Next')

    find('#search_info a', text: 'Back to Results').click

    expect(find('.constraints-container')).to have_text 'You searched for: files'
  end

  # LIBSYS-2686 - should display provenance
  it "displays provenance" do
    # visit specific items, look for provenance data
    visit solr_document_path('11375009')
    expect(find('.info')).to have_content('Provenance Possibly written for D. T. Stoddard')

    visit solr_document_path('14439340')
    expect(find('.info')).to have_content('Provenance Stephen Desroches was immediate source of acquisition')
  end


end
