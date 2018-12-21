module SavedListsHelper
  def get_full_url(list)
    root_url.sub(/\/$/, '') + list.url
  end

  def get_permissions_label(permissions)
    case permissions
    when 'private'
      html = "<span class='label label-info'>private</span>"
    when 'public'
      html = "<span class='label label-warning'>public</span>"
    else
      raise "get_permissions_label: unexpected value: #{permission}"
      end
    html.html_safe
  end
end
