
// $('.best_bets_typeahead').onInput = function() {
//   alert('Edit to input field');
// };

$('.best_bets_typeahead').on("input", function(e) {


  inputBox = e.target;

  if (inputBox.classList.contains('tt-input')) {
    // alert('tt-input already');
    return;
  }else {
    // alert('no tt-input, adding...');
  };
  

//   alert('try two');
// });
// 
// $(document).ready(function() {

  // retrieve data embedded on page
  var best_bets_url = $('#best_bets').data('url')

  // build Best Bets typeahead
  if (typeof(best_bets_url) != 'undefined') {

    // (1) build the search engine
    var bestBets = new Bloodhound({
      queryTokenizer: Bloodhound.tokenizers.whitespace,
      // Look for the query value in any of the list of fields
      // datumTokenizer: Bloodhound.tokenizers.obj.whitespace('title', 'description', 'keywords'),
      // or search a single concattenated field?
      // datumTokenizer: Bloodhound.tokenizers.obj.whitespace( 'haystack' ),
      // Nope, now they only want Title and Keywords
      // datumTokenizer: Bloodhound.tokenizers.obj.whitespace('title', 'keywords'),
      // Nope.  The librarians need absolute control, so don't search on
      // what the user sees at all, only on the managed key search terms.
      datumTokenizer: Bloodhound.tokenizers.obj.whitespace('keywords'),

      // Sort suggestions by their Title field, alphabetically
      sorter: function (a, b) { 
        var stopwords = ['a', 'an', 'the'];
        var stripper = new RegExp('\\b('+stopwords.join('|')+')\\b', 'ig')
        var titleA = a.title.replace(stripper, '').trim();
        var titleB = b.title.replace(stripper, '').trim();
        var comparison = titleA.localeCompare(titleB); 
        return comparison;
      },

      prefetch: {
        url: best_bets_url,
        cache: false,
        // "time in ms to cache, default 86400000 (1 day)" - doesn't work?
        ttl: 1,
      }
      // for testing....
      // local: ['dog', 'pig', 'moose'],
      // local: [{title: 'dog'}, {title: 'pig'}, {title: 'moose'}],
    });



    // (2) build the user interface
    $('.best_bets_typeahead').typeahead(
      { 
        // How many typed characters trigger Best Bets suggestions?
        minLength: 3,
        hint: false,
      }, 
      { 
         name: 'best-bets',
         source: bestBets,
         templates: {
          suggestion: function (data) {
            snippet = buildSnippet(data);
            return snippet;
          },
        },
        // How many best-bet suggestions should be displayed?
        limit: 7,
        display: 'title',
      }
    );

    // SELECT - OPEN URL IN NEW WINDOW
    $('.best_bets_typeahead').bind('typeahead:select', function(ev, suggestion) { 

      // console.log('>> typeahead:select triggered'); 
      // console.log("val is now set to:" + $(this).typeahead('val')  );
      // console.log("ev.target.value is now set to:" + ev.target.value);
      // console.log("ev.target.saved_value is now set to:" + ev.target.saved_value);
      // console.log(suggestion);

      // $(this).typeahead('val', ev.target.saved_value);
      // ev.target.value = ev.target.saved_value

      // if user has decided to use a best-best (click/enter), then...
      if ('url' in suggestion && suggestion.url.length > 0) {
        // (1) clear out the input field
        $(this).typeahead('val', '');
        // (2) jump to the URL in a new window
        window.open(suggestion.url, '_blank');
      }
    
      // console.log("** manually closing typeahead **")
      // $(this).typeahead('close');
      // console.log("** done **")

    }  );

    // CURSORCHANGE (up/down within suggestion list) 
    // - DON'T REPLACE USER INPUT WITH TT HINT VALUE
    $('.best_bets_typeahead').bind('typeahead:cursorchange', function(ev, suggestion) {
      console.log('>> typeahead:cursorchange'); 
      // console.log(ev);
      // console.log("val is now set to:" + $(this).typeahead('val')  );
      // console.log("ev.target.value is now set to:" + ev.target.value);
    
      // reset the input box value with the original value (not the suggestion)
      ev.target.value = $(this).typeahead('val');
    });


    // Experiments w/saving user's input before TT replaces it.
    // $('.best_bets_typeahead').bind('typeahead:beforeselect', function(ev, suggestion) { 
    //   console.log('>> typeahead:beforeselect triggered'); 
    //   console.log("val is now set to:" + $(this).typeahead('val')  );
    //   console.log("ev.target.value is now set to:" + ev.target.value);
    //   ev.target.saved_value = ev.target.value;
    // }  );


    // DEBUGGING
    // $('.best_bets_typeahead').bind('typeahead:close', function(ev, suggestion) {
    //   console.log('>> typeahead:close'); 
    // });
    $('.best_bets_typeahead').bind('typeahead:active', function(ev, suggestion) {
      console.log('>> typeahead:active');
      ev.preventDefault();
    });

    $('.best_bets_typeahead').bind('typeahead:open', function(ev, suggestion) {  console.log('>> typeahead:open'); });

    $('.best_bets_typeahead').bind('typeahead:change', function(ev, suggestion) {  console.log('>> typeahead:change'); });

    // $('.best_bets_typeahead').bind('typeahead:render', function(ev, suggestion) {  console.log('>> typeahead:render'); });
    // $('.best_bets_typeahead').bind('typeahead:autocomplete', function(ev, suggestion) {  console.log('>> typeahead:autocomplete'); });
    // $('.best_bets_typeahead').bind('blurred', function(ev, suggestion) {  console.log('>> blurred'); });
    // $('.best_bets_typeahead').bind('typeahead:onBlurred', function(ev, suggestion) {  console.log('>> typeahead:onBlurred'); });
    // $('.best_bets_typeahead').bind('typeahead:_onBlurred', function(ev, suggestion) {  console.log('>> typeahead:_onBlurred'); });

    // Initializing the Typeahead looses element focus
    setTimeout(function(){
        $('.best_bets_typeahead.tt-input').focus();
    }, 250);

  }


  // nice formatting of each best-bet suggestion
  function buildSnippet(data) {
    var title = "<span>" + data.title + "</span>\n";
    var description = "";
    if (typeof(data.description) != 'undefined' && data.description.length > 0) {
      var description = "<span> - " + data.description + "</span>\n";
    }
    var url   = "";
    if (typeof(data.url) != 'undefined' && data.url.length > 0) {
      url = "<br><a href='" + data.url + "'>" + data.url + "</a>\n";
    }
    var snippet = "<div class='best-bets-snippet'>\n" + title + description + "\n" + url + "</div>\n";
    return snippet;
  };

});

